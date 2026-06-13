import 'dart:convert';
import 'dart:typed_data';

class CustomFace {
  final String id;
  final String name;
  final List<List<bool>> grid; // 64 rows of 128 booleans
  final String? htmlCode; // For AI-generated JS Canvas animations

  CustomFace({
    required this.id,
    required this.name,
    required this.grid,
    this.htmlCode,
  });

  // Factory to create a blank 128x64 grid
  factory CustomFace.blank(String name) {
    return CustomFace(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      grid: List.generate(64, (_) => List.generate(128, (_) => false)),
    );
  }

  // Clone to create copies
  CustomFace clone() {
    return CustomFace(
      id: id,
      name: name,
      grid: grid.map((row) => List<bool>.from(row)).toList(),
      htmlCode: htmlCode,
    );
  }

  // Convert grid to compact base64 string for efficient storage
  String encodeGrid() {
    // 128 * 64 = 8192 bits = 1024 bytes
    final bytes = Uint8List(1024);
    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 128; x++) {
        if (grid[y][x]) {
          int bitIndex = (y * 128) + x;
          int byteIndex = bitIndex ~/ 8;
          int bitOffset = bitIndex % 8;
          bytes[byteIndex] |= (1 << bitOffset);
        }
      }
    }
    return base64Encode(bytes);
  }

  // Decode base64 string back into 128x64 boolean grid
  static List<List<bool>> decodeGrid(String encoded) {
    final grid = List.generate(64, (_) => List.generate(128, (_) => false));
    try {
      final bytes = base64Decode(encoded);
      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 128; x++) {
          int bitIndex = (y * 128) + x;
          int byteIndex = bitIndex ~/ 8;
          int bitOffset = bitIndex % 8;
          grid[y][x] = (bytes[byteIndex] & (1 << bitOffset)) != 0;
        }
      }
    } catch (e) {
      // If error, return blank grid
    }
    return grid;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'gridData': encodeGrid(),
      'htmlCode': htmlCode,
    };
  }

  factory CustomFace.fromJson(Map<String, dynamic> json) {
    return CustomFace(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? 'Unnamed',
      grid: decodeGrid(json['gridData'] ?? ''),
      htmlCode: json['htmlCode'],
    );
  }
}
