import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AgenticMemoryService {
  static const String _traitsKey = 'ira_harshita_traits';
  static const String _historyKey = 'ira_chat_history';
  
  static late SharedPreferences _prefs;
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  // --- TRAITS MANAGEMENT ---
  
  /// Get all known traits about Harshita
  static Map<String, dynamic> getTraits() {
    final String? traitsJson = _prefs.getString(_traitsKey);
    if (traitsJson == null) return {};
    try {
      return jsonDecode(traitsJson) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  /// Add new traits (merges with existing traits)
  static Future<void> updateTraits(Map<String, dynamic> newTraits) async {
    if (newTraits.isEmpty) return;
    
    final currentTraits = getTraits();
    currentTraits.addAll(newTraits);
    
    await _prefs.setString(_traitsKey, jsonEncode(currentTraits));
  }

  // --- CHAT HISTORY MANAGEMENT ---

  /// Get the last N conversation turns
  static List<String> getHistory({int limit = 10}) {
    final List<String>? history = _prefs.getStringList(_historyKey);
    if (history == null) return [];
    
    // Return only the last N items
    if (history.length > limit) {
      return history.sublist(history.length - limit);
    }
    return history;
  }

  /// Add a turn to the chat history
  static Future<void> addHistoryTurn(String userText, String aiResponse) async {
    final history = _prefs.getStringList(_historyKey) ?? [];
    
    history.add('User (Harshita): "$userText"');
    history.add('IRA: "$aiResponse"');
    
    // Keep history size manageable (keep last 30 messages)
    if (history.length > 30) {
      history.removeRange(0, history.length - 30);
    }
    
    await _prefs.setStringList(_historyKey, history);
  }
}
