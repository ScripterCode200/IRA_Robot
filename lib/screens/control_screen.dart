import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import '../widgets/joystick.dart';
import '../services/robot_service.dart';
import 'dart:convert';
import '../widgets/video_stream_mock.dart';

import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/local_ai_service.dart';
import '../services/cloud_ai_service.dart';
import '../services/sherpa_tts_service.dart';

class ControlScreen extends StatefulWidget {
  final bool isConnected;
  final bool isVisible;

  const ControlScreen({
    super.key,
    required this.isConnected,
    this.isVisible = true,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  // Drive variables
  double _driveSpeed = 0.0;
  double _driveTurn = 0.0;

  // States
  bool _headlights = false;
  bool _siren = false;
  bool _cameraActive = true;
  bool _screenActive = true;
  bool _isHighQuality = false;
  String _activeDir = '';
  
  // Servo State
  double _servoAngle = 100.0;
  
  // Vector data logging (what is sent to ESP32)
  String _lastTxPayload = "STANDBY";

  // Voice variables
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _transcribedText = "";
  Completer<String>? _speechCompleter;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    _speechAvailable = await _speech.initialize();
  }

  // --- Voice Button Logic (Hold to Record, Release to Transcribe) ---
  void _startListening() async {
    if (!_speechAvailable) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _isListening = true;
      _transcribedText = "";
    });
    _speechCompleter = Completer<String>();
    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isNotEmpty) {
          _transcribedText = words;
          if (!(_speechCompleter?.isCompleted ?? true)) {
            _speechCompleter!.complete(words);
          }
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 30),
      partialResults: true,
    );
  }

  void _stopListening() async {
    if (!_isListening) return;
    HapticFeedback.lightImpact();

    // Stop mic — triggers STT to finalize
    await _speech.stop();

    setState(() => _isListening = false);

    // Wait up to 2s for the Completer to receive the transcription
    String result = '';
    if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
      result = await _speechCompleter!.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => _transcribedText,
      );
    } else {
      result = _transcribedText;
    }
    _speechCompleter = null;

    if (result.isNotEmpty) {
      debugPrint('✅ Control STT: "$result" → Sending to AI...');
      _processVoiceCommand(result);
    }
  }

  void _processVoiceCommand(String text) async {
    final prefs = await SharedPreferences.getInstance();
    bool isOfflineMode = prefs.getBool('isOfflineMode') ?? true;
    
    AiCommandResponse? response;
    if (isOfflineMode) {
      response = await LocalAiService.parseRobotCommand(text);
    } else {
      response = await CloudAiService.parseRobotCommand(text);
    }

    if (response != null && mounted) {
      if (response.reply.isNotEmpty) {
        SherpaTtsService.speak(response.reply, isHindi: false);
      }
      for (var cmd in response.commands) {
        RobotService.sendHttpCommand(cmd);
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } else if (mounted) {
      // Offline fallback simple parsing
      final lowerText = text.toLowerCase().trim();
      if (lowerText.contains("forward") || lowerText.contains("straight")) {
        RobotService.sendUdpPayload("M:0.00,0.80;G:0,0;H:${_headlights ? 1 : 0};S:0");
      } else if (lowerText.contains("backward") || lowerText.contains("reverse")) {
        RobotService.sendUdpPayload("M:0.00,-0.80;G:0,0;H:${_headlights ? 1 : 0};S:0");
      } else if (lowerText.contains("left")) {
        RobotService.sendUdpPayload("M:-0.80,0.00;G:0,0;H:${_headlights ? 1 : 0};S:0");
      } else if (lowerText.contains("right")) {
        RobotService.sendUdpPayload("M:0.80,0.00;G:0,0;H:${_headlights ? 1 : 0};S:0");
      } else if (lowerText.contains("stop") || lowerText.contains("halt")) {
        RobotService.sendUdpPayload("M:0.00,0.00;G:0,0;H:${_headlights ? 1 : 0};S:0");
      } else if (lowerText.contains("horn") || lowerText.contains("beep")) {
        RobotService.sendHttpCommand("horn");
      }
    }
  }

  void _sendCommand() {
    if (!widget.isConnected) {
      setState(() {
        _lastTxPayload = "DISCONNECTED";
      });
      return;
    }
    
    // No scaling needed, we want 100% raw acceleration directly to the pins!
    double driveX = _driveTurn;
    double driveY = _driveSpeed;
    
    // Formatting the command payload: "M:turn,speed;G:servo,0;H:0/1;S:0/1"
    setState(() {
      _lastTxPayload = "M:${driveX.toStringAsFixed(2)},${driveY.toStringAsFixed(2)};G:${_servoAngle.toInt()},0;H:${_headlights ? 1 : 0};S:${_siren ? 1 : 0}";
    });
    RobotService.sendRawText(_lastTxPayload); // Send via TCP WebSocket!
  }

  void _startDriving() {
    _sendCommand(); // Send Start Event
  }

  void _stopDriving() {
    _sendCommand(); // Send Stop Event
  }

  void _updateServo(double angle) {
    setState(() => _servoAngle = angle);
    _sendCommand();
  }

  void _triggerHorn() {
    HapticFeedback.heavyImpact();
    RobotService.sendHttpCommand('horn');
    
    if (widget.isConnected) {
      // Synthesize a 0.35s digital car horn (Minor Third Chord: 400Hz + 480Hz)
      int sampleRate = 22050;
      double duration = 0.35;
      int samples = (sampleRate * duration).toInt();
      Int16List int16Data = Int16List(samples);
      
      for (int i = 0; i < samples; i++) {
        double t = i / sampleRate;
        double wave1 = math.sin(2 * math.pi * 400 * t); // Base
        double wave2 = math.sin(2 * math.pi * 480 * t); // Minor third
        double wave3 = math.sin(2 * math.pi * 800 * t); // Harmonic overtone
        
        // Mix and overdrive for a harsh 'honk' sound
        double mixed = (wave1 + wave2 * 0.8 + wave3 * 0.4) * 0.9;
        if (mixed > 1.0) mixed = 1.0;
        if (mixed < -1.0) mixed = -1.0;
        
        int16Data[i] = (mixed * 32767).toInt();
      }
      
      Uint8List byteData = int16Data.buffer.asUint8List();
      
      // Stream in async chunks to prevent ESP32 DMA buffer overflow
      () async {
        RobotService.sendAudioStart();
        
        int chunkSize = 1000;
        for (int i = 0; i < byteData.length; i += chunkSize) {
          if (!mounted || !widget.isConnected) break;
          int end = (i + chunkSize < byteData.length) ? i + chunkSize : byteData.length;
          RobotService.streamAudioChunk(byteData.sublist(i, end));
          await Future.delayed(const Duration(milliseconds: 1));
        }
        
        RobotService.sendAudioEnd();
      }();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(milliseconds: 600),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: const [
            Icon(Icons.volume_up_rounded, color: Colors.white),
            SizedBox(width: 12),
            Text(
              "🔊 ROBOT HORN CHIRP ACTIVATED!",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Pitch Black OLED
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 14),
                      SizedBox(width: 8),
                      Text("OFFLINE", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ],
                  ),
                ),

              VideoStreamMock(isConnected: widget.isConnected, isVisible: widget.isVisible, isCameraOn: _cameraActive),
              const SizedBox(height: 12),

              _buildActionModule(),
              const SizedBox(height: 12),

              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildTactileDPad(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildServoButtons(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionModule() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildOverridetoggle(
                  icon: _headlights ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
                  label: "LIGHTS",
                  value: _headlights,
                  onChanged: widget.isConnected ? (val) { HapticFeedback.selectionClick(); setState(() => _headlights = val); _sendCommand(); } : null,
                  activeColor: Colors.amber,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildOverridetoggle(
                  icon: _siren ? Icons.alarm_on_rounded : Icons.alarm_rounded,
                  label: "SIREN",
                  value: _siren,
                  onChanged: widget.isConnected ? (val) { HapticFeedback.selectionClick(); setState(() => _siren = val); _sendCommand(); } : null,
                  activeColor: Colors.redAccent,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF05070B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: widget.isConnected ? _triggerHorn : null,
                    child: Center(
                      child: Icon(Icons.volume_up_rounded, color: widget.isConnected ? const Color(0xFF10B981) : Colors.grey.withOpacity(0.3), size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildOverridetoggle(
                  icon: _cameraActive ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  label: "CAM",
                  value: _cameraActive,
                  onChanged: widget.isConnected ? (val) { HapticFeedback.selectionClick(); setState(() => _cameraActive = val); RobotService.sendRawText(val ? "camera_on" : "camera_off"); } : null,
                  activeColor: Colors.blueAccent,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => widget.isConnected ? _startListening() : null,
                  onTapUp: (_) => widget.isConnected ? _stopListening() : null,
                  onTapCancel: () => widget.isConnected ? _stopListening() : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isListening ? Colors.redAccent.withOpacity(0.2) : const Color(0xFF05070B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _isListening ? Colors.redAccent.withOpacity(0.6) : Colors.white.withOpacity(0.05)),
                      boxShadow: _isListening ? [BoxShadow(color: Colors.redAccent.withOpacity(0.6), blurRadius: 15, spreadRadius: 2)] : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic_rounded, color: _isListening ? Colors.redAccent : Colors.blueGrey, size: 16),
                        const SizedBox(width: 6),
                        Text("VOICE", style: TextStyle(color: _isListening ? Colors.white : Colors.blueGrey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildOverridetoggle(
                  icon: _screenActive ? Icons.desktop_windows_rounded : Icons.desktop_access_disabled_rounded,
                  label: "OLED",
                  value: _screenActive,
                  onChanged: widget.isConnected ? (val) { HapticFeedback.selectionClick(); setState(() => _screenActive = val); RobotService.sendRawText(val ? "screen_on" : "screen_off"); } : null,
                  activeColor: Colors.tealAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverridetoggle({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required Color activeColor,
  }) {
    final isEnabled = onChanged != null;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: value ? activeColor.withOpacity(0.15) : const Color(0xFF05070B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: value ? activeColor.withOpacity(0.7) : Colors.white.withOpacity(0.05)),
        boxShadow: value ? [BoxShadow(color: activeColor.withOpacity(0.4), blurRadius: 10, spreadRadius: 1)] : null,
      ),
      child: InkWell(
        onTap: isEnabled ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isEnabled ? (value ? activeColor : Colors.blueGrey) : Colors.grey, size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isEnabled ? (value ? Colors.white : Colors.blueGrey) : Colors.grey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }

  Timer? _servoTimer;

  void _startServoMove(double step) {
    if (!widget.isConnected) return;
    HapticFeedback.lightImpact();
    _servoTimer?.cancel();
    _servoTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      setState(() {
        _servoAngle = (_servoAngle + step).clamp(15.0, 180.0);
      });
      _sendCommand();
    });
  }

  void _stopServoMove() {
    _servoTimer?.cancel();
    _servoTimer = null;
  }

  Widget _buildServoButtons() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.25),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: widget.isConnected ? const Color(0xFF00F2FE).withOpacity(0.3) : Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: widget.isConnected ? [BoxShadow(color: const Color(0xFF00F2FE).withOpacity(0.15), blurRadius: 12, spreadRadius: 2)] : [],
      ),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTapDown: (_) => _startServoMove(2.0),
              onTapUp: (_) => _stopServoMove(),
              onTapCancel: () => _stopServoMove(),
              child: Container(
                decoration: const BoxDecoration(color: Colors.transparent),
                child: Center(
                  child: Icon(Icons.keyboard_arrow_up_rounded, color: widget.isConnected ? const Color(0xFF00F2FE) : Colors.blueGrey, size: 36),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(
              "${_servoAngle.toInt()}°",
              style: TextStyle(
                color: widget.isConnected ? const Color(0xFF00F2FE) : Colors.blueGrey,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTapDown: (_) => _startServoMove(-2.0),
              onTapUp: (_) => _stopServoMove(),
              onTapCancel: () => _stopServoMove(),
              child: Container(
                decoration: const BoxDecoration(color: Colors.transparent),
                child: Center(
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: widget.isConnected ? const Color(0xFF00F2FE) : Colors.blueGrey, size: 36),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTactileDPad() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.25),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: widget.isConnected ? const Color(0xFF00F2FE).withOpacity(0.15) : Colors.white.withOpacity(0.05), width: 1.5),
      ),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: _buildDPadButton(
              dir: 'F', icon: Icons.keyboard_arrow_up_rounded,
              onTapDown: () { setState(() { _activeDir = 'F'; _driveSpeed = 1.0; _driveTurn = 0.0; }); _startDriving(); },
              onTapUpOrCancel: () { setState(() { _activeDir = ''; _driveSpeed = 0.0; _driveTurn = 0.0; }); _stopDriving(); },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: _buildDPadButton(
                    dir: 'L', icon: Icons.keyboard_arrow_left_rounded,
                    onTapDown: () { setState(() { _activeDir = 'L'; _driveSpeed = 0.0; _driveTurn = -1.0; }); _startDriving(); },
                    onTapUpOrCancel: () { setState(() { _activeDir = ''; _driveSpeed = 0.0; _driveTurn = 0.0; }); _stopDriving(); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0F19),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Center(
                      child: Icon(Icons.circle, size: 8, color: Colors.white12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDPadButton(
                    dir: 'R', icon: Icons.keyboard_arrow_right_rounded,
                    onTapDown: () { setState(() { _activeDir = 'R'; _driveSpeed = 0.0; _driveTurn = 1.0; }); _startDriving(); },
                    onTapUpOrCancel: () { setState(() { _activeDir = ''; _driveSpeed = 0.0; _driveTurn = 0.0; }); _stopDriving(); },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 3,
            child: _buildDPadButton(
              dir: 'B', icon: Icons.keyboard_arrow_down_rounded,
              onTapDown: () { setState(() { _activeDir = 'B'; _driveSpeed = -1.0; _driveTurn = 0.0; }); _startDriving(); },
              onTapUpOrCancel: () { setState(() { _activeDir = ''; _driveSpeed = 0.0; _driveTurn = 0.0; }); _stopDriving(); },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDPadButton({
    required String dir,
    required IconData icon,
    required VoidCallback onTapDown,
    required VoidCallback onTapUpOrCancel,
  }) {
    final bool isActive = _activeDir == dir;
    final Color buttonColor = isActive ? const Color(0xFF00F2FE) : (widget.isConnected ? const Color(0xFF05070B) : const Color(0xFF05070B).withOpacity(0.5));

    return GestureDetector(
      onTapDown: widget.isConnected ? (_) { HapticFeedback.lightImpact(); onTapDown(); } : null,
      onTapUp: widget.isConnected ? (_) => onTapUpOrCancel() : null,
      onTapCancel: widget.isConnected ? () => onTapUpOrCancel() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? const Color(0xFF00F2FE) : (widget.isConnected ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.02)),
            width: 1.5,
          ),
          boxShadow: isActive ? [
            BoxShadow(color: const Color(0xFF00F2FE).withOpacity(0.8), blurRadius: 15, spreadRadius: 2),
            BoxShadow(color: const Color(0xFF00F2FE).withOpacity(0.3), blurRadius: 30, spreadRadius: 5),
          ] : null,
        ),
        child: Center(
          child: Icon(
            icon,
            color: isActive ? Colors.black : (widget.isConnected ? Colors.white : Colors.white24),
            size: 40,
          ),
        ),
      ),
    );
  }
}

