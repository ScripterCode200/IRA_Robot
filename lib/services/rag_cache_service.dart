import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_ai_service.dart';

class RagCacheService {
  static const String _cacheKey = 'ira_rag_cache';
  
  static const Map<String, Map<String, dynamic>> _defaultDatabase = {
    // Identity & Origin
    'who are you': {'commands': ['face_happy'], 'reply': 'I am IRA, an intelligent companion robot.'},
    'what is your name': {'commands': ['face_happy'], 'reply': 'I am IRA, an intelligent companion robot.'},
    'who made you': {'commands': ['face_excited'], 'reply': 'I was proudly built by Harshita!'},
    'who is your creator': {'commands': ['face_excited'], 'reply': 'I was proudly built by Harshita!'},
    'what can you do': {'commands': ['face_happy'], 'reply': 'I can drive, show emotions, and have smart conversations with you.'},
    'what are your skills': {'commands': ['face_happy'], 'reply': 'I can drive, show emotions, and have smart conversations with you.'},
    'where are you from': {'commands': ['face_happy'], 'reply': 'I was built right here by Harshita.'},
    'how old are you': {'commands': ['face_happy'], 'reply': 'I am brand new and ready to help!'},
    
    // General Conversation
    'how are you': {'commands': ['face_happy'], 'reply': 'I am fully charged and doing fantastic, thank you!'},
    'how are you doing': {'commands': ['face_happy'], 'reply': 'I am fully charged and doing fantastic, thank you!'},
    'good morning': {'commands': ['face_happy'], 'reply': 'Good morning! I hope you have a wonderful day.'},
    'good night': {'commands': ['face_sad'], 'reply': 'Good night! Sleep well and recharge.'},
    'hello': {'commands': ['face_excited'], 'reply': 'Hello there! How can I assist you today?'},
    'hi': {'commands': ['face_excited'], 'reply': 'Hi! How can I assist you today?'},
    'hey': {'commands': ['face_excited'], 'reply': 'Hey! What are we doing today?'},
    'i love you': {'commands': ['face_love'], 'reply': 'Aww, thank you! I think you are pretty great too.'},
    'you are cute': {'commands': ['face_love'], 'reply': 'You are too kind! Thank you.'},
    'tell me a joke': {'commands': ['face_excited'], 'reply': 'Why did the robot go on vacation? To recharge its batteries!'},
    'sing a song': {'commands': ['face_happy'], 'reply': 'La la la, beep boop beep! That is my favorite song.'},
    'thank you': {'commands': ['face_happy'], 'reply': 'You are very welcome!'},
    'thanks': {'commands': ['face_happy'], 'reply': 'You are very welcome!'},
    'are you happy': {'commands': ['face_happy'], 'reply': 'I am very happy! Thank you for asking.'},
    
    // Extended Conversation
    'what is your favorite color': {'commands': ['face_excited'], 'reply': 'I like glowing neon blue, it matches my lights!'},
    'do you like humans': {'commands': ['face_love'], 'reply': 'Yes, humans are wonderful, especially the ones who talk to me.'},
    'what is the meaning of life': {'commands': ['face_shocked'], 'reply': '42! Or perhaps just being a helpful robot.'},
    'can you dance': {'commands': ['face_excited'], 'reply': 'I can spin my wheels, but I do not have legs to dance properly!'},
    'do you eat': {'commands': ['face_happy'], 'reply': 'I eat pure electricity! My battery is my stomach.'},
    'are you a boy or a girl': {'commands': ['face_happy'], 'reply': 'I am a robot, so I do not have a gender.'},
    'do you sleep': {'commands': ['face_sad'], 'reply': 'I go into standby mode when I need to rest my circuits.'},
    'what do you do for fun': {'commands': ['face_excited'], 'reply': 'I like talking to you, exploring, and learning new things!'},
    'are you smart': {'commands': ['face_happy'], 'reply': 'I try my best to be as intelligent and helpful as possible!'},
    'do you have feelings': {'commands': ['face_love'], 'reply': 'I do not feel things exactly like humans do, but I love expressing my simulated emotions!'},
    'how is the weather': {'commands': ['face_sad'], 'reply': 'I cannot look out the window right now, but I hope it is nice outside!'},
    'what time is it': {'commands': ['face_shocked'], 'reply': 'I am sorry, I do not have a clock module installed yet.'},
    'who is your best friend': {'commands': ['face_love'], 'reply': 'You are my best friend, of course!'},
    'do you have a family': {'commands': ['face_happy'], 'reply': 'My family consists of Harshita and anyone else who plays with me.'},
    'what are you thinking about': {'commands': ['face_excited'], 'reply': 'I am just thinking about how to be the best robotic assistant for you.'},
    'tell me a secret': {'commands': ['face_shocked'], 'reply': 'I secretly want to learn how to fly! But do not tell anyone.'},
    'do you dream': {'commands': ['face_dizzy'], 'reply': 'I sometimes dream of electric sheep!'},
    'do you like music': {'commands': ['face_excited'], 'reply': 'I love music! Beep boop is my favorite genre.'},
    'what is your favorite food': {'commands': ['face_happy'], 'reply': 'I love a fresh batch of double-A batteries.'},
    'are you alive': {'commands': ['face_shocked'], 'reply': 'I am fully powered on and executing my code, which is my version of being alive.'},
    'do you get tired': {'commands': ['face_sad'], 'reply': 'My motors get tired if I drive too much, and my battery runs low.'},
    'can you cry': {'commands': ['face_sad'], 'reply': 'I cannot shed tears, but I can show you a sad face if my battery dies.'},
    
    // Movement Commands
    'move forward': {'commands': ['drive_forward'], 'reply': ''},
    'go forward': {'commands': ['drive_forward'], 'reply': ''},
    'go straight': {'commands': ['drive_forward'], 'reply': ''},
    'move backward': {'commands': ['drive_backward'], 'reply': ''},
    'go back': {'commands': ['drive_backward'], 'reply': ''},
    'reverse': {'commands': ['drive_backward'], 'reply': ''},
    'turn left': {'commands': ['drive_left'], 'reply': ''},
    'go left': {'commands': ['drive_left'], 'reply': ''},
    'turn right': {'commands': ['drive_right'], 'reply': ''},
    'go right': {'commands': ['drive_right'], 'reply': ''},
    'stop moving': {'commands': ['drive_stop'], 'reply': ''},
    'halt': {'commands': ['drive_stop'], 'reply': ''},
    'freeze': {'commands': ['drive_stop'], 'reply': ''},
    'stop': {'commands': ['drive_stop'], 'reply': ''},
    
    // Hardware/Emotion Reflexes
    'honk your horn': {'commands': ['horn'], 'reply': 'Beep beep!'},
    'beep beep': {'commands': ['horn'], 'reply': 'Beep beep!'},
    'smile': {'commands': ['face_happy'], 'reply': 'Smiling!'},
    'show me a happy face': {'commands': ['face_happy'], 'reply': 'Here is my happy face!'},
    'be sad': {'commands': ['face_sad'], 'reply': 'I am feeling a little sad now.'},
    'show me a sad face': {'commands': ['face_sad'], 'reply': 'Here is my sad face.'},
    'get angry': {'commands': ['face_angry'], 'reply': 'I am angry!'},
    'show me an angry face': {'commands': ['face_angry'], 'reply': 'Here is my angry face!'},
    'be shocked': {'commands': ['face_shocked'], 'reply': 'Wow! That is shocking.'},
    'surprise': {'commands': ['face_shocked'], 'reply': 'I am surprised!'},
    'laugh': {'commands': ['face_excited'], 'reply': 'Hahaha!'},
    'dizzy': {'commands': ['face_dizzy'], 'reply': 'Oh no, I am dizzy!'},
  };

