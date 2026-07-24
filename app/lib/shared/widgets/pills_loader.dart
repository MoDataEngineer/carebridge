import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Branded loading indicator (prototype 1e): six two-tone capsules orbiting a
/// centre, one per brand tint, with a comet-trail fade. Replaces the plain
/// [CircularProgressIndicator] on brand surfaces. Purely decorative — no
/// semantics beyond "busy".
class PillsLoader extends StatefulWidget {
  const PillsLoader({super.key, this.size = 44});

  final double size;

  @override
  State<PillsLoader> createState() => _PillsLoaderState();
}

class _PillsLoaderState extends State<PillsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _PillsPainter(_c.value)),
        ),
      ),
    );
  }
}

class _PillsPainter extends CustomPainter {
  _PillsPainter(this.t);

  final double t; // 0..1 rotation phase

  static const _colors = [
    AppColors.pillTeal,
    AppColors.pillPeach,
    AppColors.pillLavender,
    AppColors.pillSky,
    AppColors.pillGreen,
    AppColors.pillRose,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orbit = size.width * 0.30;
    final capLen = size.width * 0.30;
    final capW = size.width * 0.13;
    final seam = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = math.max(1, capW * 0.12);

    for (var i = 0; i < 6; i++) {
      final frac = i / 6;
      final angle = (frac + t) * 2 * math.pi;
      // Comet trail: the capsule at the leading edge is brightest.
      final trail = ((frac - t) % 1 + 1) % 1;
      final opacity = 0.30 + 0.70 * trail;

      final pos = Offset(
        center.dx + orbit * math.cos(angle),
        center.dy + orbit * math.sin(angle),
      );

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle + math.pi / 2); // tangential

      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: capW, height: capLen),
        Radius.circular(capW / 2),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = _colors[i].withValues(alpha: opacity),
      );
      // Pill seam across the middle.
      canvas.drawLine(
        Offset(-capW / 2, 0),
        Offset(capW / 2, 0),
        seam..color = Colors.white.withValues(alpha: 0.85 * opacity),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PillsPainter old) => old.t != t;
}
