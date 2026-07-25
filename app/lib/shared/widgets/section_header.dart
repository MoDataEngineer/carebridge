import 'package:flutter/material.dart';

/// An uppercase section kicker — the small all-caps label above a group of
/// cards (used across the polished screens; also the vitals view sections).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.trailing});

  final String label;

  /// Optional trailing widget (e.g. a "See all" button) on the same row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        );
    if (trailing == null) return Text(label.toUpperCase(), style: style);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label.toUpperCase(), style: style), trailing!],
    );
  }
}
