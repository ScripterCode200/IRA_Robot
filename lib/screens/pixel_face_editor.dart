import 'package:flutter/material.dart';
import '../models/custom_face_model.dart';
import '../services/face_storage_service.dart';

class PixelFaceEditor extends StatefulWidget {
  final CustomFace? initialFace;

  const PixelFaceEditor({super.key, this.initialFace});

  @override
  State<PixelFaceEditor> createState() => _PixelFaceEditorState();
}

class _PixelFaceEditorState extends State<PixelFaceEditor> {
  late List<List<bool>> _grid;
  bool _isErasing = false;
  
  // A drag-and-drop component library (mini sprites)
  // represented as list of string rows for easy defining
  final Map<String, List<String>> _components = {
    'Happy Eye': [
      '  ####  ',
      ' ##  ## ',
      '##    ##',
      '##    ##',
      '##    ##',
    ],
    'Sad Eye': [
      '##    ##',
      '##    ##',
      '##    ##',
      ' ##  ## ',
      '  ####  ',
    ],
    'Open Mouth': [
      ' ###### ',
      '##    ##',
      '##    ##',
      ' ###### ',
    ],
    'Smile Mouth': [
      '##      ##',
      ' ##    ## ',
      '  ######  ',
    ],
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialFace != null) {
      _grid = widget.initialFace!.clone().grid;
    } else {
      _grid = List.generate(64, (_) => List.generate(128, (_) => false));
    }
  }

  void _clearGrid() {
    setState(() {
      _grid = List.generate(64, (_) => List.generate(128, (_) => false));
    });
  }

  void _saveFace() {
    final TextEditingController nameController = TextEditingController(text: widget.initialFace?.name ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Save Custom Face', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter face name...',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final newFace = CustomFace(
                  id: widget.initialFace?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  grid: _grid,
                );
                await FaceStorageService.saveFace(newFace);
                if (mounted) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context, newFace); // Return to previous screen
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _handlePan(Offset localPosition, Size size) {
    // Mapping interaction point to 128x64 grid
    final double pixelWidth = size.width / 128.0;
    final double pixelHeight = size.height / 64.0;
    
    int x = (localPosition.dx / pixelWidth).floor();
    int y = (localPosition.dy / pixelHeight).floor();

    if (x >= 0 && x < 128 && y >= 0 && y < 64) {
      setState(() {
        _grid[y][x] = !_isErasing;
        
        // Make the brush slightly thicker (2x2 pixels) for easier drawing on mobile
        if (x + 1 < 128) _grid[y][x + 1] = !_isErasing;
        if (y + 1 < 64) _grid[y + 1][x] = !_isErasing;
        if (x + 1 < 128 && y + 1 < 64) _grid[y + 1][x + 1] = !_isErasing;
      });
    }
  }

  void _stampComponent(String componentName, int startX, int startY) {
    final sprite = _components[componentName]!;
    setState(() {
      for (int y = 0; y < sprite.length; y++) {
        for (int x = 0; x < sprite[y].length; x++) {
          int gridX = startX + x;
          int gridY = startY + y;
          if (gridX >= 0 && gridX < 128 && gridY >= 0 && gridY < 64) {
            if (sprite[y][x] == '#') {
              _grid[gridY][gridX] = true;
            }
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('128x64 Pixel Matrix Editor', style: TextStyle(fontSize: 14, fontFamily: 'monospace')),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _clearGrid,
            tooltip: 'Clear Board',
          ),
          IconButton(
            icon: const Icon(Icons.save, color: Color(0xFF00F2FE)),
            onPressed: _saveFace,
            tooltip: 'Save Face',
          ),
        ],
      ),
      body: Column(
        children: [
          // 128x64 Canvas (2:1 aspect ratio)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: AspectRatio(
              aspectRatio: 2.0, // 128 / 64
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F19),
                  border: Border.all(color: const Color(0xFF00F2FE).withOpacity(0.3), width: 2),
                ),
                child: Builder(
                  builder: (canvasContext) {
                    return GestureDetector(
                      onPanStart: (details) => _handlePan(details.localPosition, canvasContext.size!),
                      onPanUpdate: (details) => _handlePan(details.localPosition, canvasContext.size!),
                      child: DragTarget<String>(
                        onAcceptWithDetails: (details) {
                          final RenderBox renderBox = canvasContext.findRenderObject() as RenderBox;
                          // Offset is top-left. Let's adjust slightly so it centers near the finger.
                          final centerOffset = Offset(details.offset.dx + 40, details.offset.dy + 40);
                          final localOffset = renderBox.globalToLocal(centerOffset);
                          
                          final double pixelWidth = renderBox.size.width / 128.0;
                          final double pixelHeight = renderBox.size.height / 64.0;
                          
                          int gridX = (localOffset.dx / pixelWidth).floor();
                          int gridY = (localOffset.dy / pixelHeight).floor();
                          
                          _stampComponent(details.data, gridX, gridY);
                        },
                        builder: (context, _, __) {
                          return CustomPaint(
                            size: Size.infinite,
                            painter: _GridPainter(_grid),
                          );
                        },
                      ),
                    );
                  }
                ),
              ),
            ),
          ),
          
          // Toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildToolBtn('Draw', Icons.edit, !_isErasing, () => setState(() => _isErasing = false)),
                const SizedBox(width: 16),
                _buildToolBtn('Erase', Icons.cleaning_services, _isErasing, () => setState(() => _isErasing = true)),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          const Text("DRAG & DROP SPRITES", style: TextStyle(color: Colors.blueGrey, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 12),
          
          // Draggable Components
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _components.keys.map((name) {
                return Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Draggable<String>(
                    data: name,
                    feedback: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFF00F2FE).withOpacity(0.2), border: Border.all(color: const Color(0xFF00F2FE))),
                        child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(name.contains('Eye') ? Icons.visibility : Icons.mood, color: Colors.blueGrey, size: 24),
                          const SizedBox(height: 8),
                          Text(name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolBtn(String label, IconData icon, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00F2FE).withOpacity(0.2) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? const Color(0xFF00F2FE) : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? const Color(0xFF00F2FE) : Colors.white54, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isActive ? const Color(0xFF00F2FE) : Colors.white54, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final List<List<bool>> grid;
  _GridPainter(this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    final double pixelWidth = size.width / 128.0;
    final double pixelHeight = size.height / 64.0;
    
    final paint = Paint()
      ..color = const Color(0xFF00F2FE)
      ..style = PaintingStyle.fill;

    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 128; x++) {
        if (grid[y][x]) {
          canvas.drawRect(
            Rect.fromLTWH(x * pixelWidth, y * pixelHeight, pixelWidth, pixelHeight),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => true;
}
