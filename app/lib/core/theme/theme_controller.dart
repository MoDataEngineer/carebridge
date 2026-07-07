import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The loaded [SharedPreferences] instance, injected in `main()` via an
/// override. Defaults to null so widget tests (which don't set up storage) keep
/// working — persistence simply no-ops there.
final sharedPreferencesProvider =
    Provider<SharedPreferences?>((ref) => null);

/// Holds the app-wide [ThemeMode]. Defaults to [ThemeMode.system] so the app
/// follows the device's light/dark setting, with an in-app override that now
/// persists across restarts (UI brief §2 dark mode).
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_initial(_prefs));

  final SharedPreferences? _prefs;
  static const _key = 'theme_mode';

  static ThemeMode _initial(SharedPreferences? prefs) {
    switch (prefs?.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void set(ThemeMode mode) {
    state = mode;
    _prefs?.setString(_key, mode.name);
  }

  /// Flip between light and dark based on what is *currently showing*, so one
  /// tap always visibly changes the theme even when starting from `system`.
  void toggle(Brightness platformBrightness) {
    final showingDark = state == ThemeMode.dark ||
        (state == ThemeMode.system && platformBrightness == Brightness.dark);
    set(showingDark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
        (ref) => ThemeModeController(ref.watch(sharedPreferencesProvider)));
