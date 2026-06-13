import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/robot_service.dart';
import '../models/custom_face_model.dart';
import '../services/face_storage_service.dart';
import 'pixel_face_editor.dart';
import 'ai_face_preview_screen.dart';
enum FaceExpression { neutral, happy, excited, shocked, sad }

class FaceScreen extends StatefulWidget {
  final bool isConnected;
  final bool isVisible;

  const FaceScreen({
    super.key,
    required this.isConnected,
    this.isVisible = true,
  });

  @override
  State<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends State<FaceScreen> with TickerProviderStateMixin {
  FaceExpression _currentExpression = FaceExpression.neutral;
  
  // Animation controllers for eyelids & micro-movement loops
  late AnimationController _eyeMovementController;
  late AnimationController _blinkController;
  late AnimationController _mouthWaveController;
  
  Timer? _blinkTimer;
  bool _isBlinking = false;

  List<CustomFace> _customFaces = [];
  CustomFace? _activeCustomFace;
  WebViewController? _webViewController;
  List<Uint8List> _recordedFrames = [];
  bool _isInitializingFace = false;
  Timer? _faceInitTimer;

  @override
  void initState() {
    super.initState();

    // Subtle drift movement
    _eyeMovementController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    // Blinking eyelid controller
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    // Mouth animation controller
    _mouthWaveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    // Only start animations if currently visible
    if (widget.isVisible) {
      _eyeMovementController.repeat(reverse: true);
      _mouthWaveController.repeat();
      _startRandomBlinking();
    }
    
    _loadFaces();
  }

  @override
  void didUpdateWidget(FaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Pause/resume animations based on visibility
    if (widget.isVisible && !oldWidget.isVisible) {
      _eyeMovementController.repeat(reverse: true);
      _mouthWaveController.repeat();
      _startRandomBlinking();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _eyeMovementController.stop();
      _mouthWaveController.stop();
      _blinkTimer?.cancel();
    }
  }

  Future<void> _loadFaces() async {
    final faces = await FaceStorageService.loadSavedFaces();
    if (mounted) {
      setState(() {
        _customFaces = faces;
      });
    }
  }

  void _openEditor([CustomFace? face]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PixelFaceEditor(initialFace: face)),
    );
    if (result != null && result is CustomFace) {
      await _loadFaces();
      setState(() {
        _activeCustomFace = result;
        if (result.htmlCode != null) {
          _loadWebView(result.htmlCode!);
        } else {
          _webViewController?.loadHtmlString('');
        }
      });
    }
  }

  void _openAiGenerator() async {
    final resultHtml = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AIFacePreviewScreen(isConnected: widget.isConnected)),
    );
    if (resultHtml != null && resultHtml is String) {
      // Save it as a CustomFace
      final nameController = TextEditingController();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Save AI Face', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Enter a name...', hintStyle: TextStyle(color: Colors.white54)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        )
      );

      if (confirm == true && nameController.text.trim().isNotEmpty) {
        final newFace = CustomFace(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: nameController.text.trim(),
          grid: List.generate(64, (_) => List.generate(128, (_) => false)), // blank fallback
          htmlCode: resultHtml,
        );
        await FaceStorageService.saveFace(newFace);
        await _loadFaces();
        setState(() {
          _activeCustomFace = newFace;
          _loadWebView(resultHtml);
        });
      }
    }
  }

  void _loadWebView(String htmlCode) {
    _recordedFrames.clear();
    
    if (_webViewController == null) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel(
          'RobotChannel',
          onMessageReceived: (JavaScriptMessage message) async {
            if (widget.isConnected) {
              try {
                if (_isInitializingFace && _recordedFrames.length < 30) {
                  _recordedFrames.add(base64Decode(message.message));
                  if (_recordedFrames.length == 30) {
                     _faceInitTimer?.cancel();
                     setState(() { _isInitializingFace = false; });
                     await RobotService.sendAnimationSequence(_recordedFrames);
                  }
                }
              } catch (e) {}
            }
          },
        );
    }
    
    if (widget.isConnected) {
      setState(() { _isInitializingFace = true; });
      _faceInitTimer?.cancel();
      _faceInitTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isInitializingFace) {
          setState(() { _isInitializingFace = false; });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Warning: Face animation code might be faulty or took too long! Please generate a new one."),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });
    }
    
    _webViewController!.loadHtmlString(htmlCode);
  }

  @override
  void dispose() {
    _webViewController?.loadHtmlString('');
    _eyeMovementController.dispose();
    _blinkController.dispose();
    _mouthWaveController.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  void _startRandomBlinking() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;
      if (_currentExpression != FaceExpression.shocked) {
        _triggerBlink();
      }
    });
  }

  void _triggerBlink() async {
    if (!mounted) return;
    try {
      setState(() {
        _isBlinking = true;
      });
      await _blinkController.forward();
      await _blinkController.reverse();
      if (!mounted) return;
      setState(() {
        _isBlinking = false;
      });
    } catch (_) {}
  }

  void _setExpression(FaceExpression expression) {
    HapticFeedback.mediumImpact();
    setState(() {
      _currentExpression = expression;
    });

    String cmd = "";
    switch (expression) {
      case FaceExpression.neutral:
        cmd = "face_happy";
        break;
      case FaceExpression.happy:
        cmd = "face_happy";
        break;
      case FaceExpression.excited:
        cmd = "face_excited";
        break;
      case FaceExpression.shocked:
        cmd = "face_shocked";
        break;
      case FaceExpression.sad:
        cmd = "face_sad";
        break;
    }

    if (widget.isConnected && cmd.isNotEmpty) {
      RobotService.sendHttpCommand(cmd);
    }

    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(Icons.send_rounded, color: widget.isConnected ? const Color(0xFF00F2FE) : const Color(0xFFD946EF), size: 16),
            const SizedBox(width: 12),
            Text(
              widget.isConnected ? "HTTP COMMAND SENT -> $cmd" : "OFFLINE OVERRIDE -> ${expression.name.toUpperCase()}",
              style: const TextStyle(color: Color(0xFFE2E8F0), fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color faceColor = const Color(0xFF00F2FE);
    String titleText = "COMPANION EMOTIVE MATRIX";
    
    switch (_currentExpression) {
      case FaceExpression.neutral:
        faceColor = const Color(0xFF00F2FE); // Cyan
        break;
      case FaceExpression.happy:
        faceColor = const Color(0xFF10B981); // Emerald
        break;
      case FaceExpression.excited:
        faceColor = const Color(0xFFD946EF); // Magenta
        break;
      case FaceExpression.shocked:
        faceColor = const Color(0xFFF59E0B); // Amber
        break;
      case FaceExpression.sad:
        faceColor = const Color(0xFF3B82F6); // Blue
        break;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF05070B),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Header title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleText,
                        style: TextStyle(
                          color: faceColor.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "LED PANEL SCREEN MIRROR",
                        style: TextStyle(color: Colors.blueGrey, fontSize: 8, letterSpacing: 1),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.isConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: widget.isConnected ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      widget.isConnected ? "CONNECTED" : "OFFLINE",
                      style: TextStyle(
                        color: widget.isConnected ? Colors.green : Colors.red,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Custom Faces Gallery & Editor Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _customFaces.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildFaceBtn("DEFAULT", null);
                          }
                          final face = _customFaces[index - 1];
                          return _buildFaceBtn(face.name, face);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: const Color(0xFF00F2FE),
                          side: const BorderSide(color: Color(0xFF00F2FE), width: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: const Size(120, 32),
                        ),
                        icon: const Icon(Icons.brush, size: 14),
                        label: const Text("CUSTOM EDITOR", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                        onPressed: () => _openEditor(_activeCustomFace),
                      ),
                      const SizedBox(height: 4),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: const Color(0xFFD946EF),
                          side: const BorderSide(color: Color(0xFFD946EF), width: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: const Size(120, 32),
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 14),
                        label: const Text("GENERATE AI", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                        onPressed: _openAiGenerator,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Interactive Robotic Face Screen
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    // Cyclic tap expression triggers
                    int nextIdx = (_currentExpression.index + 1) % FaceExpression.values.length;
                    _setExpression(FaceExpression.values[nextIdx]);
                  },
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0F19),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: faceColor.withOpacity(0.15), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: faceColor.withOpacity(0.03),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Glow background lines
                          Positioned.fill(
                            child: GridPaper(
                              color: faceColor.withOpacity(0.01),
                              divisions: 1,
                              subdivisions: 1,
                              interval: 60,
                            ),
                          ),
                          // The main custom painted face
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _eyeMovementController,
                              _blinkController,
                              _mouthWaveController,
                            ]),
                            builder: (context, child) {
                              if (_activeCustomFace != null) {
                                if (_activeCustomFace!.htmlCode != null && _webViewController != null) {
                                  // Live JS Canvas animation
                                  return AspectRatio(
                                    aspectRatio: 2.0,
                                    child: Center(
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox(
                                            width: double.infinity,
                                            child: WebViewWidget(controller: _webViewController!),
                                          ),
                                          if (_isInitializingFace)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.black87,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: const Color(0xFF00F2FE)),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    width: 14, height: 14,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F2FE))
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text("INITIALIZING FACE BLOCK...", style: TextStyle(color: Color(0xFF00F2FE), fontSize: 9, fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                } else {
                                  // Static Custom Pixel Grid
                                  return CustomPaint(
                                    size: const Size(double.infinity, double.infinity),
                                    painter: _PixelFacePainter(_activeCustomFace!.grid, faceColor),
                                  );
                                }
                              }
                              
                              return CustomPaint(
                                size: const Size(double.infinity, double.infinity),
                                painter: _RobotFacePainter(
                                  expression: _currentExpression,
                                  color: faceColor,
                                  isBlinking: _isBlinking,
                                  blinkValue: _blinkController.value,
                                  movementValue: _eyeMovementController.value,
                                  mouthValue: _mouthWaveController.value,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Expression triggers selectors cockpit panel
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "MICROCONTROLLER FACE TRIGGER OVERRIDES",
                    style: TextStyle(color: Colors.blueGrey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: FaceExpression.values.map((expr) {
                      IconData icon;
                      String label;
                      Color btnColor;
                      
                      switch (expr) {
                        case FaceExpression.neutral:
                          icon = Icons.blur_on_rounded;
                          label = "SCAN";
                          btnColor = const Color(0xFF00F2FE);
                          break;
                        case FaceExpression.happy:
                          icon = Icons.sentiment_very_satisfied_rounded;
                          label = "HAPPY";
                          btnColor = const Color(0xFF10B981);
                          break;
                        case FaceExpression.excited:
                          icon = Icons.auto_awesome_rounded;
                          label = "EXCITE";
                          btnColor = const Color(0xFFD946EF);
                          break;
                        case FaceExpression.shocked:
                          icon = Icons.electric_bolt_rounded;
                          label = "SHOCK";
                          btnColor = const Color(0xFFF59E0B);
                          break;
                        case FaceExpression.sad:
                          icon = Icons.sentiment_very_dissatisfied_rounded;
                          label = "SAD";
                          btnColor = const Color(0xFF3B82F6);
                          break;
                      }

                      bool isSelected = _currentExpression == expr;

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: InkWell(
                            onTap: () => _setExpression(expr),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? btnColor.withOpacity(0.15) : const Color(0xFF0B0F19),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? btnColor : Colors.white.withOpacity(0.08),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(icon, color: isSelected ? btnColor : Colors.blueGrey, size: 20),
                                  const SizedBox(height: 4),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.blueGrey,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaceBtn(String label, CustomFace? face) {
    bool isSelected = _activeCustomFace?.id == face?.id;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () {
          setState(() {
            _activeCustomFace = face;
          });
          
          if (face != null) {
            if (face.htmlCode != null) {
              _loadWebView(face.htmlCode!);
            } else {
              _webViewController?.loadHtmlString('');
              if (widget.isConnected) {
                // Only send static grid directly. WebView handles its own JS streaming.
                RobotService.sendCustomFace(base64Decode(face.encodeGrid()));
              }
            }
          } else {
            _webViewController?.loadHtmlString('');
            _setExpression(_currentExpression);
          }
        },
        onLongPress: face != null ? () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Delete Face?', style: TextStyle(color: Colors.white)),
              content: Text('Are you sure you want to delete "$label"?', style: const TextStyle(color: Colors.white70)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, true), 
                  child: const Text('Delete')
                ),
              ],
            )
          );
          if (confirm == true) {
            await FaceStorageService.deleteFace(face.id);
            if (_activeCustomFace?.id == face.id) {
              setState(() => _activeCustomFace = null);
            }
            await _loadFaces();
          }
        } : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00F2FE).withOpacity(0.2) : const Color(0xFF0B0F19),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? const Color(0xFF00F2FE) : Colors.white10),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: isSelected ? const Color(0xFF00F2FE) : Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelFacePainter extends CustomPainter {
  final List<List<bool>> grid;
  final Color color;
  
  _PixelFacePainter(this.grid, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final double pixelWidth = size.width / 128.0;
    final double pixelHeight = size.height / 64.0;
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 128; x++) {
        if (grid[y][x]) {
          canvas.drawRect(
            Rect.fromLTWH(x * pixelWidth, y * pixelHeight, pixelWidth, pixelHeight),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelFacePainter oldDelegate) {
    return oldDelegate.color != color || !identical(oldDelegate.grid, grid);
  }
}

class _RobotFacePainter extends CustomPainter {
  final FaceExpression expression;
  final Color color;
  final bool isBlinking;
  final double blinkValue; // 0.0 to 1.0 (1.0 = fully shut)
  final double movementValue; // 0.0 to 1.0 (for float drifting)
  final double mouthValue; // 0.0 to 1.0 (mouth movement ticks)

  _RobotFacePainter({
    required this.expression,
    required this.color,
    required this.isBlinking,
    required this.blinkValue,
    required this.movementValue,
    required this.mouthValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Replicate C++ drawing scale (128x128 virtual coordinate grid centered)
    final double scale = size.width / 128.0;
    canvas.scale(scale, scale);

    // Sine wave for breathing (cycles smoothly)
    double breath = math.sin(movementValue * 2.0 * math.pi);
    double breathY = breath * 1.5; // gentle vertical drift (-1.5 to +1.5 pixels)

    // Smoothly drift target look direction (only when idle/wonder)
    double lookX = 0.0;
    double lookY = 0.0;
    
    int state = 0;
    switch (expression) {
      case FaceExpression.neutral:
        state = 0; // IDLE
        lookX = 1.5 * math.sin(movementValue * 2.0 * math.pi);
        lookY = 0.4 * math.cos(movementValue * 2.0 * math.pi);
        break;
      case FaceExpression.happy:
        state = 1; // HAPPY
        break;
      case FaceExpression.excited:
        state = 4; // WINK
        break;
      case FaceExpression.shocked:
        state = 2; // WONDER
        lookX = 1.0 * math.sin(movementValue * 3.0 * math.pi);
        lookY = 0.3 * math.cos(movementValue * 3.0 * math.pi);
        break;
      case FaceExpression.sad:
        state = 3; // SLEEPY/SAD
        break;
    }

    // Layout coordinates (anchored to virtual 128x128 grid)
    double leftEyeX = 36.0;
    double rightEyeX = 92.0;
    double eyeY = 27.0 + 32.0 + breathY;  // Shift down by 32 to center square vertical
    double mouthX = 64.0;
    double mouthY = 46.0 + 32.0 + breathY;
    double blushY = eyeY + 11.0;

    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Paint blackPaint = Paint()
      ..color = const Color(0xFF0B0F19)
      ..style = PaintingStyle.fill;

    // Eyebrow helper
    void drawEyebrow(Canvas canvas, double x, double y, bool isLeft, int state) {
      double slantL = isLeft ? -1.0 : 1.0;
      double slantR = isLeft ? 1.0 : -1.0;
      
      if (state == 1) { // HAPPY (Curved upward)
        canvas.drawLine(Offset(x - 8, y - 13), Offset(x, y - 16), paint);
        canvas.drawLine(Offset(x, y - 16), Offset(x + 8, y - 13), paint);
        canvas.drawLine(Offset(x - 8, y - 12), Offset(x, y - 15), paint);
        canvas.drawLine(Offset(x, y - 15), Offset(x + 8, y - 12), paint);
      } 
      else if (state == 2) { // WONDER (Left raised higher)
        if (isLeft) {
          canvas.drawLine(Offset(x - 8, y - 18), Offset(x + 8, y - 16), paint);
          canvas.drawLine(Offset(x - 8, y - 17), Offset(x + 8, y - 15), paint);
        } else {
          canvas.drawLine(Offset(x - 8, y - 14 + slantL), Offset(x + 8, y - 14 + slantR), paint);
          canvas.drawLine(Offset(x - 8, y - 13 + slantL), Offset(x + 8, y - 13 + slantR), paint);
        }
      } 
      else if (state == 3) { // SLEEPY (Flat and low)
        canvas.drawLine(Offset(x - 8, y - 12), Offset(x + 8, y - 12), paint);
      } 
      else { // IDLE / DEFAULT
        canvas.drawLine(Offset(x - 8, y - 14 + slantL), Offset(x + 8, y - 14 + slantR), paint);
        canvas.drawLine(Offset(x - 8, y - 13 + slantL), Offset(x + 8, y - 13 + slantR), paint);
      }
    }

    // Eye helper
    void drawEye(Canvas canvas, double x, double y, bool open, bool happy, double lookX, double lookY) {
      if (!open) {
        // Cute chubby closed eye (thick horizontal rounded line)
        final RRect rrect = RRect.fromLTRBR(x - 7, y - 1.5, x + 7, y + 1.5, const Radius.circular(1.0));
        canvas.drawRRect(rrect, fillPaint);
      } 
      else if (happy) {
        // Sleek upward happy curve ( ^ )
        canvas.drawLine(Offset(x - 8, y + 2), Offset(x, y - 5), paint..strokeWidth = 1.6);
        canvas.drawLine(Offset(x, y - 5), Offset(x + 8, y + 2), paint..strokeWidth = 1.6);
        canvas.drawLine(Offset(x - 8, y + 3), Offset(x, y - 4), paint..strokeWidth = 1.6);
        canvas.drawLine(Offset(x, y - 4), Offset(x + 8, y + 3), paint..strokeWidth = 1.6);
        paint.strokeWidth = 1.3; // Reset
      } 
      else {
        // Open expressive eye
        final RRect rrect = RRect.fromLTRBR(x - 7, y - 9, x + 7, y + 9, const Radius.circular(3.5));
        canvas.drawRRect(rrect, fillPaint);
        
        // Draw pupils / sparkles in black (0) inside the white eye
        canvas.drawRect(Rect.fromLTWH(x + lookX + 1.0, y + lookY - 6.0, 3.0, 3.0), blackPaint); // Main top-right twinkle
        canvas.drawRect(Rect.fromLTWH(x + lookX - 4.0, y + lookY + 2.0, 2.0, 2.0), blackPaint); // Secondary bottom-left twinkle
      }
    }

    // Blush helper (recreates retro OLED screen checkerboard dither pattern)
    void drawBlush(Canvas canvas, double cx, double cy) {
      final Paint ditherPaint = Paint()
        ..color = Colors.pinkAccent.withOpacity(0.35)
        ..style = PaintingStyle.fill;
      
      for (double x = -4; x <= 4; x += 1.0) {
        for (double y = -2; y <= 2; y += 1.0) {
          if ((x*x) / 16.0 + (y*y) / 4.0 <= 1.0) {
            if ((x.toInt() + y.toInt()) % 2 == 0) {
              canvas.drawRect(Rect.fromLTWH(cx + x, cy + y, 0.7, 0.7), ditherPaint);
            }
          }
        }
      }
    }

    // Mouth helper
    void drawMouth(Canvas canvas, double cx, double cy, int state, double breath) {
      if (state == 1) { // HAPPY: Big open laughing mouth (crescent half-circle)
        double w = 9.0;
        double h = 9.0 + breath * 2.0; 
        
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(cx - w - 2.0, cy, cx + w + 2.0, cy + h + 2.0));
        canvas.drawCircle(Offset(cx, cy), w, fillPaint);
        canvas.restore();
      } 
      else if (state == 2) { // WONDER: Small talking "o" shape
        double r = 4.0 + breath * 1.0;
        canvas.drawCircle(Offset(cx, cy), r, paint..strokeWidth = 1.5);
        paint.strokeWidth = 1.3; // Reset
      } 
      else if (state == 3) { // SLEEPY: Small relaxed smile
        double r = 5.0;
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(cx - r - 2.0, cy - 2.0, cx + r + 2.0, cy + r));
        
        final Path path = Path();
        path.arcTo(Rect.fromCircle(center: Offset(cx, cy - 2.0), radius: r), 0, math.pi, true);
        path.arcTo(Rect.fromCircle(center: Offset(cx, cy - 4.0), radius: r + 1.0), math.pi, -math.pi, false);
        canvas.drawPath(path, fillPaint);
        
        canvas.restore();
      } 
      else if (state == 4) { // WINK / SMIRK: Cute side smirk
        double r = 6.0;
        double smirkX = cx + 3.0;
        
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(smirkX - r - 2.0, cy, smirkX + r + 2.0, cy + r));
        
        final Path path = Path();
        path.arcTo(Rect.fromCircle(center: Offset(smirkX, cy), radius: r), 0, math.pi, true);
        path.arcTo(Rect.fromCircle(center: Offset(smirkX, cy - 2.0), radius: r + 1.0), math.pi, -math.pi, false);
        canvas.drawPath(path, fillPaint);
        
        canvas.restore();
      } 
      else { // IDLE: Beautiful warm crescent smile
        double r = 8.0;
        double openHeight = 3.0 + breath * 2.0; 
        
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(cx - r - 2.0, cy, cx + r + 2.0, cy + r + openHeight));
        
        final Path path = Path();
        path.arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r), 0, math.pi, true);
        path.arcTo(Rect.fromCircle(center: Offset(cx, cy - openHeight), radius: r + 1.0), math.pi, -math.pi, false);
        canvas.drawPath(path, fillPaint);
        
        canvas.restore();
      }
    }

    // Determine drawing parameters based on active state
    bool drawLeftOpen = true;
    bool drawRightOpen = true;
    bool eyesHappy = false;

    if (state == 1) { // HAPPY
      eyesHappy = true;
    } 
    else if (state == 3) { // SLEEPY/SAD
      bool isDrowsyClosed = blinkValue > 0.45;
      drawLeftOpen = !isDrowsyClosed;
      drawRightOpen = !isDrowsyClosed;
    } 
    else if (state == 4) { // WINK (EXCITED)
      drawLeftOpen = false; // Left eye winks closed
      drawRightOpen = true; // Right eye open sparkling
    } 
    else { // IDLE or WONDER
      drawLeftOpen = !isBlinking;
      drawRightOpen = !isBlinking;
    }

    // A. Draw Eyebrows
    drawEyebrow(canvas, leftEyeX, eyeY, true, state);
    drawEyebrow(canvas, rightEyeX, eyeY, false, state);

    // B. Draw Eyes
    drawEye(canvas, leftEyeX, eyeY, drawLeftOpen, eyesHappy, lookX, lookY);
    drawEye(canvas, rightEyeX, eyeY, drawRightOpen, eyesHappy, lookX, lookY);

    // C. Draw Blush (Dithered Cheek Circles)
    if (state == 0 || state == 1 || state == 4) {
      drawBlush(canvas, leftEyeX, blushY);
      drawBlush(canvas, rightEyeX, blushY);
    }

    // D. Draw Mouth
    drawMouth(canvas, mouthX, mouthY, state, breath);
  }

  @override
  bool shouldRepaint(covariant _RobotFacePainter oldDelegate) {
    return oldDelegate.expression != expression ||
        oldDelegate.color != color ||
        oldDelegate.isBlinking != isBlinking ||
        oldDelegate.blinkValue != blinkValue ||
        oldDelegate.movementValue != movementValue ||
        oldDelegate.mouthValue != mouthValue;
  }
}
