import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Large tappable role card on the entry screen (Section 2). Reskin 2026-07-19:
/// soft-tinted card (reference #1 pastel cards) with an icon disc, title +
/// caption, and a chevron — instead of a flat filled button. Tap target far
/// exceeds 44px; text keeps AA contrast on the tints.
class RoleButton extends StatelessWidget {
  const RoleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.caption,
    this.tint,
    this.tintDark,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? caption;
  final Color? tint;
  final Color? tintDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final fill = isDark
        ? (tintDark ?? AppColors.tintMintDark)
        : (tint ?? AppColors.tintMint);
    return Material(
      color: fill,
      borderRadius: AppRadii.rCard,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.rCard,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.25)
                      : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 26, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontSize: 18)),
                    if (caption != null) ...[
                      const SizedBox(height: 2),
                      Text(caption!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
