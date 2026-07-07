import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A pill for a test_status value, pairing colour with an icon AND a text label
/// so status is never conveyed by colour alone (UI brief §5). Shared by the
/// patient/doctor Tests view and the diagnostic partner queue.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = AppStatusColors.of(context);
    final (String label, IconData icon, Color color) = switch (status) {
      'ordered' => ('Ordered', Icons.receipt_long, scheme.onSurfaceVariant),
      'sample_collected' => ('Sample collected', Icons.colorize, s.info),
      'in_progress' => ('In progress', Icons.hourglass_bottom, s.warning),
      'report_ready' => ('Report ready', Icons.check_circle, s.success),
      'cancelled' => ('Cancelled', Icons.cancel, scheme.error),
      _ => (status, Icons.help_outline, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
