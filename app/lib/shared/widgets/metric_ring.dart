import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A Strava-style progress ring — a value against a goal, with the value in the
/// centre and a caption below. Purely presentational (the patient's own daily
/// activity view); it displays raw numbers only and never interprets them
/// (non-diagnostic, epic §6).
class MetricRing extends StatelessWidget {
  const MetricRing({
    super.key,
    required this.value,
    required this.goal,
    required this.label,
    required this.color,
    this.centerText,
    this.size = 96,
  });

  /// Current value (e.g. 6400 steps).
  final double value;

  /// Target for a full ring (e.g. 10000). Values above goal cap the sweep.
  final double goal;

  /// Caption under the ring (e.g. "steps").
  final String label;

  final Color color;

  /// Big number in the centre; defaults to a compact form of [value].
  final String? centerText;

  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pct = goal <= 0 ? 0.0 : (value / goal).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              pct: pct,
              color: color,
              track: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            child: Center(
              child: Text(
                centerText ?? _compact(value),
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  static String _compact(double v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
    }
    return v.toStringAsFixed(0);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.pct, required this.color, required this.track});

  final double pct;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    if (pct > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * pct, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.pct != pct || old.color != color || old.track != track;
}
