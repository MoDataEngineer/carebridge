import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Shared app theme (single codebase, all roles + platforms). Light and dark
/// are built from ONE component-styling function so they stay in lock-step;
/// only the [ColorScheme] differs. All values come from design_tokens.dart.
class AppTheme {
  const AppTheme._();

  static ThemeData get light =>
      _build(ColorScheme.fromSeed(seedColor: AppColors.seed));

  static ThemeData get dark => _build(ColorScheme.fromSeed(
        seedColor: AppColors.seed,
        brightness: Brightness.dark,
      ));

  static ThemeData _build(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    // Body text a notch larger than consumer defaults — patients span a wide
    // age range (UI brief §2 typography). Respects text-scaling on top of this.
    final t = base.textTheme;
    final textTheme = t.copyWith(
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 17, height: 1.4),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, height: 1.35),
      titleMedium: t.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: t.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    );

    final status = isDark
        ? const AppStatusColors(
            success: AppColors.successDark,
            warning: AppColors.warningDark,
            info: AppColors.infoDark,
          )
        : const AppStatusColors(
            success: AppColors.successLight,
            warning: AppColors.warningLight,
            info: AppColors.infoLight,
          );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [status],
      // ---- Buttons: dominant primary action, 44dp+ targets (§4/§5) ----
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.rMd),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.rMd),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: textTheme.labelLarge,
        ),
      ),
      // ---- Cards: subtle elevation, consistent radius (§4) ----
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.rLg,
          side: isDark
              ? BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))
              : BorderSide.none,
        ),
      ),
      // ---- Inputs: clear, filled, large touch target (§4 forms) ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.4 : 0.6),
        border: const OutlineInputBorder(
          borderRadius: AppRadii.rMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.rMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.rMd,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 2,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelType: NavigationRailLabelType.all,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.rSm),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.rMd),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.rLg),
      ),
    );
  }
}

/// Status colours that adapt to the active brightness, exposed as a
/// [ThemeExtension] so widgets read `Theme.of(context).extension<AppStatusColors>()`
/// instead of hardcoding. Always render alongside an icon + label (§5).
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.success,
    required this.warning,
    required this.info,
  });

  final Color success;
  final Color warning;
  final Color info;

  /// Convenience accessor: `AppStatusColors.of(context).success`.
  static AppStatusColors of(BuildContext context) =>
      Theme.of(context).extension<AppStatusColors>()!;

  @override
  AppStatusColors copyWith({Color? success, Color? warning, Color? info}) =>
      AppStatusColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info: info ?? this.info,
      );

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
