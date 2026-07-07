import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_controller.dart';

/// App-bar action that flips light/dark. Shows the icon of the theme you'd
/// switch TO, so the affordance is obvious (UI brief §2). Drop into any
/// `AppBar.actions`.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider); // rebuild the icon when the mode changes
    final showingDark = Theme.of(context).brightness == Brightness.dark;
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    return IconButton(
      tooltip: showingDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(showingDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () =>
          ref.read(themeModeProvider.notifier).toggle(platformBrightness),
    );
  }
}
