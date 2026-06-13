import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class ImageEnhancerService {
  static Interpreter? _interpreter;
  static bool _isLoaded = false;

  /// Initialize the TFLite model from the assets directory.
  /// Ensure the model file is added to pubspec.yaml assets.
  static Future<void> initModel(String modelAssetPath) async {
    try {
      _interpreter = await Interpreter.fromAsset(modelAssetPath);
      _isLoaded = true;
      debugPrint("AI Enhancement Model loaded successfully.");
    } catch (e) {
      debugPrint("Failed to load AI enhancement model: $e");
    }
  }

  static bool get isReady => _isLoaded;

  /// Enhances a JPEG image using the loaded TFLite model.
  /// If the model fails or is not loaded, it returns the original bytes.
  static Future<Uint8List> enhanceImage(Uint8List jpegBytes) async {
    if (!_isLoaded || _interpreter == null) return jpegBytes;

    try {
      // 1. Decode the original JPEG
      final image = img.decodeImage(jpegBytes);
      if (image == null) return jpegBytes;

      // Note: TFLite models usually require a fixed input shape. 
      // You must check your specific model's requirements (e.g. 50x50 or 256x256).
      // Here we assume the model is flexible or we are passing the native size.
      var inputShape = _interpreter!.getInputTensor(0).shape;
      var outputShape = _interpreter!.getOutputTensor(0).shape;

      int w = image.width;
      int h = image.height;

      // 2. Prepare the Input Tensor [1, height, width, 3] Float32
      var input = List.generate(1, (i) => List.generate(h, (y) => List.generate(w, (x) {
        final pixel = image.getPixelSafe(x, y);
        return [
          pixel.r.toDouble() / 255.0,
          pixel.g.toDouble() / 255.0,
          pixel.b.toDouble() / 255.0
        ];
      })));

      // 3. Prepare the Output Tensor 
      // If it's a Super Resolution model, the output shape is larger (e.g., 2x).
      // If dynamic, we default to the same size or a multiplier.
      int outH = outputShape.length > 1 && outputShape[1] > 0 ? outputShape[1] : h;
      int outW = outputShape.length > 2 && outputShape[2] > 0 ? outputShape[2] : w;
      var output = List.generate(1, (i) => List.generate(outH, (y) => List.generate(outW, (x) => List.filled(3, 0.0))));

      // 4. Run Inference
      _interpreter!.run(input, output);

      // 5. Reconstruct the enhanced Image from the output tensor
      final enhancedImg = img.Image(width: outW, height: outH);
      for (int y = 0; y < outH; y++) {
        for (int x = 0; x < outW; x++) {
          final r = (output[0][y][x][0] * 255).clamp(0, 255).toInt();
          final g = (output[0][y][x][1] * 255).clamp(0, 255).toInt();
          final b = (output[0][y][x][2] * 255).clamp(0, 255).toInt();
          enhancedImg.setPixelRgb(x, y, r, g, b);
        }
      }

      // 6. Encode back to a high-quality JPEG
      return Uint8List.fromList(img.encodeJpg(enhancedImg, quality: 100));
      
    } catch (e) {
      debugPrint("Error enhancing image: $e");
      return jpegBytes; // Fallback to original image on failure
    }
  }
}
