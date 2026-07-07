import 'package:flutter/material.dart';

import '../../core/theme/breakpoints.dart';
import 'theme_toggle_button.dart';

/// Centers content and constrains width on large screens so the SAME widgets
/// reflow cleanly from phone to desktop (single codebase, Section 3).
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.title,
    required this.child,
    this.maxContentWidth = 480,
    this.showBack = true,
    this.actions,
  });

  final String title;
  final Widget child;
  final double maxContentWidth;
  final bool showBack;

  /// Extra app-bar actions, shown before the always-present theme toggle.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final wide = !Breakpoints.isMobile(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: showBack,
        centerTitle: wide,
        actions: [...?actions, const ThemeToggleButton()],
      ),
      // Scrollable so tall forms survive the on-screen keyboard on mobile
      // (the register form overflowed by ~336px when the keyboard opened).
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
