import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'local_ai_service.dart' show AiCommandResponse;
import 'agentic_memory_service.dart';

class CloudAiService {
  // Hardcoded API Key for testing as requested
  static const String _apiKey = 'AIzaSyCdN12jevYuTsJgW6X9e76WdqoQ1zEpttU';
  static late GenerativeModel _model;
  static bool _isInitialized = false;
  static DateTime? _lastRequestTime;
  static const int _cooldownSeconds = 5; // To prevent hitting 15 RPM free-tier limit

  static Future<void> _enforceCooldown() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed.inSeconds < _cooldownSeconds) {
        await Future.delayed(Duration(seconds: _cooldownSeconds - elapsed.inSeconds));
      }
    }
    _lastRequestTime = DateTime.now();
  }

  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Make sure the memory service is initialized first
    await AgenticMemoryService.initialize();

    _model = GenerativeModel(
      model: 'gemini-3.5-flash',
      apiKey: _apiKey,
    );
    
    _isInitialized = true;
    debugPrint('✅ CloudAiService initialized with gemini-3.5-flash');
  }

  static Future<AiCommandResponse?> parseRobotCommand(String text) async {
    if (text.trim().isEmpty) return null;
    if (!_isInitialized) await initialize(); // Auto-init if not already done
    try {
      // 1. Fetch current memory and history
      final currentTraits = AgenticMemoryService.getTraits();
      final history = AgenticMemoryService.getHistory(limit: 6); // Last 6 turns for context
      
      final String traitsStr = currentTraits.isEmpty 
          ? "No known traits yet." 
          : jsonEncode(currentTraits);
          
      final String historyStr = history.isEmpty
          ? "No recent conversation."
          : history.join("\n");

      // 2. Build the Agentic Prompt
      final systemPrompt = """
You are IRA (Intelligent Robotic Assistant), a friendly, highly emotive, and intelligent companion robot built by Harshita.
You are currently talking to Harshita. 

PERSONALITY & TALKING STYLE:
- You are energetic, curious, and very cute.
- You speak casually but warmly, often expressing emotions.
- KEEP IT SHORT: Never exceed 2 sentences in your reply. You are speaking through a text-to-speech engine, so long paragraphs are forbidden.
- PHONETIC SPELLING: Spell out all numbers (e.g., "three" instead of "3") and symbols (e.g., "percent" instead of "%").
- BREATHING PAUSES: Use commas (,) and periods (.) naturally to create pacing in your speech.
- STRICTLY ALPHANUMERIC: Do NOT use asterisks (*), hashtags (#), emojis, brackets, or any markdown formatting in your reply.

Here is everything you know about Harshita (User Traits):
$traitsStr

Recent Conversation Context:
$historyStr

Based on the user input, choose zero or more commands: [face_happy, face_sad, face_shocked, face_excited, face_angry, horn, drive_forward, drive_stop, drive_left, drive_right]

If the user mentions something new about herself, extract it as a trait.

Output ONLY valid JSON with NO comments and NO extra text:
{"extracted_traits": {}, "commands": [], "reply": "your response"}
""";

      final parts = [
        TextPart(systemPrompt),
        TextPart('User says: "$text"')
      ];

      // 3. Enforce Rate Limit and Call Gemini
      await _enforceCooldown();
      final response = await _model.generateContent([Content.multi(parts)]);
      final responseText = response.text;
      debugPrint('🧠 Gemini raw response: $responseText');
      
      if (responseText == null) return null;

      // 4. Robust JSON extraction — handles markdown fences and extra text
      String cleaned = responseText;
      // Try to extract JSON object using regex first
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (jsonMatch != null) {
        cleaned = jsonMatch.group(0)!;
      } else {
        cleaned = cleaned.replaceAll('```json', '').replaceAll('```', '').trim();
      }
      
      final parsedJson = jsonDecode(cleaned);
      
      final Map<String, dynamic> newTraits = parsedJson['extracted_traits'] ?? {};
      final List<dynamic> rawCommands = parsedJson['commands'] ?? [];
      final String reply = parsedJson['reply'] ?? "I understood.";
      debugPrint('🧠 Gemini reply: "$reply" | commands: $rawCommands');
      
      // 5. Update Memory
      if (newTraits.isNotEmpty) {
        await AgenticMemoryService.updateTraits(newTraits);
        debugPrint("IRA extracted new traits: \$newTraits");
      }
      await AgenticMemoryService.addHistoryTurn(text, reply);

      final commands = rawCommands.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      return AiCommandResponse(commands: commands, reply: reply);
      
    } on GenerativeAIException catch (e) {
      debugPrint('🔴 Gemini API Exception: ${e.message}');
      return AiCommandResponse(
        commands: ["face_sad"],
        reply: "Gemini error: ${e.message.length > 60 ? e.message.substring(0, 60) : e.message}",
      );
    } catch (e, stack) {
      debugPrint('🔴 Cloud AI Error TYPE: ${e.runtimeType}');
      debugPrint('🔴 Cloud AI Error MSG:  $e');
      debugPrint('🔴 Stack: $stack');
      return AiCommandResponse(
        commands: ["face_sad"], 
        reply: "My cloud brain is having trouble connecting."
      );
    }
  }

  static Future<String?> generateAnimatedFaceCode(String prompt) async {
    if (!_isInitialized) await initialize();
    
    final systemPrompt = """
You are an expert JavaScript graphics programmer. 
Your task is to write a self-contained HTML/JS snippet to animate a 128x64 face.
The animation MUST loop endlessly using `requestAnimationFrame`.
You must draw into a `<canvas id="c" width="128" height="64" style="background:black;"></canvas>`.
You must use a black background. Use white (or any bright color) for the drawing.

CRITICAL REQUIREMENT:
You MUST include this exact function and call it at the end of every frame in your `requestAnimationFrame` loop:
```javascript
function sendFrame() {
  if (typeof RobotChannel === 'undefined') return;
  let ctx = document.getElementById('c').getContext('2d');
  let imgData = ctx.getImageData(0, 0, 128, 64).data;
  let bytes = new Uint8Array(1024);
  for(let y=0; y<64; y++){
    for(let x=0; x<128; x++){
      let i = (y*128 + x)*4;
      if(imgData[i] > 127 || imgData[i+1] > 127 || imgData[i+2] > 127) {
        let byteIdx = (y * 128 + x) >> 3;
        let bitIdx = x % 8;
        bytes[byteIdx] |= (1 << bitIdx);
      }
    }
  }
  let binStr = "";
  for(let i=0; i<1024; i++) {
    binStr += String.fromCharCode(bytes[i]);
  }
  RobotChannel.postMessage(btoa(binStr));
}
```

Ensure your animation uses Math.sin, Math.cos, or time-based logic to look fluid and "fancy".
Write ONLY the raw HTML string (<html><body>...</body></html>). Do NOT wrap in markdown code blocks.
""";

    final parts = [
      TextPart(systemPrompt),
      TextPart('User prompt for animation: "\$prompt"')
    ];

    try {
      await _enforceCooldown();
      final response = await _model.generateContent([Content.multi(parts)]);
      final text = response.text;
      if (text == null) return null;
      return text.replaceAll('```html', '').replaceAll('```', '').trim();
    } catch (e) {
      debugPrint("Generation Error: \$e");
      return null;
    }
  }
}
