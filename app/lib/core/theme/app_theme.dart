import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

    // Healthcare type pairing (UI-UX-Pro-Max recommendation): Figtree for
    // headings/labels — friendly, rounded, professional — over Noto Sans body.
    // Body a notch larger than consumer defaults — patients span a wide age
    // range (UI brief §2). Respects OS text-scaling on top of this.
    final noto = GoogleFonts.notoSansTextTheme(base.textTheme);
    final t = noto.copyWith(
      displaySmall: GoogleFonts.figtree(textStyle: noto.displaySmall),
      headlineMedium: GoogleFonts.figtree(textStyle: noto.headlineMedium),
      headlineSmall: GoogleFonts.figtree(
          textStyle: noto.headlineSmall, fontWeight: FontWeight.w700),
      titleLarge: GoogleFonts.figtree(
          textStyle: noto.titleLarge, fontWeight: FontWeight.w700),
      titleMedium: GoogleFonts.figtree(
          textStyle: noto.titleMedium, fontWeight: FontWeight.w600),
      titleSmall: GoogleFonts.figtree(
          textStyle: noto.titleSmall, fontWeight: FontWeight.w600),
      labelLarge: GoogleFonts.figtree(
          textStyle: noto.labelLarge, fontWeight: FontWeight.w600),
    );
    final textTheme = t.copyWith(
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 17, height: 1.4),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, height: 1.35),
      titleMedium: t.titleMedium?.copyWith(fontSize: 17),
      labelLarge: t.labelLarge?.copyWith(fontSize: 15),
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

    // Medical-data type hierarchy (UI brief §2): a lab value must read at a
    // glance as VALUE (big, bold, tabular figures) / unit (medium) / label
    // (small, muted) — one spec reused by every vitals/result surface.
    final vitals = AppVitalStyles(
      value: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.1,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: scheme.onSurface,
      ),
      unit: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
      ),
      label: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: scheme.onSurfaceVariant,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      // Mint-tinted canvas: white cards float on it (reference #3 look).
      scaffoldBackgroundColor:
          isDark ? AppColors.canvasDark : AppColors.canvasLight,
      extensions: [status, vitals],
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
      // ---- Cards (reskin spec): WHITE floating on the mint canvas, 20px
      // radius, soft wide shadow, no borders — one treatment everywhere ----
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? scheme.surfaceContainerHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm / 2),
        shadowColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.rCard),
      ),
      // ---- Inputs: clear, filled, large touch target (§4 forms) ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : Colors.white,
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
      // App bar melts into the mint canvas — screens read as one surface.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? AppColors.canvasDark : AppColors.canvasLight,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge,
      ),
      // Bottom nav: white pill bar (shells wrap it with rounded corners). The
      // ACTIVE destination gets a dark ink pill with a white icon; its label
      // shows only when selected (prototype 1). Inactive = muted icon only.
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: isDark ? scheme.surfaceContainerHigh : Colors.white,
        indicatorColor: AppColors.ink,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? Colors.white
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => (textTheme.labelMedium ?? const TextStyle()).copyWith(
            color: s.contains(WidgetState.selected)
                ? AppColors.ink
                : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? scheme.surfaceContainerHigh : Colors.white,
        indicatorColor:
            isDark ? AppColors.tintMintDark : AppColors.tintMint,
        labelType: NavigationRailLabelType.all,
      ),
      // Pill chips (reference #2/#3 category + slot chips).
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        backgroundColor: isDark ? scheme.surfaceContainerHigh : Colors.white,
        selectedColor: isDark ? AppColors.tintMintDark : AppColors.tintMint,
        labelStyle: textTheme.labelLarge?.copyWith(fontSize: 14),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.rCard),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.rMd),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? scheme.surfaceContainerHigh : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.rXl),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? scheme.surfaceContainerHigh : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}

/// Medical-data text hierarchy (value / unit / label) as a [ThemeExtension] —
/// vitals and lab results read the same everywhere, light and dark.
@immutable
class AppVitalStyles extends ThemeExtension<AppVitalStyles> {
  const AppVitalStyles({
    required this.value,
    required this.unit,
    required this.label,
  });

  final TextStyle value;
  final TextStyle unit;
  final TextStyle label;

  static AppVitalStyles of(BuildContext context) =>
      Theme.of(context).extension<AppVitalStyles>()!;

  @override
  AppVitalStyles copyWith({TextStyle? value, TextStyle? unit, TextStyle? label}) =>
      AppVitalStyles(
        value: value ?? this.value,
        unit: unit ?? this.unit,
        label: label ?? this.label,
      );

  @override
  AppVitalStyles lerp(ThemeExtension<AppVitalStyles>? other, double t) {
    if (other is! AppVitalStyles) return this;
    return AppVitalStyles(
      value: TextStyle.lerp(value, other.value, t)!,
      unit: TextStyle.lerp(unit, other.unit, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
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
