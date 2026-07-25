import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A "connect your tracker" row — a source (Apple Health / Health Connect /
/// manual entry) with a Connect / Connected affordance. Presentational; the
/// actual OS-permission request is driven by the caller's [onConnect].
class ConnectTrackerTile extends StatelessWidget {
  const ConnectTrackerTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.connected,
    required this.onConnect,
    this.tint,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool connected;
  final VoidCallback onConnect;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadii.rCard,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: tint ?? AppColors.tintMint,
            child: Icon(icon, size: 20, color: AppColors.brand700),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          connected
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 18, color: AppColors.brand600),
                    const SizedBox(width: 4),
                    Text('Connected',
                        style: text.labelMedium?.copyWith(
                            color: AppColors.brand700, fontWeight: FontWeight.w600)),
                  ],
                )
              : OutlinedButton(
                  onPressed: onConnect,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(44, 40)),
                  child: const Text('Connect'),
                ),
        ],
      ),
    );
  }
}
