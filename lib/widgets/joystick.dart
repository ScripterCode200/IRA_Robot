import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VirtualJoystick extends StatefulWidget {
  final String label;
  final ValueChanged<Offset>? onChanged;
  final VoidCallback? onReleased;
  final Color activeColor;

  const VirtualJoystick({
    super.key,
    required this.label,
    this.onChanged,
    this.onReleased,
    this.activeColor = const Color(0xFF00F2FE),
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> with SingleTickerProviderStateMixin {
  late AnimationController _springController;
  late Animation<Offset> _springAnimation;
  
  Offset _dragPosition = Offset.zero;
  final double _baseRadius = 75.0;
  final double _stickRadius = 28.0;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _springAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic));

    _springController.addListener(() {
      setState(() {
        _dragPosition = _springAnimation.value;
      });
      _notifyOffset();
    });
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _notifyOffset() {
    if (widget.onChanged != null) {
      // Normalize values to range -1.0 to 1.0
      double maxDrag = _baseRadius - _stickRadius;
      double dx = _dragPosition.dx / maxDrag;
      double dy = _dragPosition.dy / maxDrag;
      widget.onChanged!(Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0)));
    }
  }

  void _updatePosition(Offset globalPosition) {
    RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    // Position relative to the center of the joystick
    Offset localPos = renderBox.globalToLocal(globalPosition);
    Offset center = Offset(renderBox.size.width / 2, renderBox.size.height / 2);
    Offset offset = localPos - center;

    double maxDrag = _baseRadius - _stickRadius;
    double dragDistance = offset.distance;

    // Constrain within the outer bounds
    if (dragDistance > maxDrag) {
      offset = Offset.fromDirection(offset.direction, maxDrag);
    }

    // Dynamic tactile micro-clicks on movements
    double prevDistance = _dragPosition.distance;
    if ((offset.distance - prevDistance).abs() > maxDrag / 5) {
      HapticFeedback.lightImpact();
    }

    setState(() {
      _dragPosition = offset;
    });
    _notifyOffset();
  }

  void _onDragEnd() {
    // Smooth return to center (spring physics effect)
    _springAnimation = Tween<Offset>(
      begin: _dragPosition,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _springController, curve: Curves.easeOutBack));

    _springController.reset();
    _springController.forward();
    
    HapticFeedback.mediumImpact();
    if (widget.onReleased != null) {
      widget.onReleased!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double widgetSize = _baseRadius * 2 + 10;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Using Listener instead of GestureDetector to capture pointer events
        // at the lowest level, completely bypassing the Flutter gesture arena.
        // This prevents the parent SingleChildScrollView from stealing vertical drags.
        Listener(
          onPointerDown: (event) {
            HapticFeedback.mediumImpact();
            _updatePosition(event.position);
          },
          onPointerMove: (event) => _updatePosition(event.position),
          onPointerUp: (event) => _onDragEnd(),
          child: Container(
            width: widgetSize,
            height: widgetSize,
            alignment: Alignment.center,
            child: CustomPaint(
              size: Size(_baseRadius * 2, _baseRadius * 2),
              painter: _JoystickPainter(
                dragPosition: _dragPosition,
                baseRadius: _baseRadius,
                stickRadius: _stickRadius,
                activeColor: widget.activeColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            color: Colors.blueGrey.shade400,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset dragPosition;
  final double baseRadius;
  final double stickRadius;
  final Color activeColor;

  _JoystickPainter({
    required this.dragPosition,
    required this.baseRadius,
    required this.stickRadius,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxDrag = baseRadius - stickRadius;

    // Draw grid coordinate lines (technical details)
    final Paint linePaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    canvas.drawLine(Offset(center.dx - baseRadius, center.dy), Offset(center.dx + baseRadius, center.dy), linePaint);
    canvas.drawLine(Offset(center.dx, center.dy - baseRadius), Offset(center.dx, center.dy + baseRadius), linePaint);

    // Draw outer boundary circles
    final Paint outerBorderPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final Paint outerGlowPaint = Paint()
      ..color = activeColor.withOpacity(0.05)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, baseRadius, outerGlowPaint);
    canvas.drawCircle(center, baseRadius, outerBorderPaint);
    
    // Draw guide lines matching the active offset direction
    if (dragPosition != Offset.zero) {
      final Paint activeLinePaint = Paint()
        ..color = activeColor.withOpacity(0.2)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(center, center + dragPosition, activeLinePaint);
      
      // Draw outer target ticks
      final double angle = dragPosition.direction;
      final Offset outerIntersection = center + Offset.fromDirection(angle, baseRadius);
      final Paint tickPaint = Paint()
        ..color = activeColor
        ..strokeWidth = 3.0
        ..style = PaintingStyle.fill;
      canvas.drawCircle(outerIntersection, 3.0, tickPaint);
    }

    // Inner joystick pad shadow
    final Path padShadowPath = Path()
      ..addOval(Rect.fromCircle(center: center + dragPosition, radius: stickRadius));
    canvas.drawShadow(padShadowPath, Colors.black, 8.0, true);

    // Draw joystick handle (stick knob)
    final double dragIntensity = dragPosition.distance / maxDrag;
    final Color knobColor = Color.lerp(
      Colors.blueGrey.shade800,
      activeColor,
      dragIntensity.clamp(0.0, 1.0),
    )!;

    final Paint knobPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          knobColor.withOpacity(0.9),
          knobColor.withOpacity(0.6),
          const Color(0xFF1E293B),
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center + dragPosition, radius: stickRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center + dragPosition, stickRadius, knobPaint);

    // Outer ring on the joystick knob itself
    final Paint knobRingPaint = Paint()
      ..color = Color.lerp(Colors.white30, activeColor, dragIntensity)!
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center + dragPosition, stickRadius - 1, knobRingPaint);
    
    // Glowing central dot
    final Paint dotPaint = Paint()
      ..color = dragPosition == Offset.zero ? Colors.white70 : activeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center + dragPosition, 4.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.dragPosition != dragPosition ||
        oldDelegate.baseRadius != baseRadius ||
        oldDelegate.stickRadius != stickRadius ||
        oldDelegate.activeColor != activeColor;
  }
}
