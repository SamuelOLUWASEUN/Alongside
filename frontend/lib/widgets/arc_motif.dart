import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A soft, open gradient arc - the recurring shape tied to the name
/// "Alongside": a horizon, a held breath, something open rather than closed.
/// Used as the onboarding hero and reused as the chat "thinking" indicator,
/// so it reads as a deliberate brand mark rather than one-off decoration.
class ArcMotif extends StatelessWidget {
  final double size;
  final double strokeWidth;

  const ArcMotif({super.key, this.size = 160, this.strokeWidth = 10});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ArcPainter(strokeWidth: strokeWidth)),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double strokeWidth;
  _ArcPainter({required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [AppColors.tide, AppColors.ember, AppColors.tide],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    // A wide arc, open at the bottom - like a horizon held open rather than
    // a closed ring.
    canvas.drawArc(rect, -2.4, 4.5, false, paint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      oldDelegate.strokeWidth != strokeWidth;
}

/// A small animated version of [ArcMotif] used as a "thinking"/loading
/// indicator - the same brand shape, gently rotating, instead of a generic
/// spinner.
class BreathingArc extends StatefulWidget {
  final double size;
  const BreathingArc({super.key, this.size = 28});

  @override
  State<BreathingArc> createState() => _BreathingArcState();
}

class _BreathingArcState extends State<BreathingArc> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: ArcMotif(size: widget.size, strokeWidth: widget.size / 8),
    );
  }
}
