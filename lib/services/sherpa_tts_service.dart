import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'robot_service.dart';

class SherpaTtsService {
  static OfflineTts? _englishTts;
  static OfflineTts? _hindiTts;
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _isInitialized = false;
  static String currentVoiceId = 'vits-piper-en_US-kristin-medium';

  static Future<void> initialize() async {
    if (_isInitialized) return;
    initBindings();
    try {
      final appDir = await getApplicationDocumentsDirectory();
      
      final prefs = await SharedPreferences.getInstance();
      currentVoiceId = prefs.getString('selected_english_voice') ?? 'vits-piper-en_US-kristin-medium';

      final hiDir = '${appDir.path}/vits-piper-hi_IN-rohan-medium';

      Future<void> extractModel(String assetPath, String checkDir, String onnxFile) async {
        if (await Directory(checkDir).exists()) {
          if (await File(onnxFile).exists()) {
            return;
          } else {
            debugPrint("Corrupted TTS model cache found. Deleting $checkDir...");
            await Directory(checkDir).delete(recursive: true);
          }
        }
        
        debugPrint("Extracting $assetPath to ${appDir.path}...");
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        
        await compute(_decodeAndSaveArchive, {
          'bytes': bytes,
          'appDirPath': appDir.path,
        });
      }

      // Default fallback bundled model extraction
      final enDir = '${appDir.path}/vits-piper-en_US-kristin-medium';
      await extractModel('assets/tts/vits-piper-en_US-kristin-medium.tar.bz2', enDir, '$enDir/en_US-kristin-medium.onnx');
      await extractModel('assets/tts/vits-piper-hi_IN-rohan-medium.tar.bz2', hiDir, '$hiDir/hi_IN-rohan-medium.onnx');

      // Initialize English Engine based on selected voice
      await _initEnglishEngine(currentVoiceId);

      // Initialize Hindi Engine
      _hindiTts = OfflineTts(
        OfflineTtsConfig(
          model: OfflineTtsModelConfig(
            vits: OfflineTtsVitsModelConfig(
              model: '$hiDir/hi_IN-rohan-medium.onnx',
              tokens: '$hiDir/tokens.txt',
              dataDir: '$hiDir/espeak-ng-data',
            ),
            provider: "cpu",
            numThreads: 2,
          ),
        ),
      );

      _isInitialized = true;
      debugPrint("Sherpa TTS Engines Initialized successfully!");
    } catch (e, stacktrace) {
      debugPrint("Failed to initialize Sherpa TTS: $e\n$stacktrace");
    }
  }

  static Future<void> _initEnglishEngine(String voiceId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = '${appDir.path}/$voiceId';
    final baseName = voiceId.replaceFirst('vits-piper-', '');
    final onnxFile = '$modelDir/$baseName.onnx';

    // If the selected voice model file does not exist, fallback to Kristin
    if (!File(onnxFile).existsSync()) {
      debugPrint("TTS Model $onnxFile not found. Falling back to default Kristin.");
      await _initEnglishEngine('vits-piper-en_US-kristin-medium');
      return;
    }

    _englishTts?.free();
    _englishTts = OfflineTts(
      OfflineTtsConfig(
        model: OfflineTtsModelConfig(
          vits: OfflineTtsVitsModelConfig(
            model: onnxFile,
            tokens: '$modelDir/tokens.txt',
            dataDir: '$modelDir/espeak-ng-data',
          ),
          provider: "cpu",
          numThreads: 2,
        ),
      ),
    );
  }

  static Future<void> changeVoice(String voiceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_english_voice', voiceId);
    currentVoiceId = voiceId;
    await _initEnglishEngine(voiceId);
  }

  static Future<void> speak(String text, {bool isHindi = false}) async {
    if (!_isInitialized) return;
    try {
      final tts = isHindi ? _hindiTts : _englishTts;
      if (tts == null) return;

      // Generate PCM audio
      final audio = tts.generate(text: text);
      if (audio == null || audio.samples.isEmpty) return;

      // Save as WAV (we might still need it for fallback or logging)
      final wavPath = await _savePcmToWav(audio.samples, audio.sampleRate);

      if (RobotService.isConnected) {
        // Stream directly to Robot I2S
        final int16Data = Int16List(audio.samples.length);
        double volumeBoost = 1.2; // Safe 120% Software Volume Boost (prevents static clipping!)
        for (int i = 0; i < audio.samples.length; i++) {
          int val = (audio.samples[i] * volumeBoost * 32767).round();
          if (val > 32767) val = 32767;
          if (val < -32768) val = -32768;
          int16Data[i] = val;
        }
        final byteData = int16Data.buffer.asUint8List();
        
        RobotService.sendAudioStart();
        
        int chunkSize = 1000; // MUST be under 1400 bytes to prevent WebSocket fragmentation!
        for (int i = 0; i < byteData.length; i += chunkSize) {
          int end = (i + chunkSize < byteData.length) ? i + chunkSize : byteData.length;
          RobotService.streamAudioChunk(byteData.sublist(i, end));
          // Tiny 1ms yield to prevent Flutter UI freezing during massive burst transmission
          await Future.delayed(const Duration(milliseconds: 1));
        }
        
        RobotService.sendAudioEnd();
      } else {
        // Play locally if robot is not connected
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(wavPath));
      }
      
    } catch (e) {
      debugPrint("Sherpa Playback Error: $e");
    }
  }

  static Future<void> stop() async {
    await _audioPlayer.stop();
  }

  static Future<String> _savePcmToWav(Float32List pcmData, int sampleRate) async {
    final int16Data = Int16List(pcmData.length);
    for (int i = 0; i < pcmData.length; i++) {
      int val = (pcmData[i] * 32767).round();
      if (val > 32767) val = 32767;
      if (val < -32768) val = -32768;
      int16Data[i] = val;
    }
    
    final int byteRate = sampleRate * 1 * 2;
    final int dataSize = int16Data.length * 2;
    final int fileSize = 36 + dataSize;
    
    final builder = BytesBuilder();
    builder.add('RIFF'.codeUnits);
    builder.add(_int32ToBytes(fileSize));
    builder.add('WAVE'.codeUnits);
    builder.add('fmt '.codeUnits);
    builder.add(_int32ToBytes(16));
    builder.add(_int16ToBytes(1));
    builder.add(_int16ToBytes(1));
    builder.add(_int32ToBytes(sampleRate));
    builder.add(_int32ToBytes(byteRate));
    builder.add(_int16ToBytes(2));
    builder.add(_int16ToBytes(16));
    builder.add('data'.codeUnits);
    builder.add(_int32ToBytes(dataSize));
    builder.add(int16Data.buffer.asUint8List());
    
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tts_sherpa_temp.wav');
    await file.writeAsBytes(builder.toBytes(), flush: true);
    return file.path;
  }

  static Uint8List _int32ToBytes(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  }

  static Uint8List _int16ToBytes(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
  }
}

Future<void> _decodeAndSaveArchive(Map<String, dynamic> params) async {
  final bytes = params['bytes'] as Uint8List;
  final appDirPath = params['appDirPath'] as String;
  
  final tarBytes = BZip2Decoder().decodeBytes(bytes);
  final archive = TarDecoder().decodeBytes(tarBytes);
  
  for (final file in archive) {
    final filename = file.name;
    if (file.isFile) {
      final outFile = File('$appDirPath/$filename');
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    } else {
      await Directory('$appDirPath/$filename').create(recursive: true);
    }
  }
}
