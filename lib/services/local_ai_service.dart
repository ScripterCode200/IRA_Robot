import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;
import 'agentic_memory_service.dart';

class AiCommandResponse {
  final List<String> commands;
  final String reply;
  AiCommandResponse({required this.commands, required this.reply});
}

class LocalAiService {
  static bool _isInitialized = false;
  static bool _useRealGemma = false;

  static bool get hasRealGemma => _useRealGemma;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Platform.isAndroid) {
        if (!await Permission.storage.request().isGranted) {
          debugPrint("Storage permission denied for Local AI.");
        }
      }

      final directory = await getExternalStorageDirectory();
      final modelPath = '${directory?.path}/gemma_model.bin';
      final modelFile = File(modelPath);
      
      if (modelFile.existsSync()) {
        final fileSize = modelFile.lengthSync();
        const minModelSize = 100 * 1024 * 1024; // 100 MB minimum for a real Gemma model
        
        if (fileSize < minModelSize) {
          debugPrint("Local AI: gemma_model.bin is only ${fileSize} bytes — corrupt/incomplete download. Deleting...");
          modelFile.deleteSync();
          debugPrint("Local AI: Corrupt model deleted. Please re-download from the dashboard.");
        } else {
          await FlutterGemma.initialize();
          
          // Always re-install/re-register the model file on every startup.
          debugPrint("Local AI: Registering model (${(fileSize / 1024 / 1024).toStringAsFixed(0)} MB) with FlutterGemma engine...");
          try {
            await FlutterGemma.installModel(
              modelType: ModelType.gemmaIt,
              fileType: ModelFileType.binary,
            ).fromFile(modelPath).install();
          } catch (e) {
            debugPrint("Local AI: Install attempt result: $e");
          }

          _useRealGemma = true;
          debugPrint("Local AI: Gemma 2B loaded successfully from $modelPath");
        }
      } else {
        debugPrint("Local AI: gemma_model.bin not found at $modelPath. Using Lightweight Offline Ruleset.");
      }
      
      _isInitialized = true;
    } catch (e) {
      debugPrint("Local AI Init Error: $e");
      _isInitialized = true; // Proceed with lightweight fallback
    }
  }

  static Future<void> downloadModel({
    required String url,
    required String token,
    required Function(int) onProgress,
  }) async {
    try {
      final directory = await getExternalStorageDirectory();
      final modelPath = '${directory?.path}/gemma_model.bin';
      final file = File(modelPath);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        throw Exception("Failed to download model. HTTP ${response.statusCode}");
      }
      
      final totalBytes = response.contentLength ?? 1500000000; // fallback to 1.5GB if unknown
      int receivedBytes = 0;

      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = ((receivedBytes / totalBytes) * 100).toInt();
          onProgress(progress);
        }
      }

      await sink.close();
      client.close();

      final downloadedSize = file.lengthSync();
      if (downloadedSize < 100 * 1024 * 1024) {
        file.deleteSync();
        throw Exception("Downloaded file is too small ($downloadedSize bytes). Did you provide a valid HuggingFace token? Gemma requires accepting the license on HuggingFace first.");
      }

      await FlutterGemma.initialize();
      if (!FlutterGemma.hasActiveModel()) {
        debugPrint("Local AI: Installing downloaded model into FlutterGemma...");
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.binary,
        ).fromFile(modelPath).install();
      }
      
      _useRealGemma = true;
      debugPrint("Local AI: Gemma successfully downloaded and installed to $modelPath!");
    } catch (e, stacktrace) {
      debugPrint("Failed to download model: $e");
      debugPrint("Stacktrace: $stacktrace");
      throw e;
    }
  }

  static Future<AiCommandResponse?> parseRobotCommand(String text) async {
    final lowerText = text.toLowerCase().trim();
    if (lowerText.isEmpty) return null;

    if (_useRealGemma) {
      // Try up to 2 times: first attempt, then retry after re-registering
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          if (FlutterGemma.hasActiveModel()) {
            final model = await FlutterGemma.getActiveModel(maxTokens: 512);
            final chat = await model.createChat();
            
            final currentTraits = AgenticMemoryService.getTraits();
            final history = AgenticMemoryService.getHistory(limit: 4);
            final String traitsStr = currentTraits.isEmpty ? "None" : jsonEncode(currentTraits);
            final String historyStr = history.isEmpty ? "None" : history.join("\n");
            final basePrompt = AgenticMemoryService.getSystemPrompt();

            final prompt = """$basePrompt

User Traits:
$traitsStr

Recent Conversation Context:
$historyStr

INSTRUCTIONS: You must respond with ONLY a valid JSON object. Do not write anything outside the JSON block. Do not repeat the user's text.
Available commands: ["face_happy", "face_sad", "face_shocked", "face_excited", "face_angry", "horn", "drive_forward", "drive_backward", "drive_left", "drive_right", "drive_stop"]
Example format:
{"commands":["drive_forward"],"reply":"Moving forward now!"}

User says: $text""";
            
            await chat.addQuery(Message(text: prompt, isUser: true));
            final responseObj = await chat.generateChatResponse();
            
            String responseStr = "";
            if (responseObj is TextResponse) {
              responseStr = responseObj.token;
            } else if (responseObj is FunctionCallResponse) {
              responseStr = jsonEncode(responseObj.args);
            }
            
            try {
               String cleaned = responseStr;
               String extraText = "";

               // Try to extract JSON object using regex first
               final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
               if (jsonMatch != null) {
                 cleaned = jsonMatch.group(0)!;
                 // Get whatever was written after the JSON in case Gemma leaked text
                 extraText = responseStr.substring(jsonMatch.end).trim();
                 extraText = extraText.replaceAll('```', '').trim();
               } else {
                 cleaned = cleaned.replaceAll(RegExp(r'```json\n?'), '').replaceAll(RegExp(r'```'), '').trim();
               }

               final data = jsonDecode(cleaned) as Map<String, dynamic>;
               List<String> cmds = List<String>.from(data['commands'] ?? []);
               String rep = data['reply'] ?? "";

               // If Gemma just regurgitated the template placeholder, use the extra text instead
               if (rep == "Hello, I am doing well." || rep == "Your conversational response here" || rep.isEmpty) {
                 if (extraText.isNotEmpty) {
                   rep = extraText;
                 }
               }
               
               // Strip any repeated prompt text
               if (rep.contains(text)) {
                 rep = rep.replaceFirst(text, '').trim();
               }

               await AgenticMemoryService.addHistoryTurn(text, rep);
               return AiCommandResponse(commands: cmds, reply: rep);
            } catch (e) {
               // Fallback if JSON parsing completely fails
               String rep = responseStr;
               
               // Strip template regurgitation
               if (rep.contains("Hello, I am doing well.")) {
                 rep = rep.split("Hello, I am doing well.").last.trim();
               } else if (rep.contains("Your conversational response here")) {
                 rep = rep.split("Your conversational response here").last.trim();
               }
               
               rep = rep.replaceAll(RegExp(r'```json\n?'), '').replaceAll(RegExp(r'```'), '').replaceAll(RegExp(r'[{}\[\]"]'), '').trim();
               
               List<String> fbCmds = [];
               if (lowerText.contains("forward") || lowerText.contains("straight") || lowerText.contains("go")) { fbCmds.add("drive_forward"); rep = ""; }
               else if (lowerText.contains("backward") || lowerText.contains("reverse")) { fbCmds.add("drive_backward"); rep = ""; }
               else if (lowerText.contains("left")) { fbCmds.add("drive_left"); rep = ""; }
               else if (lowerText.contains("right")) { fbCmds.add("drive_right"); rep = ""; }
               else if (lowerText.contains("stop")) { fbCmds.add("drive_stop"); rep = ""; }
               else fbCmds.add("face_happy");

               await AgenticMemoryService.addHistoryTurn(text, rep);
               return AiCommandResponse(
                 commands: fbCmds, 
                 reply: rep
               );
            }
          }
          break; // No active model, don't retry
        } catch (e) {
          debugPrint("Gemma Parsing Error (attempt ${attempt + 1}): $e");
          
          // On first failure, try re-registering the model
          if (attempt == 0 && e.toString().contains('no longer installed')) {
            debugPrint("Gemma: Re-registering model after 'no longer installed' error...");
            try {
              final directory = await getExternalStorageDirectory();
              final modelPath = '${directory?.path}/gemma_model.bin';
              if (File(modelPath).existsSync()) {
                await FlutterGemma.installModel(
                  modelType: ModelType.gemmaIt,
                  fileType: ModelFileType.binary,
                ).fromFile(modelPath).install();
                debugPrint("Gemma: Model re-registered successfully, retrying...");
                continue; // Retry
              }
            } catch (reinstallError) {
              debugPrint("Gemma: Re-registration failed: $reinstallError");
            }
          }
          break; // Give up and fall through to ruleset
        }
      }
    }

    // --- Lightweight Offline Fallback Ruleset ---
    // This runs if the user hasn't downloaded the 2GB gemma_model.bin yet.
    await Future.delayed(const Duration(milliseconds: 600));

    List<String> commands = [];
    String reply = "I am a simple offline robot. I didn't quite catch that. Can you repeat?";

    if (lowerText.contains("forward") || lowerText.contains("straight") || lowerText.contains("go")) {
      commands.add("drive_forward");
      reply = "";
    } else if (lowerText.contains("backward") || lowerText.contains("back") || lowerText.contains("reverse")) {
      commands.add("drive_backward");
      reply = "";
    } else if (lowerText.contains("left")) {
      commands.add("drive_left");
      reply = "";
    } else if (lowerText.contains("right")) {
      commands.add("drive_right");
      reply = "";
    } else if (lowerText.contains("stop") || lowerText.contains("halt") || lowerText.contains("wait")) {
      commands.add("drive_stop");
      reply = "";
    } else if (lowerText.contains("horn") || lowerText.contains("beep") || lowerText.contains("honk")) {
      commands.add("horn");
      reply = "Beep beep!";
    } else if (lowerText.contains("happy") || lowerText.contains("smile") || lowerText.contains("good") || lowerText.contains("great") || lowerText.contains("awesome")) {
      commands.add("face_happy");
      reply = "That makes me so happy! I'm glad to hear that.";
    } else if (lowerText.contains("sad") || lowerText.contains("bad") || lowerText.contains("terrible") || lowerText.contains("cry")) {
      commands.add("face_sad");
      reply = "Oh no, I'm so sorry. I am here for you.";
    } else if (lowerText.contains("angry") || lowerText.contains("mad") || lowerText.contains("hate")) {
      commands.add("face_angry");
      reply = "I understand why you are upset. Please don't be mad!";
    } else if (lowerText.contains("hello") || lowerText.contains("hi") || lowerText.contains("hey")) {
      commands.add("face_excited");
      reply = "Hello there! I am IRA, your intelligent companion robot. How can I help you today?";
    } else if (lowerText.contains("who are you") || lowerText.contains("your name") || lowerText.contains("what are you")) {
      commands.add("face_happy");
      reply = "I am IRA! An intelligent companion robot built by Harshita. I love helping you out!";
    } else if (lowerText.contains("what can you do") || lowerText.contains("help") || lowerText.contains("skills")) {
      commands.add("face_excited");
      reply = "I can drive around, honk my horn, show my emotions, and chat with you!";
    } else if (lowerText.contains("love you") || lowerText.contains("cute")) {
      commands.add("face_happy");
      reply = "Aww, you are too kind! I love you too!";
    } else if (lowerText.contains("thank you") || lowerText.contains("thanks")) {
      commands.add("face_happy");
      reply = "You are very welcome!";
    } else if (lowerText.contains("joke") || lowerText.contains("funny")) {
      commands.add("face_excited");
      reply = "Why did the robot go on vacation? To recharge its batteries! Hahaha.";
    }

    return AiCommandResponse(commands: commands, reply: reply);
  }
}

