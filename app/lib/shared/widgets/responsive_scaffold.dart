import 'package:flutter/material.dart';

import '../../core/theme/breakpoints.dart';

/// Centers content and constrains width on large screens so the SAME widgets
/// reflow cleanly from phone to desktop (single codebase, Section 3).
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.title,
    required this.child,
    this.maxContentWidth = 480,
    this.showBack = true,
  });

  final String title;
  final Widget child;
  final double maxContentWidth;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final wide = !Breakpoints.isMobile(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: showBack,
        centerTitle: wide,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}
