import sys, re

file_path = r"s:\Projects\IRA\lib\widgets\video_stream_mock.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. replace _httpClient and _mjpegActive
content = content.replace("  HttpClient? _httpClient;\n  bool _mjpegActive = false;", "  StreamSubscription<Uint8List>? _videoSub;")

# 2. replace _disconnectStream
old_disconnect = """  void _disconnectStream() {
    _mjpegActive = false;
    _httpClient?.close(force: true);
    _httpClient = null;
  }"""
new_disconnect = """  void _disconnectStream() {
    _videoSub?.cancel();
    _videoSub = null;
  }"""
content = content.replace(old_disconnect, new_disconnect)

# 3. replace _connectStream
# We use a regex to match the old _connectStream block
old_connect_re = r"  Future<void> _connectStream\(\) async \{.*?\n  \}\n\n  /// Parse"
new_connect = """  void _connectStream() {
    _disconnectStream();
    _videoSub = RobotService.videoStream.listen((frame) {
      if (mounted) {
        setState(() => _currentFrame = frame);
        VideoStreamMock.latestFrame = frame;
        _tryParseFrameSize(frame);
        if (_isRecording && _recFrames.length < _maxFrames) _recFrames.add(frame);
        
        // ── AI Vision Processing ──
        if (_aiVisionActive) {
          _frameCount++;
          if (_frameCount % 10 == 0) { // Approx 3 FPS sampling
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
       print("Video stream error: $e");
    });
  }

  /// Parse"""
content = re.sub(old_connect_re, new_connect, content, flags=re.DOTALL)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Patch applied to video_stream_mock.dart")