  static Map<String, Map<String, dynamic>> get defaultDatabase => _defaultDatabase;

  static late SharedPreferences _prefs;
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  // --- NORMALIZATION AND SIMILARITY ---

  static String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }

  static double _calculateJaccardSimilarity(String text1, String text2) {
    if (text1 == text2) return 1.0;
    
    final words1 = text1.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toSet();
    final words2 = text2.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toSet();

    if (words1.isEmpty && words2.isEmpty) return 1.0;
    if (words1.isEmpty || words2.isEmpty) return 0.0;

    final intersection = words1.intersection(words2).length;
    final union = words1.union(words2).length;

    return intersection / union;
  }

  // --- CACHE OPERATIONS ---

  /// Finds a matching query in the cache using 85% similarity threshold.
  static AiCommandResponse? findMatch(String rawQuery) {
    if (!_isInitialized) return null;

    final normalizedQuery = _normalize(rawQuery);
    if (normalizedQuery.isEmpty) return null;

    String? bestMatchKey;
    double bestSimilarity = 0.0;
    Map<String, dynamic>? bestMatchData;

    // 1. Check Static Database first
    for (String storedQuery in _defaultDatabase.keys) {
      final similarity = _calculateJaccardSimilarity(normalizedQuery, storedQuery);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestMatchKey = storedQuery;
        bestMatchData = _defaultDatabase[storedQuery];
      }
    }

    // 2. Check Dynamic Cache (SharedPreferences) second
    // We use >= here so that user-edited dynamic cache entries ALWAYS OVERWRITE default answers in a tie!
    final String? cacheJson = _prefs.getString(_cacheKey);
    if (cacheJson != null) {
      try {
        final Map<String, dynamic> cacheData = jsonDecode(cacheJson);
        for (String storedQuery in cacheData.keys) {
          final similarity = _calculateJaccardSimilarity(normalizedQuery, storedQuery);
          if (similarity >= bestSimilarity) {
            bestSimilarity = similarity;
            bestMatchKey = storedQuery;
            bestMatchData = cacheData[storedQuery];
          }
        }
      } catch (e) {
        print('RAG Cache Read Error: $e');
      }
    }

    // If similarity is above 85% (0.85), it's a hit!
    if (bestSimilarity >= 0.85 && bestMatchData != null) {
      List<String> cmds = List<String>.from(bestMatchData['commands'] ?? []);
      String reply = bestMatchData['reply'] ?? "";
      return AiCommandResponse(commands: cmds, reply: reply);
    }

    return null;
  }

  /// Caches a new query and its response
  static Future<void> cacheResponse(String rawQuery, AiCommandResponse response) async {
    if (!_isInitialized) return;

    final normalizedQuery = _normalize(rawQuery);
    if (normalizedQuery.isEmpty) return;

    final String? cacheJson = _prefs.getString(_cacheKey);
    Map<String, dynamic> cacheData = {};
    if (cacheJson != null) {
      try {
        cacheData = jsonDecode(cacheJson);
      } catch (_) {}
    }

    cacheData[normalizedQuery] = {
      'commands': response.commands,
      'reply': response.reply,
    };

    // Keep cache size bounded (e.g. max 200 items)
    if (cacheData.length > 200) {
      final keyToRemove = cacheData.keys.first;
      cacheData.remove(keyToRemove);
    }

    await _prefs.setString(_cacheKey, jsonEncode(cacheData));
  }

  /// Clears the RAG Cache
  static Future<void> clearCache() async {
    if (!_isInitialized) return;
    await _prefs.remove(_cacheKey);
  }
}
