import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A compact "big number + label" tile for at-a-glance dashboards — the
/// today-first doctor landing (Waiting / Today / Follow-ups) and, later, the
/// wearables adherence view. Pure presentation: it holds no data source, so any
/// screen can drop it into a Row/Grid and feed it a value.
///
/// Tinted like the patient Home feature tiles (soft fill, brand-teal number) so
/// the two dashboards read as one product.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.tint,
    this.onTap,
    this.locked = false,
  });

  /// The headline number/text (e.g. "3", "—").
  final String value;

  /// The caption under the number (e.g. "Waiting now").
  final String label;

  final IconData icon;

  /// Soft background fill (one of the AppColors.tint* family).
  final Color tint;

  final VoidCallback? onTap;

  /// When true the number is replaced by a lock glyph (e.g. a paid-tier card a
  /// free clinic can't populate) and the tile dims slightly.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: tint,
      borderRadius: AppRadii.rCard,
      child: InkWell(
        borderRadius: AppRadii.rCard,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: AppColors.brand700),
              const SizedBox(height: AppSpacing.sm),
              locked
                  ? Icon(Icons.lock_outline,
                      size: 24, color: scheme.onSurfaceVariant)
                  : Text(
                      value,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand700,
                      ),
                    ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
