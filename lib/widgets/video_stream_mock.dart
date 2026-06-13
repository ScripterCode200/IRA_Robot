import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import '../services/ai_vision_service.dart';
import '../services/image_enhancer_service.dart';
import '../services/robot_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Minimal MJPEG → AVI writer (pure Dart, no native dependencies)
// AVI RIFF format with MJPG codec — plays natively on Android/Windows/VLC
// ─────────────────────────────────────────────────────────────────────────────
class _AviMjpegWriter {
  // Little-endian helpers

  static void _writeFCC(List<int> buf, String fourCC) {
    for (int i = 0; i < 4; i++) buf.add(fourCC.codeUnitAt(i));
  }

  static void _writeU32le(List<int> buf, int v) {
    buf.add(v & 0xFF);
    buf.add((v >> 8) & 0xFF);
    buf.add((v >> 16) & 0xFF);
    buf.add((v >> 24) & 0xFF);
  }

  static void _writeU16le(List<int> buf, int v) {
    buf.add(v & 0xFF);
    buf.add((v >> 8) & 0xFF);
  }

  /// Builds a complete AVI file from a list of JPEG frames.
  /// [fps] = frames per second to embed in the header (display rate).
  static Uint8List build(List<Uint8List> frames, int fps, int width, int height) {
    if (frames.isEmpty) return Uint8List(0);

    // ── 1. Build the movi chunk (raw JPEG frames wrapped in '00dc' chunks) ──
    final moviData = <int>[];
    final offsets = <int>[]; // byte offset of each frame inside moviData
    for (final frame in frames) {
      // Pad each frame to even length (AVI requirement)
      offsets.add(moviData.length);
      _writeFCC(moviData, '00dc'); // stream 0, compressed video
      _writeU32le(moviData, frame.length);
      moviData.addAll(frame);
      if (frame.length % 2 != 0) moviData.add(0); // padding byte
    }

    // ── 2. Build idx1 index chunk ─────────────────────────────────────────
    // idx1 entries: FOURCC, flags(AVIF_KEYFRAME=0x10), offset, size
    // offset is relative to start of movi data (+4 bytes for 'movi' FOURCC skip)
    final idx1Data = <int>[];
    for (int i = 0; i < frames.length; i++) {
      _writeFCC(idx1Data, '00dc');
      _writeU32le(idx1Data, 0x10); // AVIIF_KEYFRAME
      _writeU32le(idx1Data, offsets[i] + 4); // +4 to skip 'movi' FOURCC
      _writeU32le(idx1Data, frames[i].length);
    }

    // ── 3. Compute sizes ──────────────────────────────────────────────────
    final moviChunkSize = moviData.length + 4; // +4 for 'movi' FCC
    final idx1ChunkSize = idx1Data.length;

    // AVI header block: avih (56 bytes) + one strl LIST with strh+strf
    // strh = 56 bytes, strf = BITMAPINFOHEADER = 40 bytes
    const avihSize = 56;
    const strhSize = 56;
    const strfSize = 40;
    // LIST 'hdrl': avih chunk + LIST 'strl'
    // LIST 'strl': strh chunk + strf chunk
    const strlListSize = 4 + (8 + strhSize) + (8 + strfSize); // 'strl' + strh chunk + strf chunk
    const hdrlListSize = 4 + (8 + avihSize) + (8 + strlListSize); // 'hdrl' + avih + strl list

    // Total RIFF size: 4 (RIFF type 'AVI ') + hdrl + movi + idx1
    final riffSize = 4
        + (8 + hdrlListSize)        // LIST hdrl
        + (8 + moviChunkSize)       // LIST movi
        + (8 + idx1ChunkSize);      // idx1

    final buf = <int>[];

    // ── RIFF AVI header ───────────────────────────────────────────────────
    _writeFCC(buf, 'RIFF');
    _writeU32le(buf, riffSize);
    _writeFCC(buf, 'AVI ');

    // ── LIST hdrl ─────────────────────────────────────────────────────────
    _writeFCC(buf, 'LIST');
    _writeU32le(buf, hdrlListSize);
    _writeFCC(buf, 'hdrl');

    // avih chunk (main AVI header)
    _writeFCC(buf, 'avih');
    _writeU32le(buf, avihSize);
    _writeU32le(buf, 1000000 ~/ fps);      // microseconds per frame
    _writeU32le(buf, 0);                    // max bytes per second (0 = unknown)
    _writeU32le(buf, 0);                    // padding granularity
    _writeU32le(buf, 0x10 | 0x100);        // flags: HASINDEX | ISINTERLEAVED
    _writeU32le(buf, frames.length);        // total frames
    _writeU32le(buf, 0);                    // initial frames
    _writeU32le(buf, 1);                    // number of streams
    _writeU32le(buf, 0);                    // suggested buffer size
    _writeU32le(buf, width);               // width
    _writeU32le(buf, height);              // height
    for (int i = 0; i < 4; i++) _writeU32le(buf, 0); // reserved

    // LIST strl
    _writeFCC(buf, 'LIST');
    _writeU32le(buf, strlListSize);
    _writeFCC(buf, 'strl');

    // strh chunk (stream header)
    _writeFCC(buf, 'strh');
    _writeU32le(buf, strhSize);
    _writeFCC(buf, 'vids');               // stream type = video
    _writeFCC(buf, 'MJPG');               // MJPEG codec
    _writeU32le(buf, 0);                  // flags
    _writeU16le(buf, 0);                  // priority
    _writeU16le(buf, 0);                  // language
    _writeU32le(buf, 0);                  // initial frames
    _writeU32le(buf, 1);                  // scale (denominator)
    _writeU32le(buf, fps);                // rate / scale = fps
    _writeU32le(buf, 0);                  // start
    _writeU32le(buf, frames.length);      // length (# frames)
    _writeU32le(buf, 0);                  // suggested buffer size
    _writeU32le(buf, 0);                  // quality
    _writeU32le(buf, 0);                  // sample size
    // rcFrame: left top right bottom
    _writeU16le(buf, 0); _writeU16le(buf, 0);
    _writeU16le(buf, width); _writeU16le(buf, height);

    // strf chunk (BITMAPINFOHEADER for MJPEG)
    _writeFCC(buf, 'strf');
    _writeU32le(buf, strfSize);
    _writeU32le(buf, strfSize);           // biSize
    _writeU32le(buf, width);              // biWidth
    _writeU32le(buf, height);             // biHeight
    _writeU16le(buf, 1);                  // biPlanes
    _writeU16le(buf, 24);                 // biBitCount
    _writeFCC(buf, 'MJPG');               // biCompression
    _writeU32le(buf, width * height * 3); // biSizeImage
    _writeU32le(buf, 0);                  // biXPelsPerMeter
    _writeU32le(buf, 0);                  // biYPelsPerMeter
    _writeU32le(buf, 0);                  // biClrUsed
    _writeU32le(buf, 0);                  // biClrImportant

    // ── LIST movi ─────────────────────────────────────────────────────────
    _writeFCC(buf, 'LIST');
    _writeU32le(buf, moviChunkSize);
    _writeFCC(buf, 'movi');
    buf.addAll(moviData);

    // ── idx1 chunk ────────────────────────────────────────────────────────
    _writeFCC(buf, 'idx1');
    _writeU32le(buf, idx1ChunkSize);
    buf.addAll(idx1Data);

    return Uint8List.fromList(buf);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class VideoStreamMock extends StatefulWidget {
  final bool isConnected;
  final bool isVisible;
  static Uint8List? latestFrame;
  const VideoStreamMock({super.key, required this.isConnected, this.isVisible = true});

  @override
  State<VideoStreamMock> createState() => _VideoStreamMockState();
}

class _VideoStreamMockState extends State<VideoStreamMock>
    with SingleTickerProviderStateMixin {

  // ── Vision ────────────────────────────────────────────────────────────────
  bool _isNightVision = false;
  bool _isThermalVision = false;
  bool _aiVisionActive = false;
  bool _enhanceCaptures = false;
  int _frameCount = 0;


  // ── Recording / Capture ────────────────────────────────────────────────────
  bool _isRecording = false;
  bool _isSaving = false;
  int _recSeconds = 0;
  Timer? _recTimer;
  final List<Uint8List> _recFrames = [];
  static const int _maxFrames = 1800; // ~60 s at 30 fps
  // Detected frame dimensions (parsed from JPEG SOF marker or estimated)
  int _frameWidth = 320;
  int _frameHeight = 240;

  // ── HUD Simulation ────────────────────────────────────────────────────────
  int _streamFps = 30;

  // ── MJPEG Stream ──────────────────────────────────────────────────────────
  final ValueNotifier<Uint8List?> _currentFrameNotifier = ValueNotifier<Uint8List?>(null);
  Uint8List? _latestRawFrame; // Keep raw bytes for snapshot/recording
  StreamSubscription<Uint8List>? _videoSub;
  int _lastFrameTime = 0;
  
  // On-Demand (Push) Strategy Variables
  bool _isWaitingForFrame = false;
  @override
  void initState() {
    super.initState();

    if (widget.isConnected && widget.isVisible) _connectStream();
  }

  @override
  void didUpdateWidget(VideoStreamMock old) {
    super.didUpdateWidget(old);
    final shouldConnect = widget.isConnected && widget.isVisible;
    final wasConnected = old.isConnected && old.isVisible;
    if (shouldConnect && !wasConnected) _connectStream();
    else if (!shouldConnect && wasConnected) _disconnectStream();
  }

  @override
  void dispose() {
    _disconnectStream();
    _currentFrameNotifier.value = null;
    _recTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MJPEG connection
  // ─────────────────────────────────────────────────────────────────────────
  void _disconnectStream() {
    RobotService.sendRawText("stream_stop");
    _videoSub?.cancel();
    _videoSub = null;
  }

  void _connectStream() {
    _disconnectStream();
    
    // Initiate continuous PUSH stream from ESP32
    RobotService.sendRawText("stream_start");

    _videoSub = RobotService.videoStream.listen((frame) {
      _isWaitingForFrame = false; // Acknowledged! Ready for next request
      if (mounted) {
        final now = DateTime.now().millisecondsSinceEpoch;
        _lastFrameTime = now;
        
        // Store raw bytes for snapshot/recording
        _latestRawFrame = frame;
        VideoStreamMock.latestFrame = frame;
        _tryParseFrameSize(frame);
        
        if (_isRecording && _recFrames.length < _maxFrames) _recFrames.add(frame);
        
        // AGGRESSIVE MEMORY MANAGEMENT
        // Flutter's Image.memory caches uncompressed bitmaps. A single 640x480 frame is 1.2MB.
        // At 20 FPS, this will fill the 100MB cache limit in 4 seconds and cause massive GC stuttering!
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();

        _currentFrameNotifier.value = frame; 
        // ── AI Vision Processing ──
        if (_aiVisionActive) {
          _frameCount++;
          if (_frameCount % 10 == 0) {
            AIVisionService.processFrame(frame).then((action) {
              if (action != null && mounted) {
                RobotService.sendHttpCommand(action);
                _snack("AI DETECTED: ${action.replaceAll('action_', '').toUpperCase()} 🤖");
              }
            });
          }
        }
      }
    }, onError: (e) {
       _isWaitingForFrame = false;
       print("Video stream error: $e");
    });
  }

  /// Parse width/height from JPEG SOF0/SOF2 marker (0xFFC0 / 0xFFC2)
  void _tryParseFrameSize(Uint8List jpeg) {
    if (_frameWidth > 0 && _frameHeight > 0) return; // Only parse once
    try {
      for (int i = 0; i < jpeg.length - 9; i++) {
        if (jpeg[i] == 0xFF && (jpeg[i + 1] == 0xC0 || jpeg[i + 1] == 0xC2)) {
          final h = (jpeg[i + 5] << 8) | jpeg[i + 6];
          final w = (jpeg[i + 7] << 8) | jpeg[i + 8];
          if (w > 0 && h > 0) { _frameWidth = w; _frameHeight = h; }
          return;
        }
      }
    } catch (_) {}
  }



  // ─────────────────────────────────────────────────────────────────────────
  // Snapshot
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _captureSnapshot() async {
    if (_latestRawFrame == null) {
      _snack("No camera frame — is the stream live?", error: true); return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);
    try {
      Uint8List finalFrame = _latestRawFrame!;
      if (_enhanceCaptures) {
        _snack("Applying AI Image Enhancement...");
        finalFrame = await ImageEnhancerService.enhanceImage(finalFrame);
      }
      
      // gal handles permissions internally on Android 13+
      await Gal.putImageBytes(finalFrame, album: 'IRA Robot');
      _snack("📸 Photo saved to Gallery");
    } on GalException catch (e) {
      if (e.type == GalExceptionType.accessDenied) {
        _snack("Storage permission denied", error: true);
      } else {
        _snack("Could not save photo: ${e.type.message}", error: true);
      }
    } catch (e) {
      _snack("Error: $e", error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Video Recording
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _toggleRecording() async {
    HapticFeedback.heavyImpact();

    if (_isRecording) {
      // ── STOP ──────────────────────────────────────────────────────────
      _recTimer?.cancel();
      setState(() { _isRecording = false; _isSaving = true; });
      await _saveRecordingAsAvi();
      setState(() => _isSaving = false);
    } else {
      // ── START ─────────────────────────────────────────────────────────
      _recFrames.clear();
      _recSeconds = 0;
      setState(() => _isRecording = true);
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecording) return;
        setState(() => _recSeconds++);
      });
      _snack("🔴 Recording… tap STOP to save");
    }
  }

  Future<void> _saveRecordingAsAvi() async {
    final count = _recFrames.length;
    if (count == 0) {
      _snack("No frames captured — was camera streaming?", error: true); return;
    }

    try {
      List<Uint8List> processedFrames = _recFrames;
      if (_enhanceCaptures) {
        _snack("Enhancing $count frames with AI (This may take a while)...");
        processedFrames = [];
        for (int i = 0; i < count; i++) {
          processedFrames.add(await ImageEnhancerService.enhanceImage(_recFrames[i]));
        }
      }

      // Build MJPEG AVI in memory
      final aviBytes = _AviMjpegWriter.build(processedFrames, _streamFps, _frameWidth, _frameHeight);
      _recFrames.clear();

      // Write to temp file, then hand off to gal
      final tmp = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tmp.path}/IRA_REC_$ts.avi');
      await file.writeAsBytes(aviBytes);

      await Gal.putVideo(file.path, album: 'IRA Robot');
      await file.delete();
      _snack("🎬 Video saved to Gallery ($count frames, ${_recSeconds}s)");
    } on GalException catch (e) {
      _recFrames.clear();
      if (e.type == GalExceptionType.accessDenied) {
        _snack("Storage permission denied", error: true);
      } else {
        _snack("Gallery save failed: ${e.type.message}", error: true);
      }
    } catch (e) {
      _recFrames.clear();
      _snack("Error saving video: $e", error: true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Snackbar helper
  // ─────────────────────────────────────────────────────────────────────────
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
        backgroundColor: error ? Colors.red.shade900.withOpacity(0.95) : const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    Color hud = const Color(0xFF00F2FE);
    if (!widget.isConnected) hud = Colors.red;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildViewport(hud),
        const SizedBox(height: 8),
        _buildControlsPanel(hud),
      ],
    );
  }

  Widget _buildViewport(Color hud) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF020617),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hud.withOpacity(0.35), width: 1.5),
          boxShadow: [BoxShadow(color: hud.withOpacity(0.12), blurRadius: 16, spreadRadius: 2)],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBase(),
            // REC badge
            if (_isRecording) Positioned(top: 10, left: 12,
              child: Row(children: [
                _FlashingDot(color: Colors.red),
                const SizedBox(width: 6),
                Text("REC  ${_fmtDur(_recSeconds)}",
                  style: const TextStyle(color: Colors.red, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1)),
              ])),
            // Encoding overlay
            if (_isSaving) Container(
              color: Colors.black.withOpacity(0.72),
              child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)))),
                SizedBox(height: 10),
                Text("BUILDING AVI FILE...", style: TextStyle(color: Color(0xFF00F2FE), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ])),
            ),
            // LIVE badge
            if (widget.isConnected && !_isRecording) Positioned(top: 10, right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: hud.withOpacity(0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: hud.withOpacity(0.5))),
                child: Text("● LIVE", style: TextStyle(color: hud, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsPanel(Color hud) {
    if (!widget.isConnected) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          icon: const Icon(Icons.camera_alt_rounded),
          color: const Color(0xFF00F2FE),
          onPressed: (_latestRawFrame != null && !_isSaving) ? _captureSnapshot : null,
        ),
        IconButton(
          icon: Icon(_isRecording ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded),
          color: _isRecording ? Colors.red : const Color(0xFFEC4899),
          onPressed: !_isSaving ? _toggleRecording : null,
        ),
      ],
    );
  }

  Widget _buildBase() {
    if (!widget.isConnected) {
      return Container(color: const Color(0xFF020617), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 52, height: 52,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.withOpacity(0.08), border: Border.all(color: Colors.red.withOpacity(0.3), width: 1.5)),
          child: const Icon(Icons.videocam_off_rounded, color: Colors.redAccent, size: 26)),
        const SizedBox(height: 12),
        const Text("NO SIGNAL", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 3, fontFamily: 'monospace')),
        const SizedBox(height: 4),
        Text("Connect to robot Wi-Fi to activate feed", style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 9)),
      ])));
    }
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: _currentFrameNotifier,
      builder: (context, frame, child) {
        if (frame != null) {
          return Transform.rotate(
            angle: math.pi, 
            child: Image.memory(
              frame, 
              fit: BoxFit.cover, 
              gaplessPlayback: true,
            )
          );
        }
        return Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _GridBackgroundPainter(isNightVision: _isNightVision, isThermal: _isThermalVision)),
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)))),
            const SizedBox(height: 10),
            Text("CONNECTING TO STREAM...", style: TextStyle(color: const Color(0xFF00F2FE).withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontFamily: 'monospace')),
            const SizedBox(height: 3),
            Text("mDNS LOCAL STREAM", style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 8, fontFamily: 'monospace')),
          ])),
        ]);
      },
    );
  }

  String _fmtDur(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
class _GridBackgroundPainter extends CustomPainter {
  final bool isNightVision, isThermal;
  _GridBackgroundPainter({required this.isNightVision, required this.isThermal});
  @override
  void paint(Canvas canvas, Size size) {
    const gs = 40.0;
    final lp = Paint()..color = (isNightVision ? Colors.green : (isThermal ? Colors.orange : const Color(0xFF00F2FE))).withOpacity(0.04)..strokeWidth = 1.0;
    for (double y = 0; y < size.height; y += gs) canvas.drawLine(Offset(0, y), Offset(size.width, y), lp);
    for (double x = 0; x < size.width; x += gs) canvas.drawLine(Offset(x, 0), Offset(x, size.height), lp);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()
      ..shader = RadialGradient(colors: [Colors.transparent, Colors.black.withOpacity(0.6)], radius: 1.2).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
  }
  @override bool shouldRepaint(covariant _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
class _FlashingDot extends StatefulWidget {
  final Color color; const _FlashingDot({required this.color});
  @override State<_FlashingDot> createState() => _FlashingDotState();
}
class _FlashingDotState extends State<_FlashingDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) => FadeTransition(opacity: _c,
    child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color,
      boxShadow: [BoxShadow(color: widget.color.withOpacity(0.6), blurRadius: 4, spreadRadius: 1)])));
}
