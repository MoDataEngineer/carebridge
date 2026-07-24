import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// One destination in [PillNavBar].
class PillNavItem {
  const PillNavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// The app's floating bottom navigation — a rounded white bar where the active
/// destination is a dark ink pill holding its icon + label (prototype look).
///
/// This is a hand-rolled Row (not Material's [NavigationBar]) on purpose: the
/// stock NavigationBar, wrapped in the floating rounded clip, intermittently
/// dropped the first destination when a later tab was selected. A plain Row can
/// never lose an item, and it gives us the exact horizontal-pill selection the
/// prototype shows, with a subtle scale-pop on the active icon.
class PillNavBar extends StatelessWidget {
  const PillNavBar({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final int currentIndex;
  final List<PillNavItem> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Theme.of(context).colorScheme.surfaceContainerHigh
                : Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                _NavItem(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PillNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelLarge;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: AppMotion.normal,
        curve: Curves.easeOut,
        padding: selected
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
            : const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.12 : 1.0,
              duration: AppMotion.normal,
              curve: Curves.easeOut,
              child: Icon(
                item.icon,
                size: 22,
                color: selected ? Colors.white : scheme.onSurfaceVariant,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Text(item.label,
                  style: label?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
