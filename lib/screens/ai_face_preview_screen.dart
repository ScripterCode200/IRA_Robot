import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/cloud_ai_service.dart';
import '../services/robot_service.dart';
import '../models/custom_face_model.dart';
import '../services/face_storage_service.dart';

class AIFacePreviewScreen extends StatefulWidget {
  final bool isConnected;

  const AIFacePreviewScreen({super.key, required this.isConnected});

  @override
  State<AIFacePreviewScreen> createState() => _AIFacePreviewScreenState();
}

class _AIFacePreviewScreenState extends State<AIFacePreviewScreen> {
  final TextEditingController _promptController = TextEditingController();
  bool _isGenerating = false;
  String? _generatedHtml;
  late final WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'RobotChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (widget.isConnected) {
            try {
              final bytes = base64Decode(message.message);
              RobotService.sendCustomFace(bytes);
            } catch (e) {
              debugPrint("Error streaming frame: $e");
            }
          }
        },
      );
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _generatedHtml = null;
    });

    final html = await CloudAiService.generateAnimatedFaceCode(prompt);

    setState(() {
      _isGenerating = false;
      if (html != null && html.isNotEmpty) {
        _generatedHtml = html;
        _webViewController.loadHtmlString(_generatedHtml!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to generate animation. Try again.")),
        );
      }
    });
  }

  Future<void> _saveFace() async {
    if (_generatedHtml == null) return;
    
    // We save the HTML string inside the CustomFace's name field with a prefix,
    // or we can add an `htmlCode` field to CustomFace.
    // For now, let's just show a dialog to ask for the name, and store the HTML in a new parameter if we had one.
    // Wait, CustomFace only stores a 128x64 grid.
    // We need to add an `htmlCode` field to `CustomFace` to save JS animations!
    
    // For now, since CustomFace expects a 128x64 grid, we can just save it with a special tag.
    // Actually, I should update `CustomFace` to optionally hold `htmlCode`.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('AI Face Generator', style: TextStyle(fontSize: 14, fontFamily: 'monospace')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _promptController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "e.g. A glowing eye that looks left and right",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.auto_awesome, color: Color(0xFF00F2FE)),
                  onPressed: _isGenerating ? null : _generate,
                ),
              ),
              onSubmitted: (_) => _isGenerating ? null : _generate(),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Center(
                child: _isGenerating
                    ? const CircularProgressIndicator(color: Color(0xFF00F2FE))
                    : _generatedHtml != null
                        ? AspectRatio(
                            aspectRatio: 2.0,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFF00F2FE).withOpacity(0.5), width: 2),
                              ),
                              child: WebViewWidget(controller: _webViewController),
                            ),
                          )
                        : const Text(
                            "Type a prompt and press the magic wand to generate an animated face!",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
              ),
            ),
            const SizedBox(height: 24),
            if (_generatedHtml != null)
               ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F2FE).withOpacity(0.2),
                  foregroundColor: const Color(0xFF00F2FE),
                  side: const BorderSide(color: Color(0xFF00F2FE)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
                icon: const Icon(Icons.save),
                label: const Text("SAVE THIS ANIMATION"),
                onPressed: () {
                   // Return the generated HTML string back to FaceScreen to handle saving
                   Navigator.pop(context, _generatedHtml);
                },
              ),
          ],
        ),
      ),
    );
  }
}
