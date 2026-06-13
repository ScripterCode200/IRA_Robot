import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

class TtsVoice {
  final String id;
  final String displayName;
  final String description;

  const TtsVoice({
    required this.id,
    required this.displayName,
    required this.description,
  });

  String get downloadUrl =>
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$id.tar.bz2';
}

class TtsDownloadService {
  static const List<TtsVoice> availableVoices = [
    TtsVoice(
      id: 'vits-piper-en_US-kristin-medium',
      displayName: 'Kristin (Default)',
      description: 'Clear, medium-paced female voice.',
    ),
    TtsVoice(
      id: 'vits-piper-en_US-amy-medium',
      displayName: 'Amy (Expressive)',
      description: 'Bright and highly expressive female voice.',
    ),
    TtsVoice(
      id: 'vits-piper-en_GB-jenny_dioco-medium',
      displayName: 'Jenny (Friendly)',
      description: 'Warm and friendly British female voice.',
    ),
    TtsVoice(
      id: 'vits-piper-en_US-libritts-high',
      displayName: 'LibriTTS (Multi-Speaker)',
      description: 'High-quality multi-speaker dataset voice.',
    ),
  ];

  static Future<bool> isVoiceDownloaded(String voiceId) async {
    // Kristin is bundled as an asset
    if (voiceId == 'vits-piper-en_US-kristin-medium') return true;

    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = '${appDir.path}/$voiceId';
    final onnxFile = '$modelDir/${voiceId.replaceFirst("vits-piper-", "")}.onnx';

    return File(onnxFile).existsSync();
  }

  static Future<void> downloadAndExtractVoice(
    TtsVoice voice,
    Function(double) onProgress,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = '${appDir.path}/${voice.id}';
    final tempArchive = '${appDir.path}/${voice.id}.tar.bz2';

    try {
      if (await Directory(modelDir).exists()) {
        await Directory(modelDir).delete(recursive: true);
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(voice.downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception("Failed to download voice. HTTP ${response.statusCode}");
      }

      final contentLength = response.contentLength ?? 0;
      int receivedBytes = 0;

      final file = File(tempArchive);
      final sink = file.openWrite();

      await for (var chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (contentLength > 0) {
          // Progress up to 80% for download
          onProgress((receivedBytes / contentLength) * 0.8);
        }
      }
      await sink.close();

      // Extraction phase (remaining 20%)
      onProgress(0.85); // Extraction started
      final bytes = await file.readAsBytes();
      await compute(_decodeAndSaveArchive, {
        'bytes': bytes,
        'appDirPath': appDir.path,
      });

      // Cleanup
      if (await file.exists()) {
        await file.delete();
      }
      
      onProgress(1.0); // Complete
    } catch (e) {
      debugPrint("Voice Download Error: $e");
      rethrow;
    }
  }

  static Future<void> _decodeAndSaveArchive(Map<String, dynamic> args) async {
    final bytes = args['bytes'] as Uint8List;
    final appDirPath = args['appDirPath'] as String;

    final bzip2Decoder = BZip2Decoder();
    final tarBytes = bzip2Decoder.decodeBytes(bytes);
    final tarArchive = TarDecoder().decodeBytes(tarBytes);

    for (final file in tarArchive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File('$appDirPath/$filename');
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(data);
      } else {
        Directory('$appDirPath/$filename').createSync(recursive: true);
      }
    }
  }
}
