import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A one-shot entrance animation: a short fade + upward slide when the widget
/// first appears (UI brief §2 micro-animations — fast, purposeful). Honours the
/// platform "reduce motion" setting: when set, the child appears instantly with
/// no movement. Safe to use on time-sensitive content because it never blocks
/// interaction and finishes in ~200ms.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = AppMotion.normal,
    this.offset = 12,
  });

  final Widget child;
  final Duration duration;

  /// Vertical distance (px) the child slides up from.
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: AppMotion.curve);

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect the OS "reduce motion" request — show the child as-is.
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _a.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
