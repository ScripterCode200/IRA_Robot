import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/agentic_memory_service.dart';
import '../services/rag_cache_service.dart';

class PersonalityEditorScreen extends StatefulWidget {
  const PersonalityEditorScreen({super.key});

  @override
  State<PersonalityEditorScreen> createState() => _PersonalityEditorScreenState();
}

class _PersonalityEditorScreenState extends State<PersonalityEditorScreen> {
  late TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: AgenticMemoryService.getSystemPrompt());
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _savePrompt() async {
    HapticFeedback.mediumImpact();
    await AgenticMemoryService.setSystemPrompt(_promptController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Personality Prompt Saved Successfully!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
    );
  }

  void _resetToDefault() async {
    HapticFeedback.lightImpact();
    await AgenticMemoryService.resetPrompt();
    setState(() {
      _promptController.text = AgenticMemoryService.getSystemPrompt();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to Default Personality', style: TextStyle(color: Colors.white)), backgroundColor: Colors.blueGrey),
    );
  }

  void _clearMemory() async {
    HapticFeedback.heavyImpact();
    await AgenticMemoryService.clearMemory();
    await RagCacheService.clearCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat History, Cache, and Traits Cleared!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.deepOrange),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // AMOLED Pitch Black
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0B132B), Color(0xFF000000)],
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                // Glassmorphic App Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.5),
                    border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'Soul & Personality',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const Icon(Icons.psychology_alt_rounded, color: Color(0xFF00F2FE), size: 28),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),

                // Main Content
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Description
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F2FE).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF00F2FE).withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Color(0xFF00F2FE), size: 24),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  "This prompt defines how IRA acts, speaks, and responds. Both Local and Cloud AI models will adopt this persona.",
                                  style: TextStyle(color: Colors.blueGrey.shade100, fontSize: 13, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Editor TextField
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF00F2FE).withOpacity(0.05), blurRadius: 20, spreadRadius: 5),
                            ],
                          ),
                          child: TextField(
                            controller: _promptController,
                            maxLines: 12,
                            style: const TextStyle(
                              color: Colors.white, 
                              fontSize: 15, 
                              height: 1.6, 
                              fontFamily: 'monospace',
                            ),
                            decoration: InputDecoration(
                              hintText: "Define the robot's personality here...",
                              hintStyle: TextStyle(color: Colors.blueGrey.withOpacity(0.5)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(20),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _savePrompt,
                                icon: const Icon(Icons.save_rounded, size: 20),
                                label: const Text("SAVE PROMPT", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00F2FE).withOpacity(0.15),
                                  foregroundColor: const Color(0xFF00F2FE),
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _resetToDefault,
                                icon: const Icon(Icons.restore_rounded, size: 20),
                                label: const Text("DEFAULT", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.05),
                                  foregroundColor: Colors.white70,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Danger Zone Divider
                        Row(
                          children: [
                            const Expanded(child: Divider(color: Colors.white12)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text("DANGER ZONE", style: TextStyle(color: Colors.redAccent.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                            ),
                            const Expanded(child: Divider(color: Colors.white12)),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Memory Wiper
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.2), width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), shape: BoxShape.circle),
                                    child: const Icon(Icons.memory_rounded, color: Colors.redAccent, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text("Wipe Memory & Traits", style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Clear the robot's short-term conversation history and extracted long-term memory traits entirely.",
                                style: TextStyle(color: Colors.redAccent.withOpacity(0.6), fontSize: 12, height: 1.4),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _clearMemory,
                                  icon: const Icon(Icons.delete_forever_rounded, size: 20),
                                  label: const Text("ERASE MEMORY", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent.withOpacity(0.15),
                                    foregroundColor: Colors.redAccent,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: const BorderSide(color: Colors.redAccent, width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
