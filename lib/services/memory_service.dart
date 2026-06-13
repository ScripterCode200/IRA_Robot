import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

class EpisodicMemory {
  final String id;
  final int timestamp;
  final String userPrompt;
  final String aiResponse;
  final String thumbnailBase64;

  EpisodicMemory({
    required this.id,
    required this.timestamp,
    required this.userPrompt,
    required this.aiResponse,
    required this.thumbnailBase64,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp,
    'userPrompt': userPrompt,
    'aiResponse': aiResponse,
    'thumbnailBase64': thumbnailBase64,
  };

  factory EpisodicMemory.fromJson(Map<String, dynamic> json) => EpisodicMemory(
    id: json['id'],
    timestamp: json['timestamp'],
    userPrompt: json['userPrompt'],
    aiResponse: json['aiResponse'],
    thumbnailBase64: json['thumbnailBase64'],
  );
}

class MemoryService {
  static const _key = 'episodic_memories';
  static SharedPreferences? _prefs;

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> addMemory(String userPrompt, String aiResponse, Uint8List rawFrame) async {
    if (_prefs == null) return;
    
    // Compress and resize the frame to a tiny thumbnail (e.g. 160 width) to save space
    String base64Thumb = "";
    try {
      final image = img.decodeImage(rawFrame);
      if (image != null) {
        final resized = img.copyResize(image, width: 160);
        final compressed = img.encodeJpg(resized, quality: 40); // High compression
        base64Thumb = base64Encode(compressed);
      }
    } catch (e) {
      debugPrint("Failed to compress memory thumbnail: $e");
    }

    final memory = EpisodicMemory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      userPrompt: userPrompt,
      aiResponse: aiResponse,
      thumbnailBase64: base64Thumb,
    );

    final memories = getMemories();
    memories.insert(0, memory); // Add to beginning (latest first)
    
    // Keep max 200 memories to save space
    if (memories.length > 200) {
      memories.removeLast();
    }

    await _prefs!.setStringList(_key, memories.map((e) => jsonEncode(e.toJson())).toList());
  }

  static List<EpisodicMemory> getMemories() {
    if (_prefs == null) return [];
    final jsonList = _prefs!.getStringList(_key) ?? [];
    return jsonList.map((e) => EpisodicMemory.fromJson(jsonDecode(e))).toList();
  }
}
