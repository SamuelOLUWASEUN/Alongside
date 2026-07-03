import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A minimal expressive face for a mood score (1-10): two dot eyes and a
/// single curved mouth that smoothly flips from frown to smile. Deliberately
/// built from the same "curved line" language as the app's arc logo rather
/// than generic emoji, which render inconsistently across platforms and
/// would clash with the app's calmer visual tone.
class MoodFace extends StatelessWidget {
  final double score; // 1-10
  final double size;

  const MoodFace({super.key, required this.score, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MoodFacePainter(score: score),
    );
  }
}

class _MoodFacePainter extends CustomPainter {
  final double score;
  _MoodFacePainter({required this.score});

  Color _color() {
    if (score <= 3) return AppColors.alert;
    if (score <= 6) return AppColors.ember;
    return AppColors.tide;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final color = _color();
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.06;
    final radius = size.width / 2 - strokeWidth;

    // Soft tinted background circle, matching the tinted-chip style used
    // elsewhere in the app (e.g. the crisis overlay icon).
    canvas.drawCircle(center, radius, Paint()..color = color.withOpacity(0.12));

    // Eyes
    final eyePaint = Paint()..color = color;
    final eyeRadius = size.width * 0.038;
    final eyeY = center.dy - radius * 0.28;
    canvas.drawCircle(
        Offset(center.dx - radius * 0.36, eyeY), eyeRadius, eyePaint);
    canvas.drawCircle(
        Offset(center.dx + radius * 0.36, eyeY), eyeRadius, eyePaint);

    // Mouth: a single quadratic-bezier arc whose curvature flips from a
    // frown (score low) through a neutral flat line (score ~5-6) to a
    // smile (score high) - same "open arc" shape language as the logo.
    final t = ((score - 5.5) / 4.5).clamp(-1.0, 1.0);
    final mouthY = center.dy + radius * 0.3;
    final mouthHalfWidth = radius * 0.42;
    final controlOffsetY = t * radius * 0.6;

    final path = Path()
      ..moveTo(center.dx - mouthHalfWidth, mouthY)
      ..quadraticBezierTo(center.dx, mouthY + controlOffsetY,
          center.dx + mouthHalfWidth, mouthY);

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MoodFacePainter oldDelegate) =>
      oldDelegate.score != score;
}
