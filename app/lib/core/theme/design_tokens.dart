import 'package:flutter/material.dart';

/// Centralized design tokens — the single source of truth for colour, spacing
/// and radii referenced by both the light and dark [ThemeData] (see
/// app_theme.dart). Do NOT hardcode these values per-widget; pull from here so
/// the dark-mode toggle and any future rebrand stay maintainable (UI brief §6).

/// Brand + semantic colours. The teal scale matches the ayulekha.in marketing
/// palette so web and app read as one product.
class AppColors {
  const AppColors._();

  // ---- Teal brand scale (light 50 → dark 900) ----
  static const brand50 = Color(0xFFEEFCF9);
  static const brand100 = Color(0xFFD6F7F0);
  static const brand200 = Color(0xFFB0EEE2);
  static const brand300 = Color(0xFF7BDFD0);
  static const brand400 = Color(0xFF40C8B8);
  static const brand500 = Color(0xFF1FAB9E);
  static const brand600 = Color(0xFF158A82); // primary accent (light)
  static const brand700 = Color(0xFF146E69);
  static const brand800 = Color(0xFF145855);
  static const brand900 = Color(0xFF144947);

  /// Hue anchor for the M3 tonal palette (ColorScheme.fromSeed).
  static const seed = brand600;

  // ---- Semantic status colours ----
  // Always pair these with an icon + text label; never convey status by colour
  // alone (UI brief §5, accessibility). Tuned for WCAG AA on their theme's
  // surface: the *Light values sit on light surfaces, *Dark on dark surfaces.
  static const successLight = Color(0xFF157A3C);
  static const successDark = Color(0xFF56D08B);
  static const warningLight = Color(0xFF945D00);
  static const warningDark = Color(0xFFF0B429);
  static const infoLight = brand700;
  static const infoDark = brand300;
}

/// 4-pt spacing scale. Use these instead of magic numbers in padding/gaps.
class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner radii. One consistent family across cards, buttons, inputs, sheets.
class AppRadii {
  const AppRadii._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
}

/// Motion durations — smooth, fast, purposeful (UI brief §2). Keep animation
/// off anything time-sensitive (e.g. mid-consultation "Order Test").
class AppMotion {
  const AppMotion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);
  static const Curve curve = Curves.easeOutCubic;
}
