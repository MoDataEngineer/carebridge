import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../features/vitals/vitals_models.dart';

/// A small 7-bar week chart of raw daily totals. Bars scale to the week's max;
/// purely a visual of the numbers — no average line, target, or interpretation
/// (non-diagnostic, epic §6). Shared by the patient's own view and the doctor
/// trend view.
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.points, this.height = 120});

  final List<MetricPoint> points;
  final double height;

  static const _dow = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  static String _compact(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = points.map((p) => p.value).fold<double>(1, (a, b) => b > a ? b : a);
    final barMax = height - 46;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in points)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(_compact(p.value),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: (p.value / max) * barMax,
                    decoration: BoxDecoration(
                      color: AppColors.brand400,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_dow[p.date.weekday - 1],
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
