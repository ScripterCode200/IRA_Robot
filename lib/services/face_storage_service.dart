import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_face_model.dart';

class FaceStorageService {
  static const String _storageKey = 'saved_custom_faces';

  static Future<List<CustomFace>> loadSavedFaces() async {
    final prefs = await SharedPreferences.getInstance();
    final String? facesJson = prefs.getString(_storageKey);
    
    if (facesJson == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(facesJson);
      return decoded.map((e) => CustomFace.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveFace(CustomFace face) async {
    final faces = await loadSavedFaces();
    
    // Replace if exists, otherwise add
    final index = faces.indexWhere((f) => f.id == face.id);
    if (index >= 0) {
      faces[index] = face;
    } else {
      faces.add(face);
    }

    await _saveAll(faces);
  }

  static Future<void> deleteFace(String id) async {
    final faces = await loadSavedFaces();
    faces.removeWhere((f) => f.id == id);
    await _saveAll(faces);
  }

  static Future<void> _saveAll(List<CustomFace> faces) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(faces.map((f) => f.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}
