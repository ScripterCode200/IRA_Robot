import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
import '../services/rag_cache_service.dart';
import 'personality_editor_screen.dart';
import 'rag_editor_screen.dart';

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
  int _aiDriveForwardMs = 1500;
  int _aiDriveTurnMs = 1000;

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
    RagCacheService.initialize();

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
        _aiDriveForwardMs = prefs.getInt('aiDriveForwardMs') ?? 1500;
        _aiDriveTurnMs = prefs.getInt('aiDriveTurnMs') ?? 1000;
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
      backgroundColor: Colors.transparent, // Transparent to allow glassy blur effect
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.6, // 60% of screen
                  padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.85),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.15), width: 1.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag Pill
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F2FE).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.record_voice_over_rounded, color: Color(0xFF00F2FE), size: 24),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Offline Voice Engines", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                SizedBox(height: 2),
                                Text("Powered by Piper VITS", style: TextStyle(color: Colors.blueGrey, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // List
                      Expanded(
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: TtsDownloadService.availableVoices.length,
                          itemBuilder: (context, index) {
                            final voice = TtsDownloadService.availableVoices[index];
                            final isSelected = SherpaTtsService.currentVoiceId == voice.id;

                            return FutureBuilder<bool>(
                              future: TtsDownloadService.isVoiceDownloaded(voice.id),
                              builder: (context, snapshot) {
                                final isDownloaded = snapshot.data ?? false;
                                
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF00F2FE).withOpacity(0.1) : const Color(0xFF1E293B).withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF00F2FE).withOpacity(0.5) : Colors.white.withOpacity(0.05),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                    boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF00F2FE).withOpacity(0.1), blurRadius: 10)] : [],
                                  ),
                                  child: Row(
                                    children: [
                                      // Avatar / Icon
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: isSelected 
                                            ? const LinearGradient(colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)]) 
                                            : LinearGradient(colors: [Colors.blueGrey.shade800, Colors.blueGrey.shade900]),
                                        ),
                                        child: Icon(
                                          isSelected ? Icons.check_rounded : Icons.person_rounded,
                                          color: isSelected ? Colors.black87 : Colors.white54,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      
                                      // Text Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(voice.displayName, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 4),
                                            Text(voice.description, style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      
                                      // Actions
                                      if (isDownloaded)
                                        if (isSelected)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(color: const Color(0xFF00F2FE).withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                                            child: const Text("ACTIVE", style: TextStyle(color: Color(0xFF00F2FE), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                                          )
                                        else
                                          ElevatedButton(
                                            onPressed: () async {
                                              await SherpaTtsService.changeVoice(voice.id);
                                              setSheetState(() {});
                                              setState(() {});
                                              _speak("Voice changed to ${voice.displayName}");
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white.withOpacity(0.1),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            child: const Text("Select"),
                                          )
                                      else
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.download_rounded, size: 16),
                                          label: const Text("Get"),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orangeAccent.withOpacity(0.2),
                                            foregroundColor: Colors.orangeAccent,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            side: const BorderSide(color: Colors.orangeAccent, width: 1),
                                          ),
                                          onPressed: () async {
                                            // Show progress dialog
                                            showDialog(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (context) => _DownloadProgressDialog(voice: voice),
                                            ).then((_) => setSheetState(() {}));
                                          },
                                        ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDriveSettingsSheet() {
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
                  const Text("AI Movement Duration", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text("Configure how long the robot moves when given a voice command.", style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 20),
                  const Text("Forward & Backward", style: TextStyle(color: Colors.white70)),
                  Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text("${_aiDriveForwardMs}ms", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Expanded(
                        child: Slider(
                          value: _aiDriveForwardMs.toDouble(),
                          min: 1,
                          max: 5000,
                          divisions: 4999,
                          activeColor: Colors.greenAccent,
                          onChanged: (val) {
                            setSheetState(() => _aiDriveForwardMs = val.toInt());
                            setState(() => _aiDriveForwardMs = val.toInt());
                          },
                          onChangeEnd: (val) async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setInt('aiDriveForwardMs', val.toInt());
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text("Left & Right Turns", style: TextStyle(color: Colors.white70)),
                  Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text("${_aiDriveTurnMs}ms", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Expanded(
                        child: Slider(
                          value: _aiDriveTurnMs.toDouble(),
                          min: 1,
                          max: 5000,
                          divisions: 4999,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) {
                            setSheetState(() => _aiDriveTurnMs = val.toInt());
                            setState(() => _aiDriveTurnMs = val.toInt());
                          },
                          onChangeEnd: (val) async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setInt('aiDriveTurnMs', val.toInt());
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
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

    // 1. Check RAG Cache First
    AiCommandResponse? response = RagCacheService.findMatch(text);
    bool isCacheHit = response != null;

    if (isCacheHit) {
      setState(() {
        _robotLogs.add("⚡ [CACHE HIT] Direct match found. Bypassing AI processing.");
      });
    } else {
      // 2. Send to Selected AI if not cached
      if (_isOfflineMode) {
        response = await LocalAiService.parseRobotCommand(text);
      } else {
        response = await CloudAiService.parseRobotCommand(text);
      }
      
      // 3. Save successful new response to Cache
      if (response != null) {
        await RagCacheService.cacheResponse(text, response);
      }
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
          if (cmd == "drive_forward" || cmd == "drive_backward") {
            cmd = "$cmd:$_aiDriveForwardMs";
          } else if (cmd == "drive_left" || cmd == "drive_right") {
            cmd = "$cmd:$_aiDriveTurnMs";
          }
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
      backgroundColor: const Color(0xFF000000), // Pitch Black AMOLED Background
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 80.0), // Padding for FAB
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  // App Title & Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Dashboard",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Colors.white,
                              shadows: [Shadow(color: accentColor.withOpacity(0.5), blurRadius: 10)],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.isConnected ? const Color(0xFF00F2FE) : const Color(0xFFD946EF),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (widget.isConnected ? const Color(0xFF00F2FE) : const Color(0xFFD946EF)).withOpacity(0.6),
                                      blurRadius: 6, spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.isConnected ? "SYSTEM ONLINE" : "SYSTEM OFFLINE",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: widget.isConnected ? const Color(0xFF00F2FE) : const Color(0xFFD946EF),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Action Buttons Panel
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Voice Selection Button
                        IconButton(
                          icon: const Icon(Icons.record_voice_over_rounded, color: Colors.amberAccent, size: 24),
                          tooltip: "Voice Settings",
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _showVoiceSelectionSheet();
                          },
                        ),
                        // RAG Cache Button
                        IconButton(
                          icon: const Icon(Icons.memory_rounded, color: Colors.blueAccent, size: 24),
                          tooltip: "RAG Cache",
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const RagEditorScreen()));
                          },
                        ),
                        // Personality Editor Button
                        IconButton(
                          icon: const Icon(Icons.psychology_alt_rounded, color: Colors.white70, size: 24),
                          tooltip: "Personality",
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const PersonalityEditorScreen()));
                          },
                        ),
                        Container(
                          width: 1.5,
                          height: 30,
                          color: Colors.white.withOpacity(0.1),
                        ),
                        // Custom Offline / Cloud Toggle
                        GestureDetector(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            final val = !_isOfflineMode;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('isOfflineMode', val);
                            setState(() => _isOfflineMode = val);
                          },
                          child: Container(
                            width: 72,
                            height: 36,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                              boxShadow: [
                                BoxShadow(
                                  color: _isOfflineMode ? Colors.amber.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                AnimatedAlign(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutBack,
                                  alignment: _isOfflineMode ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isOfflineMode ? Colors.amber : Colors.blue,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_isOfflineMode ? Colors.amber : Colors.blue).withOpacity(0.6),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _isOfflineMode ? Icons.memory_rounded : Icons.cloud_rounded,
                                      color: Colors.black,
                                      size: 16,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: _isOfflineMode ? Alignment.centerLeft : Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    child: Text(
                                      _isOfflineMode ? "LCL" : "CLD",
                                      style: TextStyle(
                                        color: _isOfflineMode ? Colors.amber.withOpacity(0.8) : Colors.blue.withOpacity(0.8),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),

                  // Connection Control Panel (Glassmorphism)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isConnecting
                            ? Colors.amber.withOpacity(0.4)
                            : (widget.isConnected ? const Color(0xFF00F2FE).withOpacity(0.3) : const Color(0xFFD946EF).withOpacity(0.3)),
                        width: 1.5,
                      ),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (widget.isConnected ? const Color(0xFF00F2FE) : const Color(0xFFD946EF)).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            widget.isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                            color: widget.isConnected ? const Color(0xFF00F2FE) : const Color(0xFFD946EF),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "ROBOT UPLINK",
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.blueGrey.shade300),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.isConnected ? "Connected to ESP32" : "Awaiting Connection...",
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _isConnecting ? null : _toggleConnection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.isConnected ? Colors.red.withOpacity(0.15) : const Color(0xFF00F2FE).withOpacity(0.15),
                            foregroundColor: widget.isConnected ? Colors.redAccent : const Color(0xFF00F2FE),
                            side: BorderSide(
                              color: widget.isConnected ? Colors.redAccent.withOpacity(0.5) : const Color(0xFF00F2FE).withOpacity(0.5),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            elevation: 0,
                          ),
                          child: _isConnecting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.amber)))
                              : Text(
                                  widget.isConnected ? "DISCONNECT" : "CONNECT",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Missing Offline Model Warning (only shows if missing and offline mode selected)
                  if (_isOfflineMode && !LocalAiService.hasRealGemma)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text("Offline AI Model Missing", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                                Text("Required for voice commands without internet.", style: TextStyle(color: Colors.white70, fontSize: 10)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.withOpacity(0.2), foregroundColor: Colors.amberAccent, elevation: 0),
                            onPressed: _showDownloadDialog,
                            child: const Text("DOWNLOAD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Flexible Space for either Wi-Fi Guide or Logs
                  Expanded(
                    child: widget.isConnected 
                      ? _buildLogViewer() 
                      : _buildWifiGuide(),
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

  Widget _buildWifiGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              "ROBOT CONNECTION STEPS",
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.blueAccent.shade100),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStepRow("1", "Turn ON your Mobile Hotspot", Icons.cell_wifi_rounded),
                _buildStepRow("2", "Set Hotspot Name to:\n'Shivam'\n(Password: 1234567891)", Icons.settings_rounded),
                _buildStepRow("3", "Turn ON the robot and tap 'CONNECT'", Icons.power_settings_new_rounded),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepRow(String number, String text, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF00F2FE).withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF00F2FE).withOpacity(0.5)),
          ),
          alignment: Alignment.center,
          child: Text(number, style: const TextStyle(color: Color(0xFF00F2FE), fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        const SizedBox(width: 16),
        Icon(icon, color: Colors.white54, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
        ),
      ],
    );
  }

  Widget _buildLogViewer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "SYSTEM LOGS",
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.blueGrey.shade400),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF070A13),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
            ),
            child: ListView.builder(
              reverse: true,
              physics: const BouncingScrollPhysics(),
              itemCount: _robotLogs.length,
              itemBuilder: (context, index) {
                final log = _robotLogs[_robotLogs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    log,
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontFamily: 'monospace', height: 1.4),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceFAB() {
    return GestureDetector(
      onLongPressStart: (_) => _startListening(),
      onLongPressEnd: (_) => _stopListening(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _waveController]),
        builder: (context, child) {
          // Normal idle breathing scale
          final double idleScale = 1.0 + (math.sin(_pulseController.value * math.pi * 2) * 0.05);
          // Active listening bouncy scale
          final double activeScale = 1.1 + (math.sin(_waveController.value * math.pi * 8) * 0.1);
          final double scale = _isListening ? activeScale : idleScale;

          return SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glowing Ripples when listening
                if (_isListening) ...[
                  for (int i = 0; i < 3; i++)
                    _buildRipple(i, _waveController.value),
                ],
                
                // Main Button
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isListening
                            ? [const Color(0xFF00F2FE), const Color(0xFFEC4899), const Color(0xFF8B5CF6)]
                            : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        if (_isListening)
                          BoxShadow(
                            color: const Color(0xFF00F2FE).withOpacity(0.6),
                            blurRadius: 25,
                            spreadRadius: 8,
                          ),
                        if (_isListening)
                          BoxShadow(
                            color: const Color(0xFFEC4899).withOpacity(0.4),
                            blurRadius: 40,
                            spreadRadius: 12,
                          ),
                        if (!_isListening)
                          BoxShadow(
                            color: const Color(0xFF00F2FE).withOpacity(0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                      ],
                      border: Border.all(
                        color: _isListening ? Colors.white : const Color(0xFF00F2FE).withOpacity(0.5),
                        width: _isListening ? 2.0 : 1.0,
                      ),
                    ),
                    child: Icon(
                      _isListening ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                      color: _isListening ? Colors.white : const Color(0xFF00F2FE),
                      size: _isListening ? 32 : 28,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRipple(int index, double animationValue) {
    // Offset the animation for each ripple so they expand one after another
    final double phase = (animationValue + (index * 0.33)) % 1.0;
    // Scale goes from 0.5 to 2.0
    final double scale = 0.5 + (phase * 1.5);
    // Opacity fades out as it expands
    final double opacity = 1.0 - phase;

    return Transform.scale(
      scale: scale,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF00F2FE).withOpacity(opacity * 0.8),
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEC4899).withOpacity(opacity * 0.3),
              blurRadius: 15,
              spreadRadius: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeechOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.65), // Slightly lighter background
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), // Much stronger blur
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: 20.0, 
                    right: 20.0, 
                    top: 40.0, // Push down slightly
                    bottom: MediaQuery.of(context).viewInsets.bottom + 100.0, // Room for FAB
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.75),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF00F2FE).withOpacity(0.15), blurRadius: 50, spreadRadius: -10),
                        BoxShadow(color: const Color(0xFFEC4899).withOpacity(0.1), blurRadius: 40, offset: const Offset(0, 20)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // Wrap content tightly!
                      children: [
                        // Header and Dismiss Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(width: 48), // Balance for centering
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    "Voice Command",
                                    style: TextStyle(
                                      color: const Color(0xFF00F2FE),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2.5,
                                      shadows: [
                                        Shadow(color: const Color(0xFF00F2FE).withOpacity(0.5), blurRadius: 8),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    "Speech Recognition",
                                    style: TextStyle(color: Colors.blueGrey, fontSize: 8, letterSpacing: 1.0),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.only(left: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
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
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),

                        // Dynamic Central Visualization Frame with CLIP RECT to prevent overflow!
                        ClipRect(
                          child: SizedBox(
                            height: 180, // Taller bounds for bigger waves
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
                                            size: const Size(double.infinity, 180),
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
                                        width: 50,
                                        height: 50,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3.0,
                                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                        Text(
                                          "Processing...",
                                          style: TextStyle(
                                          color: Colors.amber.shade200,
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          letterSpacing: 1.5,
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
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF10B981).withOpacity(0.15),
                                          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5), width: 2.0),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Color(0xFF10B981),
                                          size: 36,
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
                        ),

                        const SizedBox(height: 24),

                        // Real-time voice Transcription display
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withOpacity(0.4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Text(
                            _transcribedText.isEmpty
                                ? (_isListening ? "( listening for speech... )" : "( speak, type custom input, or tap preset )")
                                : "\"$_transcribedText\"",
                            style: TextStyle(
                              color: _transcribedText.isEmpty ? Colors.blueGrey : Colors.white,
                              fontSize: 14,
                              fontStyle: _transcribedText.isEmpty ? FontStyle.italic : FontStyle.normal,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        const SizedBox(height: 32),

                        // Holographic Command Suggestion Chips
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Presets",
                              style: TextStyle(color: Colors.blueGrey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 8),
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
                        
                        const SizedBox(height: 24),

                        // Custom Text Speech Injector
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Text Input",
                              style: TextStyle(color: Colors.blueGrey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 44,
                                    child: TextField(
                                      controller: _customInputController,
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color(0xFF1E293B).withOpacity(0.5),
                                        hintText: "Type voice command text here...",
                                        hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 11),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
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
                                  height: 44,
                                  width: 44,
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
                                      side: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                    child: const Icon(Icons.send_rounded, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // (Dismiss button moved to top right)
                      ],
                    ),
                  ),
                );
              }
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
    // Use BlendMode.screen to make overlapping colors intensely bright like plasma
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen;

    final centerY = size.height / 2;
    final width = size.width;

    // Amplified dynamic sound level (minimum 0.05 so it's never completely dead)
    final dynamicLevel = math.max(0.05, soundLevel);
    final maxAmplitude = 30.0 + (dynamicLevel * 140.0); // Massive bounce on speech

    // We draw 6 overlapping glowing waves to create a dense energy core
    _drawGlowingWave(
      canvas, paint, width, centerY, 
      color: const Color(0xFF00F2FE), // Bright Cyan
      frequency: 1.2,
      amplitude: maxAmplitude * 0.8,
      phaseShift: animValue * 2 * math.pi,
      thickness: 4.0,
      glowBlur: 15.0,
    );

    _drawGlowingWave(
      canvas, paint, width, centerY, 
      color: const Color(0xFFEC4899), // Neon Pink
      frequency: 1.8,
      amplitude: maxAmplitude * 0.6,
      phaseShift: -animValue * 3 * math.pi + 1.2,
      thickness: 3.5,
      glowBlur: 12.0,
    );

    _drawGlowingWave(
      canvas, paint, width, centerY, 
      color: const Color(0xFF8B5CF6), // Laser Purple
      frequency: 0.9,
      amplitude: maxAmplitude * 1.0,
      phaseShift: animValue * 1.5 * math.pi + 2.5,
      thickness: 5.0,
      glowBlur: 20.0,
    );

    // Inner Core Plasma lines (thinner, brighter, faster)
    _drawGlowingWave(
      canvas, paint, width, centerY, 
      color: Colors.white,
      frequency: 2.2,
      amplitude: maxAmplitude * 0.3,
      phaseShift: -animValue * 4 * math.pi,
      thickness: 2.0,
      glowBlur: 5.0,
    );
    
    _drawGlowingWave(
      canvas, paint, width, centerY, 
      color: const Color(0xFF00F2FE),
      frequency: 1.5,
      amplitude: maxAmplitude * 0.4,
      phaseShift: animValue * 2.5 * math.pi + 0.8,
      thickness: 2.5,
      glowBlur: 8.0,
    );
    
    _drawGlowingWave(
      canvas, paint, width, centerY, 
      color: const Color(0xFFEC4899),
      frequency: 2.8,
      amplitude: maxAmplitude * 0.2,
      phaseShift: -animValue * 5 * math.pi + 3.1,
      thickness: 1.5,
      glowBlur: 4.0,
    );
  }

  void _drawGlowingWave(
    Canvas canvas, 
    Paint paint, 
    double width, 
    double centerY, {
    required Color color,
    required double frequency,
    required double amplitude,
    required double phaseShift,
    required double thickness,
    required double glowBlur,
  }) {
    // Draw the glow layer first
    paint.strokeWidth = thickness * 2.5;
    paint.color = color.withOpacity(0.4);
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur);
    _drawPath(canvas, paint, width, centerY, frequency, amplitude, phaseShift);

    // Draw the solid core layer on top
    paint.strokeWidth = thickness;
    paint.color = color;
    paint.maskFilter = null; // No blur for the sharp core
    _drawPath(canvas, paint, width, centerY, frequency, amplitude, phaseShift);
  }

  void _drawPath(Canvas canvas, Paint paint, double width, double centerY, double frequency, double amplitude, double phaseShift) {
    final path = Path();
    for (double x = 0; x <= width; x += 2) { // Step by 2 for performance
      final relativeX = x / width;
      // Use a bell curve (sine) to pinch the edges so the wave only expands in the middle
      final edgeFade = math.pow(math.sin(relativeX * math.pi), 1.5).toDouble(); 
      
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
