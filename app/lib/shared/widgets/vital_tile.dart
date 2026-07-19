import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// One measured value (lab result, vital) rendered with the app-wide medical
/// type hierarchy: LABEL small+muted, VALUE big/bold/tabular, unit medium.
/// [flagged] marks an out-of-range value — colour PLUS an icon, never colour
/// alone (UI brief §5).
class VitalTile extends StatelessWidget {
  const VitalTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.reference,
    this.flagged = false,
  });

  final String label;
  final String value;
  final String? unit;

  /// e.g. "4.0–5.6" — shown muted under the value when present.
  final String? reference;
  final bool flagged;

  @override
  Widget build(BuildContext context) {
    final v = AppVitalStyles.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: flagged ? Border.all(color: scheme.error, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: v.label),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(value,
                    style: flagged
                        ? v.value.copyWith(color: scheme.error)
                        : v.value),
              ),
              if (unit != null && unit!.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit!, style: v.unit),
              ],
              if (flagged) ...[
                const SizedBox(width: 6),
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: scheme.error),
              ],
            ],
          ),
          if (reference != null && reference!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('Ref $reference', style: v.unit.copyWith(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
