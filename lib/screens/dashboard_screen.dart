import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../services/robot_service.dart';
import '../services/local_ai_service.dart';
import '../services/cloud_ai_service.dart';
import '../services/memory_service.dart';
import '../services/sherpa_tts_service.dart';
import '../services/tts_download_service.dart';
import '../widgets/video_stream_mock.dart';
import '../services/image_enhancer_service.dart';

class DashboardScreen extends StatefulWidget {
  final Function(bool) onConnectionChanged;
  final bool isConnected;
  final bool isVisible;

  const DashboardScreen({
    super.key,
    required this.onConnectionChanged,
    required this.isConnected,
    this.isVisible = true,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  
  bool _isConnecting = false;
  bool _showGuide = false;
  bool _headlightsActive = false;
  bool _isOfflineMode = true; // Default to Offline Mode
  bool _useHindi = false;

  // Speech Recognition States
  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isOverlayVisible = false;
  String _transcribedText = "";
  final ValueNotifier<double> _soundLevel = ValueNotifier<double>(0.0);
  String _whisperStatus = ""; // "LISTENING", "PROCESSING", "DONE"
  
  Timer? _recordingTimer;
  final ValueNotifier<int> _recordingMs = ValueNotifier<int>(0);

  Timer? _logTimer;
  
  final List<String> _robotLogs = [
    "🤖 [SYS] Booting companion firmware v1.0.4...",
    "🤖 [SYS] Wi-Fi AP active: ESP32_Companion_Bot",
    "🤖 [SYS] Camera streaming interface initialized at port :81",
    "🤖 [SYS] Standing by. Please connect controller app."
  ];

  final TextEditingController _customInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    // Only start the pulse animation if currently visible
    if (widget.isVisible) {
      _pulseController.repeat(reverse: true);
    }

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _speech = stt.SpeechToText();
    _initSpeechState();
    _loadPreferences();
    SherpaTtsService.initialize();
    LocalAiService.initialize();
    CloudAiService.initialize();

    if (widget.isConnected) {
      _startLogPoller();
    }
  }

  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Pause/resume animations based on visibility
    if (widget.isVisible && !oldWidget.isVisible) {
      _pulseController.repeat(reverse: true);
      if (widget.isConnected) _startLogPoller();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _pulseController.stop();
      _logTimer?.cancel();
    }

    // Handle connection state changes
    if (widget.isConnected && !oldWidget.isConnected && widget.isVisible) {
      _startLogPoller();
    } else if (!widget.isConnected && oldWidget.isConnected) {
      _logTimer?.cancel();
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isOfflineMode = prefs.getBool('isOfflineMode') ?? true;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _logTimer?.cancel();
    _recordingTimer?.cancel();
    _customInputController.dispose();
    super.dispose();
  }

  Future<void> _initSpeechState() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          print("STT status: $status");
          if (!mounted) return;
          if (status == 'notListening' && _isListening) {
            _stopListening();
          }
        },
        onError: (error) {
          print("STT error: $error");
        },
      );
      if (mounted) {
        setState(() {
          _speechAvailable = available;
        });
      }
    } catch (e) {
      print("STT initialization failed: $e");
      if (mounted) {
        setState(() {
          _speechAvailable = false;
        });
      }
    }
  }

  void _speak(String text) async {
    await SherpaTtsService.speak(text, isHindi: _useHindi);
  }

  void _showDownloadDialog() {
    final urlController = TextEditingController(text: "https://huggingface.co/bofenghuang/gemma-2b-it-gpu-int4.bin/resolve/main/gemma-2b-it-gpu-int4.bin");
    final tokenController = TextEditingController();
    bool isDownloading = false;
    int progress = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text("Download Gemma LLM", style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isDownloading) ...[
                      const Text("Direct Model URL", style: TextStyle(color: Colors.white70)),
                      TextField(
                        controller: urlController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(hintText: "Model URL", filled: true, fillColor: Colors.black26),
                      ),
                      const SizedBox(height: 10),
                      const Text("HF Token (Optional)", style: TextStyle(color: Colors.white70)),
                      TextField(
                        controller: tokenController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(hintText: "hf_...", filled: true, fillColor: Colors.black26),
                      ),
                    ] else ...[
                      const Text("Downloading 1.5GB File. Please keep app open...", style: TextStyle(color: Colors.orangeAccent)),
                      const SizedBox(height: 20),
                      LinearProgressIndicator(value: progress / 100, backgroundColor: Colors.white24, color: Colors.blueAccent),
                      const SizedBox(height: 10),
                      Center(child: Text("$progress%", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (!isDownloading)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
                ),
              if (!isDownloading)
                ElevatedButton(
                  onPressed: () async {
                    setDialogState(() => isDownloading = true);
                    try {
                      await LocalAiService.downloadModel(
                        url: urlController.text,
                        token: tokenController.text,
                        onProgress: (p) {
                          setDialogState(() => progress = p);
                        },
                      );
                      Navigator.pop(context);
                      setState(() {}); // refresh dashboard
                      _speak("Gemma model installed successfully!");
                    } catch (e) {
                      setDialogState(() => isDownloading = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download Failed: $e")));
                    }
                  },
                  child: const Text("Start Download"),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showVoiceSelectionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Offline Voice Settings (Piper VITS)", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: TtsDownloadService.availableVoices.length,
                      itemBuilder: (context, index) {
                        final voice = TtsDownloadService.availableVoices[index];
                        final isSelected = SherpaTtsService.currentVoiceId == voice.id;

                        return FutureBuilder<bool>(
                          future: TtsDownloadService.isVoiceDownloaded(voice.id),
                          builder: (context, snapshot) {
                            final isDownloaded = snapshot.data ?? false;
                            
                            return ListTile(
                              leading: Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.record_voice_over,
                                color: isSelected ? Colors.greenAccent : Colors.white54,
                              ),
                              title: Text(voice.displayName, style: const TextStyle(color: Colors.white)),
                              subtitle: Text(voice.description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              trailing: isDownloaded
                                  ? (isSelected
                                      ? const Text("ACTIVE", style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold))
                                      : ElevatedButton(
                                          onPressed: () async {
                                            await SherpaTtsService.changeVoice(voice.id);
                                            setSheetState(() {});
                                            setState(() {});
                                            _speak("Voice changed to ${voice.displayName}");
                                          },
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                                          child: const Text("Select"),
                                        ))
                                  : ElevatedButton.icon(
                                      icon: const Icon(Icons.download, size: 16),
                                      label: const Text("Download"),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                                      onPressed: () async {
                                        setSheetState(() {
                                          voice.description; // Just forcing rebuild to show loading if we had local state
                                        });
                                        
                                        // Show progress dialog
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (context) => _DownloadProgressDialog(voice: voice),
                                        ).then((_) => setSheetState(() {}));
                                      },
                                    ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _startLogPoller() {
    _logTimer?.cancel();
    _logTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted || !widget.isVisible) return;
      
      // Poll real-time detailed logs from the physical robot over HTTP
      if (widget.isConnected) {
        RobotService.getRobotLogs().then((logs) async {
          if (!mounted || logs.isEmpty) return;
          // Only rebuild if there are actually new log lines
          bool hasNewLogs = false;
          for (var line in logs.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty) {
              _robotLogs.add(trimmed);
              hasNewLogs = true;
            }
          }
          if (hasNewLogs) {
            if (_robotLogs.length > 50) {
              _robotLogs.removeRange(0, _robotLogs.length - 50);
            }
            setState(() {});
          }
        });
      }
    });
  }

  void _toggleConnection() {
    HapticFeedback.mediumImpact();
    if (widget.isConnected) {
      _logTimer?.cancel();
      widget.onConnectionChanged(false);
      setState(() {
        _robotLogs.add("🔴 [APP] Manually disconnected from robot.");
      });
    } else {
      setState(() {
        _isConnecting = true;
      });
      _robotLogs.add("⚡ [APP] Pinging Cloud Relay on Render...");
      
      RobotService.pingRobot().then((success) {
        if (!mounted) return;
        setState(() {
          _isConnecting = false;
        });
        if (success) {
          setState(() {
            _robotLogs.add("🟢 [SYS] Gateway reached. System online!");
          });
          widget.onConnectionChanged(true);
          _startLogPoller();
          HapticFeedback.mediumImpact();
        } else {
          setState(() {
            _robotLogs.add("❌ [APP] Robot unreachable. Check Hotspot connection.");
          });
          _showManualIpDialog();
        }
      });
    }
  }

  void _showManualIpDialog() {
    final ipController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Robot Not Found", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "The automatic subnet scan failed.\nPlease check the robot's OLED screen and enter the IP address shown (e.g., 192.168.43.154).",
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: "192.168.x.x",
                filled: true,
                fillColor: Colors.black26,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (ipController.text.isNotEmpty) {
                RobotService.setManualIp(ipController.text.trim());
                Navigator.pop(context);
                _toggleConnection(); // Try connecting again!
              }
            },
            child: const Text("Connect"),
          ),
        ],
      ),
    );
  }

  String _formatUptime(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    return "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  String _formatUptimeMs(int ms) {
    final int seconds = ms ~/ 1000;
    final int hundredths = (ms % 1000) ~/ 10;
    return "${seconds.toString().padLeft(2, '0')}:${hundredths.toString().padLeft(2, '0')}";
  }

  // --- Voice Button Logic (Hold to Record, Release to Transcribe) ---
  Completer<String>? _speechCompleter;

  void _startListening() async {
    HapticFeedback.heavyImpact();
    setState(() {
      _isListening = true;
      _isOverlayVisible = true;
      _whisperStatus = "RECORDING";
      _transcribedText = "";
      _recordingMs.value = 0;
      _soundLevel.value = 0.0;
    });

    _waveController.repeat();
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) _recordingMs.value += 50;
    });

    if (_speechAvailable) {
      // Create a Completer — it resolves the moment we get any transcription result
      _speechCompleter = Completer<String>();
      try {
        await _speech.listen(
          onResult: (result) {
            // Accept the BEST result available (partial or final)
            final words = result.recognizedWords.trim();
            if (words.isNotEmpty) {
              setState(() => _transcribedText = words);
              // Complete immediately when we have text — don't wait for "final"
              if (!(_speechCompleter?.isCompleted ?? true)) {
                _speechCompleter!.complete(words);
              }
            }
          },
          onSoundLevelChange: (level) {
            _soundLevel.value = (level.clamp(-2.0, 12.0) + 2.0) / 14.0;
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 30),
          partialResults: true, // Need partials so we always get a result when stop() is called
        );
      } catch (e) {
        debugPrint("Listen failed: $e");
        _speechCompleter?.complete('');
      }
    }
  }

  void _stopListening() async {
    if (!_isListening) return;
    HapticFeedback.lightImpact();

    setState(() {
      _isListening = false;
      _whisperStatus = "PROCESSING";
    });

    _waveController.stop();
    _recordingTimer?.cancel();

    // Stop recording — triggers the STT engine to finalize
    await _speech.stop();

    // Wait up to 2 seconds for the transcription result to arrive via Completer
    // This properly resolves the race condition with the async STT callback
    String result = '';
    if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
      result = await _speechCompleter!.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => _transcribedText, // Fall back to whatever we have
      );
    } else {
      result = _transcribedText;
    }
    _speechCompleter = null;

    if (result.isNotEmpty) {
      debugPrint('✅ STT Result: "$result" → Sending to AI...');
      _processFinalTranscription(result);
    } else {
      debugPrint('⚠️ STT returned empty. Showing retry state.');
      setState(() {
        _whisperStatus = "RECORDING";
      });
    }
  }

  void _injectPresetCommand(String text) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isListening = false;
      _whisperStatus = "PROCESSING";
      _transcribedText = text;
    });

    _waveController.stop();
    _recordingTimer?.cancel();

    _processFinalTranscription(text);
  }

  void _processFinalTranscription(String text) async {
    if (!mounted) return;
    setState(() {
      _whisperStatus = "PROCESSING";
    });

    // Send to Selected AI
    AiCommandResponse? response;
    if (_isOfflineMode) {
      response = await LocalAiService.parseRobotCommand(text);
    } else {
      response = await CloudAiService.parseRobotCommand(text);
    }

    if (!mounted) return;
    setState(() {
      _whisperStatus = "DONE";
      _robotLogs.add("🎤 [USER]: \"$text\"");
    });

    if (response != null) {
      if (response!.reply.isNotEmpty) {
        setState(() {
          _robotLogs.add("🧠 [AI]: ${response!.reply}");
        });
        _speak(response!.reply);
      }

      if (response.commands.isNotEmpty) {
        String actionsList = response.commands.join(', ');
        setState(() {
          _robotLogs.add("🤖 [CMD]: $actionsList");
        });
        for (var cmd in response.commands) {
          RobotService.sendHttpCommand(cmd);
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }

      // 3. Episodic Memory Logging (Enhanced Quality)
      if (VideoStreamMock.latestFrame != null) {
        String logText = response.reply.isNotEmpty ? response.reply : response.commands.join(', ');
        
        // Enhance the snapshot with the local lightweight ML model
        final enhancedFrame = await ImageEnhancerService.enhanceImage(VideoStreamMock.latestFrame!);
        await MemoryService.addMemory(text, logText, enhancedFrame);
      }
    } else {
      // Fallback offline processing if AI fails
      _executeVoiceCommand(text);
    }

    // Fade out overlay after 2 seconds
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    setState(() {
      _isOverlayVisible = false;
      _whisperStatus = "";
    });
  }



  void _executeVoiceCommand(String rawText) {
    final text = rawText.toLowerCase().trim();
    if (text.isEmpty) return;

    setState(() {
      _robotLogs.add("🎤 [WHISPER] Transcribed offline: \"$rawText\"");
    });

    String command = "";
    String actionPayload = "";

    // Command mapping and execution
    if (text.contains("forward") || text.contains("go straight") || text.contains("move front")) {
      command = "DRIVE: FORWARD";
      actionPayload = "M:0.00,0.80;G:0,0;H:${_headlightsActive ? 1 : 0};S:0";
      RobotService.sendUdpPayload(actionPayload);
    } else if (text.contains("backward") || text.contains("reverse") || text.contains("move back")) {
      command = "DRIVE: BACKWARD";
      actionPayload = "M:0.00,-0.80;G:0,0;H:${_headlightsActive ? 1 : 0};S:0";
      RobotService.sendUdpPayload(actionPayload);
    } else if (text.contains("left") || text.contains("turn left") || text.contains("go left")) {
      command = "DRIVE: LEFT";
      actionPayload = "M:-0.80,0.00;G:0,0;H:${_headlightsActive ? 1 : 0};S:0";
      RobotService.sendUdpPayload(actionPayload);
    } else if (text.contains("right") || text.contains("turn right") || text.contains("go right")) {
      command = "DRIVE: RIGHT";
      actionPayload = "M:0.80,0.00;G:0,0;H:${_headlightsActive ? 1 : 0};S:0";
      RobotService.sendUdpPayload(actionPayload);
    } else if (text.contains("stop") || text.contains("halt") || text.contains("freeze")) {
      command = "DRIVE: STOP";
      actionPayload = "M:0.00,0.00;G:0,0;H:${_headlightsActive ? 1 : 0};S:0";
      RobotService.sendUdpPayload(actionPayload);
    } else if (text.contains("horn") || text.contains("beep") || text.contains("honk")) {
      command = "HORN CHIRP";
      actionPayload = "HTTP GET /control?cmd=horn";
      RobotService.sendHttpCommand("horn");
    } else if (text.contains("headlight") || text.contains("light")) {
      if (text.contains("off") || text.contains("deactivate") || text.contains("disable")) {
        _headlightsActive = false;
        command = "HEADLIGHTS OFF";
        actionPayload = "M:0.00,0.00;G:0,0;H:0;S:0";
        RobotService.sendUdpPayload(actionPayload);
      } else {
        _headlightsActive = true;
        command = "HEADLIGHTS ON";
        actionPayload = "M:0.00,0.00;G:0,0;H:1;S:0";
        RobotService.sendUdpPayload(actionPayload);
      }
    } else if (text.contains("happy") || text.contains("smile")) {
      command = "FACE: HAPPY";
      actionPayload = "HTTP GET /control?cmd=face_happy";
      RobotService.sendHttpCommand("face_happy");
    } else if (text.contains("excited") || text.contains("laugh")) {
      command = "FACE: EXCITED";
      actionPayload = "HTTP GET /control?cmd=face_excited";
      RobotService.sendHttpCommand("face_excited");
    } else if (text.contains("angry") || text.contains("mad") || text.contains("shock")) {
      command = "FACE: SHOCKED";
      actionPayload = "HTTP GET /control?cmd=face_shocked";
      RobotService.sendHttpCommand("face_shocked");
    } else if (text.contains("sad") || text.contains("cry")) {
      command = "FACE: SAD";
      actionPayload = "HTTP GET /control?cmd=face_sad";
      RobotService.sendHttpCommand("face_sad");
    } else {
      command = "UNRECOGNIZED SPEECH MACRO";
      actionPayload = "No triggers matched raw text.";
    }

    setState(() {
      _robotLogs.add("⚙️ [COMMAND] Executed: \"$command\"");
      _robotLogs.add("📡 [TX] Gateway sent -> $actionPayload");
      if (_robotLogs.length > 50) _robotLogs.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.isConnected ? const Color(0xFF00F2FE) : const Color(0xFFD946EF);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: Stack(
        children: [
          // Main Body Content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 100.0), // extra bottom margin for Floating Button
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // App Title & Header
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Dashboard",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: accentColor.withOpacity(0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.isConnected ? const Color(0xFF00F2FE) : Colors.red,
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.isConnected ? const Color(0xFF00F2FE).withOpacity(0.6) : Colors.red.withOpacity(0.6),
                                      blurRadius: 4,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.isConnected ? "Connected" : "Disconnected",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: widget.isConnected ? const Color(0xFF00F2FE) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Custom AI Toggle
                          GestureDetector(
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              final prefs = await SharedPreferences.getInstance();
                              setState(() {
                                _isOfflineMode = !_isOfflineMode;
                                prefs.setBool('isOfflineMode', _isOfflineMode);
                                _robotLogs.add("🤖 [SYS] Brain switched to ${_isOfflineMode ? 'LOCAL OFFLINE' : 'CLOUD AGENTIC'} mode.");
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _isOfflineMode ? const Color(0xFF10B981).withOpacity(0.15) : const Color(0xFF8B5CF6).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isOfflineMode ? const Color(0xFF10B981).withOpacity(0.4) : const Color(0xFF8B5CF6).withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isOfflineMode ? Icons.memory_rounded : Icons.cloud_sync_rounded,
                                    size: 14,
                                    color: _isOfflineMode ? const Color(0xFF10B981) : const Color(0xFF8B5CF6),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isOfflineMode ? "Local" : "Cloud",
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                      color: _isOfflineMode ? const Color(0xFF10B981) : const Color(0xFF8B5CF6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Voice Selector Button
                          if (_isOfflineMode)
                            GestureDetector(
                              onTap: () => _showVoiceSelectionSheet(),
                              child: Container(
                                margin: const EdgeInsets.only(right: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.record_voice_over_rounded, size: 14, color: Colors.amber),
                                    const SizedBox(width: 6),
                                    const Text("VOICE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber)),
                                  ],
                                ),
                              ),
                            ),
                          // Glowing Badge
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: accentColor.withOpacity(0.3), width: 1.0),
                            ),
                            child: Icon(
                              widget.isConnected ? Icons.precision_manufacturing_rounded : Icons.wifi_off_rounded,
                              color: accentColor,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Connection Panel
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isConnecting
                            ? Colors.amber.withOpacity(0.3)
                            : (widget.isConnected ? const Color(0xFF00F2FE).withOpacity(0.2) : Colors.white10),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Signal Icon
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (widget.isConnected ? const Color(0xFF00F2FE) : Colors.blueGrey).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                            color: widget.isConnected ? const Color(0xFF00F2FE) : Colors.blueGrey,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Connection Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isConnected ? "Connection Status: Online" : "Connection Status: Offline",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: widget.isConnected ? const Color(0xFF00F2FE) : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Connect Toggle Button
                        SizedBox(
                          height: 34,
                          child: ElevatedButton(
                            onPressed: _isConnecting ? null : _toggleConnection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.isConnected 
                                  ? Colors.red.withOpacity(0.15) 
                                  : const Color(0xFF8B5CF6).withOpacity(0.15),
                              foregroundColor: widget.isConnected 
                                  ? Colors.redAccent 
                                  : const Color(0xFFC084FC),
                              side: BorderSide(
                                color: widget.isConnected ? Colors.redAccent.withOpacity(0.5) : const Color(0xFFC084FC).withOpacity(0.5),
                                width: 1.0,
                              ),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: _isConnecting
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                                    ),
                                  )
                                : Text(
                                    widget.isConnected ? "OFFLINE" : "CONNECT",
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Language/TTS Toggle removed per user request
                  // AP Wifi Setup Instructions (Collapsible to keep layout extremely clean)
                  if (!widget.isConnected) ...[
                    InkWell(
                      onTap: () => setState(() => _showGuide = !_showGuide),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: Colors.blueAccent.shade100, size: 16),
                                const SizedBox(width: 8),
                                const Text(
                                  "ROBOT AP WI-FI CONFIG STEPS",
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            Icon(
                              _showGuide ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              color: Colors.blueAccent.shade200,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showGuide) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          children: [
                             _buildStepRow("1", "Open your mobile system Wi-Fi settings."),
                             _buildStepRow("2", "Connect to SSID: 'Harshita_IRA' (Password: Shivam21074)."),
                             _buildStepRow("3", "Return to this app and tap 'CONNECT' above."),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  // Telemetry removed per user request

                  // Console logs header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "System Logs",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: Colors.blueGrey.shade400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Missing Offline Model Warning
                  if (_isOfflineMode && !LocalAiService.hasRealGemma)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            "Local AI Model Not Installed",
                            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Please download the model for offline functionality.",
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.withOpacity(0.2),
                              foregroundColor: Colors.amberAccent,
                              elevation: 0,
                            ),
                            onPressed: _showDownloadDialog,
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: const Text("Download Local Model", style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),

                  // Console Log Box (Elegant glass viewport)
                  Container(
                    height: 200,
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF070A13),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: ListView.builder(
                      reverse: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _robotLogs.length,
                      itemBuilder: (context, index) {
                        final log = _robotLogs[_robotLogs.length - 1 - index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                          child: Text(
                            log,
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 10,
                              fontFamily: 'monospace',
                              height: 1.3,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // High-Tech Speech-to-Text Backdrop Overlay
          if (_isOverlayVisible) _buildSpeechOverlay(),
        ],
      ),
      floatingActionButton: _buildVoiceFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildVoiceFAB() {
    return GestureDetector(
      onLongPressStart: (_) => _startListening(),
      onLongPressEnd: (_) => _stopListening(),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final double scale = 1.0 + (_pulseController.value * 0.05);
          return Transform.scale(
            scale: _isListening ? 1.15 : scale,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _isListening
                      ? [const Color(0xFF00F2FE), const Color(0xFFEC4899)]
                      : [const Color(0xFF8B5CF6), const Color(0xFF00F2FE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isListening ? const Color(0xFFEC4899) : const Color(0xFF8B5CF6)).withOpacity(0.4),
                    blurRadius: _isListening ? 20 : 10,
                    spreadRadius: _isListening ? 3 : 1,
                  ),
                ],
                border: Border.all(
                  color: Colors.white30,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpeechOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  // Header
                  Text(
                    "Voice Command",
                    style: TextStyle(
                      color: const Color(0xFF00F2FE),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      shadows: [
                        Shadow(color: const Color(0xFF00F2FE).withOpacity(0.5), blurRadius: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Speech Recognition",
                    style: TextStyle(color: Colors.blueGrey, fontSize: 8, letterSpacing: 0.8),
                  ),
                  const Spacer(),

                  // Dynamic Central Visualization Frame
                  SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_whisperStatus == "RECORDING") ...[
                          // Wave visualizer
                          AnimatedBuilder(
                            animation: _waveController,
                            builder: (context, child) {
                              return ValueListenableBuilder<double>(
                                valueListenable: _soundLevel,
                                builder: (context, level, child) {
                                  return CustomPaint(
                                    size: const Size(double.infinity, 120),
                                    painter: _VoiceWavePainter(
                                      animValue: _waveController.value,
                                      soundLevel: level,
                                    ),
                                  );
                                }
                              );
                            },
                          ),
                          // Status Text
                          Positioned(
                            bottom: 0,
                            child: ValueListenableBuilder<int>(
                              valueListenable: _recordingMs,
                              builder: (context, ms, child) {
                                return Text(
                                  _speechAvailable
                                      ? "Hold to record... [ ${_formatUptimeMs(ms)} ]"
                                      : "Recording (Offline)... [ ${_formatUptimeMs(ms)} ]",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1.5,
                                  ),
                                );
                              }
                            ),
                          ),
                        ] else if (_whisperStatus == "PROCESSING") ...[
                          // High-tech scanner laser spinner
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 44,
                                height: 44,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                                ),
                              ),
                              const SizedBox(height: 20),
                                Text(
                                  "Processing...",
                                  style: TextStyle(
                                  color: Colors.amber.shade200,
                                  fontFamily: 'monospace',
                                  fontSize: 9,
                                  letterSpacing: 1.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ] else if (_whisperStatus == "DONE") ...[
                          // Success state
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF10B981).withOpacity(0.1),
                                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4), width: 1.5),
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Color(0xFF10B981),
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "SPEECH TRANSCRIBED SUCCESSFULLY",
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Real-time voice Transcription display
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.04)),
                    ),
                    child: Text(
                      _transcribedText.isEmpty
                          ? (_isListening ? "( listening for speech... )" : "( speak, type custom input, or tap preset )")
                          : "\"$_transcribedText\"",
                      style: TextStyle(
                        color: _transcribedText.isEmpty ? Colors.blueGrey : Colors.white,
                        fontSize: 13,
                        fontStyle: _transcribedText.isEmpty ? FontStyle.italic : FontStyle.normal,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Spacer(),

                  // Holographic Command Suggestion Chips
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Presets",
                        style: TextStyle(color: Colors.blueGrey, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _buildPresetChip("go forward", Colors.green),
                            _buildPresetChip("stop robot", Colors.red),
                            _buildPresetChip("turn left", Colors.cyan),
                            _buildPresetChip("turn right", Colors.cyan),
                            _buildPresetChip("honk horn", Colors.teal),
                            _buildPresetChip("headlights on", Colors.amber),
                            _buildPresetChip("headlights off", Colors.orange),
                            _buildPresetChip("show happy face", Colors.purple),
                            _buildPresetChip("show sad face", Colors.deepPurple),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Custom Text Speech Injector (For robust testing anywhere!)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Text Input",
                        style: TextStyle(color: Colors.blueGrey, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 42,
                              child: TextField(
                                controller: _customInputController,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B).withOpacity(0.3),
                                  hintText: "Type voice command text here...",
                                  hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 11),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFF00F2FE), width: 1.0),
                                  ),
                                ),
                                onSubmitted: (val) {
                                  if (val.trim().isNotEmpty) {
                                    _customInputController.clear();
                                    FocusScope.of(context).unfocus();
                                    _injectPresetCommand(val);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: () {
                                final text = _customInputController.text.trim();
                                if (text.isNotEmpty) {
                                  _customInputController.clear();
                                  FocusScope.of(context).unfocus();
                                  _injectPresetCommand(text);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00F2FE).withOpacity(0.15),
                                foregroundColor: const Color(0xFF00F2FE),
                                side: const BorderSide(color: Color(0xFF00F2FE), width: 1.0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: const Icon(Icons.send_rounded, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Dismiss overlay helper
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isOverlayVisible = false;
                        _isListening = false;
                        _whisperStatus = "";
                      });
                      _recordingTimer?.cancel();
                      _waveController.stop();
                      if (_speechAvailable) {
                        _speech.stop();
                      }
                    },
                    child: const Text(
                      "DISMISS DIALOG",
                      style: TextStyle(color: Colors.grey, fontSize: 9, letterSpacing: 1.0, decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String text, Color highlightColor) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        backgroundColor: const Color(0xFF1E293B).withOpacity(0.4),
        side: BorderSide(color: highlightColor.withOpacity(0.4), width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        label: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            shadows: [
              Shadow(color: highlightColor.withOpacity(0.4), blurRadius: 4),
            ],
          ),
        ),
        onPressed: () => _injectPresetCommand(text),
      ),
    );
  }

  Widget _buildStepRow(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            alignment: Alignment.center,
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blueAccent.withOpacity(0.2),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
            ),
            child: Text(
              number,
              style: const TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'monospace',
                    shadows: [
                      Shadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Fluid, Multi-layered Siri-style Sine Wave Painter
class _VoiceWavePainter extends CustomPainter {
  final double animValue;
  final double soundLevel;

  _VoiceWavePainter({required this.animValue, required this.soundLevel});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final centerY = size.height / 2;
    final width = size.width;

    // Draw 3 overlapping transparent waves with varying frequency and phases
    _drawSingleWave(
      canvas, 
      paint, 
      width, 
      centerY, 
      color: const Color(0xFF00F2FE).withOpacity(0.85), // Cyan
      frequency: 1.4,
      amplitude: 12.0 + (soundLevel * 35.0),
      phaseShift: animValue * 2 * math.pi,
    );

    _drawSingleWave(
      canvas, 
      paint, 
      width, 
      centerY, 
      color: const Color(0xFFEC4899).withOpacity(0.65), // Laser Pink
      frequency: 0.95,
      amplitude: 20.0 + (soundLevel * 45.0),
      phaseShift: -animValue * 2 * math.pi + 1.2,
    );

    _drawSingleWave(
      canvas, 
      paint, 
      width, 
      centerY, 
      color: const Color(0xFF8B5CF6).withOpacity(0.45), // Royal Purple
      frequency: 2.1,
      amplitude: 8.0 + (soundLevel * 20.0),
      phaseShift: animValue * math.pi + 2.5,
    );
  }

  void _drawSingleWave(
    Canvas canvas, 
    Paint paint, 
    double width, 
    double centerY, {
    required Color color,
    required double frequency,
    required double amplitude,
    required double phaseShift,
  }) {
    paint.color = color;
    final path = Path();
    
    for (double x = 0; x <= width; x++) {
      final relativeX = x / width;
      final edgeFade = math.sin(relativeX * math.pi); // Fade amplitude near boundaries
      
      final y = centerY + amplitude * edgeFade * math.sin(frequency * 2 * math.pi * relativeX + phaseShift);
      
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) {
    return oldDelegate.animValue != animValue || oldDelegate.soundLevel != soundLevel;
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final TtsVoice voice;
  const _DownloadProgressDialog({required this.voice});

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      await TtsDownloadService.downloadAndExtractVoice(widget.voice, (progress) {
        if (mounted) {
          setState(() {
            _progress = progress;
          });
        }
      });
      if (mounted) {
        Navigator.pop(context); // Close on success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text("Downloading ${widget.voice.displayName}", style: const TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isError)
            const Text("Download failed. Please try again.", style: TextStyle(color: Colors.redAccent))
          else ...[
            const Text("This voice is ~25MB. Please do not close the app.", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _progress, backgroundColor: Colors.white24, color: Colors.blueAccent),
            const SizedBox(height: 10),
            Text("${(_progress * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
      actions: [
        if (_isError)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: Colors.white54)),
          ),
      ],
    );
  }
}
