import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:path_provider/path_provider.dart';

class AIVisionService {
  static final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  
  // Custom image labeler (RPS) will require the user to provide a tflite model.
  static ImageLabeler? _rpsLabeler;

  // Waving logic state
  static final List<double> _wristXHistory = [];
  static int _lastWaveTime = 0;

  static Future<void> initRpsModel(String modelPath) async {
    try {
      final options = LocalLabelerOptions(modelPath: modelPath);
      _rpsLabeler = ImageLabeler(options: options);
      debugPrint("RPS Model initialized successfully.");
    } catch (e) {
      debugPrint("Failed to init RPS model: $e");
    }
  }

  /// Processes a single JPEG frame and returns a detected action command if any
  static Future<String?> processFrame(Uint8List jpegBytes) async {
    try {
      // ML Kit requires NV21 byte format or file path. For raw JPEGs from MJPEG stream, 
      // writing to a fast temp file is the most reliable way to feed ML Kit.
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/ai_frame.jpg');
      await tempFile.writeAsBytes(jpegBytes);
      
      final inputImage = InputImage.fromFilePath(tempFile.path);
      
      // 1. Pose Detection (Waving)
      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isNotEmpty) {
        final pose = poses.first;
        // Check either right or left wrist
        final wrist = pose.landmarks[PoseLandmarkType.rightWrist] ?? pose.landmarks[PoseLandmarkType.leftWrist];
        final elbow = pose.landmarks[PoseLandmarkType.rightElbow] ?? pose.landmarks[PoseLandmarkType.leftElbow];
        final shoulder = pose.landmarks[PoseLandmarkType.rightShoulder] ?? pose.landmarks[PoseLandmarkType.leftShoulder];

        if (wrist != null && elbow != null && shoulder != null) {
          // Check if hand is raised (wrist Y is physically higher than elbow Y)
          // ML Kit coordinates: Y=0 is top, so higher means smaller Y.
          if (wrist.y < elbow.y) {
            _wristXHistory.add(wrist.x);
            if (_wristXHistory.length > 5) _wristXHistory.removeAt(0);

            if (_wristXHistory.length >= 5) {
              // Calculate horizontal oscillation (variance/direction changes)
              int directionChanges = 0;
              for (int i = 1; i < _wristXHistory.length - 1; i++) {
                if ((_wristXHistory[i] > _wristXHistory[i - 1] && _wristXHistory[i] > _wristXHistory[i + 1]) ||
                    (_wristXHistory[i] < _wristXHistory[i - 1] && _wristXHistory[i] < _wristXHistory[i + 1])) {
                  directionChanges++;
                }
              }

              if (directionChanges >= 2) {
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - _lastWaveTime > 3000) { // Cooldown 3s
                  _lastWaveTime = now;
                  _wristXHistory.clear();
                  return 'action_wave';
                }
              }
            }
          } else {
            _wristXHistory.clear();
          }
        }
      }

      // 2. Image Labeling (RPS)
      if (_rpsLabeler != null) {
        final labels = await _rpsLabeler!.processImage(inputImage);
        for (final label in labels) {
          if (label.confidence > 0.7) {
            if (label.label.toLowerCase().contains('rock')) return 'action_rock';
            if (label.label.toLowerCase().contains('paper')) return 'action_paper';
            if (label.label.toLowerCase().contains('scissors')) return 'action_scissors';
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint("AI Vision Error: $e");
      return null;
    }
  }
}
