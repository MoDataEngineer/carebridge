import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Generated Ayulekha logo mark — a rounded-square teal gradient tile with a
/// white cross whose heart-pulse line runs through it. Painted (vector), so it
/// stays crisp at any size and needs no binary asset.
class AyulekhaLogo extends StatelessWidget {
  const AyulekhaLogo({super.key, this.size = 64, this.withWordmark = false});

  final double size;
  final bool withWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand400, AppColors.brand700],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand600.withValues(alpha: 0.35),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: CustomPaint(painter: _CrossPulsePainter()),
    );
    if (!withWordmark) return mark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(height: size * 0.25),
        Text(
          'Ayulekha',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
      ],
    );
  }
}

class _CrossPulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cross = Paint()..color = Colors.white;

    // Rounded medical cross.
    final arm = w * 0.20;
    final len = w * 0.58;
    final r = Radius.circular(arm * 0.35);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w / 2, h / 2), width: len, height: arm),
        r,
      ),
      cross,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w / 2, h / 2), width: arm, height: len),
        r,
      ),
      cross,
    );

    // Heart-pulse line across the horizontal arm.
    final pulse = Paint()
      ..color = AppColors.brand700
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final midY = h / 2;
    final path = Path()
      ..moveTo(w * 0.28, midY)
      ..lineTo(w * 0.42, midY)
      ..lineTo(w * 0.47, midY - h * 0.12)
      ..lineTo(w * 0.54, midY + h * 0.12)
      ..lineTo(w * 0.58, midY)
      ..lineTo(w * 0.72, midY);
    canvas.drawPath(path, pulse);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
