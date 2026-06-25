import 'package:flutter/material.dart';

/// Shared app theme (single codebase, all roles + platforms).
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF1565C0); // calm clinical blue

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
}
