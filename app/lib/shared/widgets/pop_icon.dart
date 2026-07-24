import 'package:flutter/material.dart';

/// A nav icon that "pops" — a quick scale + settle — whenever it mounts. Used as
/// a NavigationDestination's `selectedIcon`: because the selected icon is only
/// built when its destination becomes active, the pop plays each time the user
/// lands on that tab, giving the bottom nav a lively, animated feel.
class PopIcon extends StatefulWidget {
  const PopIcon(this.icon, {super.key});

  final IconData icon;

  @override
  State<PopIcon> createState() => _PopIconState();
}

class _PopIconState extends State<PopIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.18), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0), weight: 45),
  ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: Icon(widget.icon));
  }
}
