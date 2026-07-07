import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A frosted-glass panel (UI brief §2/§6). Use ONLY on overlays/modals where
/// there is content behind it to frost — e.g. the "Share your record" consent
/// overlay and onboarding sheets. NEVER wrap lab values, prescriptions, or the
/// history feed in this: translucency lowers text contrast on exactly the
/// content that must never be misread.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 18,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.borderRadius = AppRadii.rXl,
  });

  final Widget child;
  final double blur;
  final EdgeInsets padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: isDark ? 0.55 : 0.7),
            borderRadius: borderRadius,
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: isDark ? 0.14 : 0.10),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
