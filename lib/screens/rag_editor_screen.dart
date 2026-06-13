import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/rag_cache_service.dart';
import '../services/local_ai_service.dart'; // To get AiCommandResponse class

class RagEditorScreen extends StatefulWidget {
  const RagEditorScreen({super.key});

  @override
  State<RagEditorScreen> createState() => _RagEditorScreenState();
}

class _RagEditorScreenState extends State<RagEditorScreen> {
  Map<String, dynamic> _cacheData = {};
  Map<String, dynamic> _combinedData = {};

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cacheJson = prefs.getString('ira_rag_cache');
    
    setState(() {
      _cacheData = {};
      if (cacheJson != null) {
        try {
          _cacheData = jsonDecode(cacheJson);
        } catch (_) {}
      }

      // Combine static and dynamic
      _combinedData = {
        ...RagCacheService.defaultDatabase,
        ..._cacheData,
      };
    });
  }

  Future<void> _saveCustomReply(String query, String newReply, List<String> commands) async {
    final response = AiCommandResponse(commands: commands, reply: newReply);
    await RagCacheService.cacheResponse(query, response);
    await _loadCache(); // Reload
  }

  Future<void> _deleteCustomReply(String query) async {
    final prefs = await SharedPreferences.getInstance();
    _cacheData.remove(query);
    await prefs.setString('ira_rag_cache', jsonEncode(_cacheData));
    await _loadCache();
  }

  void _showEditDialog(String query, String currentReply, List<String> commands, bool isCustom) {
    HapticFeedback.mediumImpact();
    final TextEditingController _replyController = TextEditingController(text: currentReply);
    final TextEditingController _cmdController = TextEditingController(text: commands.join(', '));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Edit Data for "$query"', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Spoken Reply:", style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: _replyController,
                style: const TextStyle(color: Color(0xFF00F2FE), fontSize: 13),
                maxLines: 3,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black45,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  hintText: "Enter new reply...",
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
              const SizedBox(height: 16),
              const Text("Robot Commands (comma separated):", style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: _cmdController,
                style: const TextStyle(color: Colors.pinkAccent, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black45,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  hintText: "e.g. face_happy, drive_forward",
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isCustom)
            TextButton(
              onPressed: () {
                _deleteCustomReply(query);
                Navigator.pop(context);
              },
              child: const Text("Delete Override", style: TextStyle(color: Colors.redAccent)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final newCmds = _cmdController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              _saveCustomReply(query, _replyController.text.trim(), newCmds);
              Navigator.pop(context);
            },
            child: const Text("Save", style: TextStyle(color: Color(0xFF00F2FE), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // AMOLED Black
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "RAG Database",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _combinedData.isEmpty
          ? const Center(child: Text("No data found.", style: TextStyle(color: Colors.white70)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _combinedData.keys.length,
              separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
              itemBuilder: (context, index) {
                final key = _combinedData.keys.elementAt(index);
                final reply = _combinedData[key]['reply'] ?? '';
                final List<String> commands = List<String>.from(_combinedData[key]['commands'] ?? []);
                final isCustom = _cacheData.containsKey(key);

                return InkWell(
                  onLongPress: () => _showEditDialog(key, reply, commands, isCustom),
                  onTap: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Long-press to edit", style: TextStyle(color: Colors.amber)),
                        backgroundColor: Color(0xFF1E1E1E),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('"$key"', style: TextStyle(color: isCustom ? Colors.amber : const Color(0xFF00F2FE), fontSize: 14, fontWeight: FontWeight.bold)),
                            if (isCustom) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.auto_awesome, color: Colors.amber, size: 12),
                            ]
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          reply.toString().isEmpty ? "(Action Only / No Speech)" : reply,
                          style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                        ),
                        if (commands.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: commands.map((c) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.pinkAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.pinkAccent.withOpacity(0.4))),
                              child: Text(c, style: const TextStyle(color: Colors.pinkAccent, fontSize: 9, fontFamily: 'monospace')),
                            )).toList(),
                          ),
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
