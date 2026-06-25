import 'package:flutter/widgets.dart';

/// Responsive breakpoints. ONE codebase reflows the same widgets by screen size
/// (Section 3) — never fork into separate web/mobile projects.
class Breakpoints {
  const Breakpoints._();

  static const double mobile = 600;
  static const double tablet = 1024;

  static bool isMobile(BuildContext c) => MediaQuery.sizeOf(c).width < mobile;
  static bool isTablet(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return w >= mobile && w < tablet;
  }

  static bool isDesktop(BuildContext c) => MediaQuery.sizeOf(c).width >= tablet;
}
