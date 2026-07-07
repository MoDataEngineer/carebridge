import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A lightweight, gently-pulsing placeholder shown while content loads —
/// preferred over a bare spinner for list content (UI brief §4). Kept
/// deliberately simple (one AnimationController, no shimmer package) per §6.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key, this.items = 4});

  /// How many placeholder cards to show.
  final int items;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: widget.items,
        itemBuilder: (_, __) => const _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Bar(widthFactor: 0.4, height: 14),
            SizedBox(height: AppSpacing.md),
            _Bar(widthFactor: 0.85, height: 12),
            SizedBox(height: AppSpacing.sm),
            _Bar(widthFactor: 0.65, height: 12),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.widthFactor, required this.height});
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          borderRadius: AppRadii.rSm,
        ),
      ),
    );
  }
}
