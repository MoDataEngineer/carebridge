import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// One destination in [PillNavBar].
class PillNavItem {
  const PillNavItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });
  final IconData icon;
  final String label;

  /// Optional count bubble on the icon (0 = none), e.g. pending access requests.
  final int badgeCount;
}

/// The app's floating bottom navigation — a rounded white bar. Every
/// destination shows an icon + label (so none can be "invisible"); the active
/// one gets a teal brand pill behind its icon with a soft glow and a scale-pop,
/// tying the nav into the mint/teal theme.
///
/// Hand-rolled (not Material's [NavigationBar]) on purpose: the stock bar,
/// wrapped in the floating rounded clip, intermittently failed to paint the
/// first destination. A plain Row renders every child, every time.
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavItem(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
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
    // Guaranteed-visible resting colour (medium slate on the white bar).
    final rest = scheme.onSurface.withValues(alpha: 0.55);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.normal,
              curve: Curves.easeOut,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.brand600 : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.brand600.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: AnimatedScale(
                scale: selected ? 1.1 : 1.0,
                duration: AppMotion.normal,
                curve: Curves.easeOut,
                child: Badge(
                  isLabelVisible: item.badgeCount > 0,
                  label: Text('${item.badgeCount}'),
                  child: Icon(
                    item.icon,
                    size: 22,
                    color: selected ? Colors.white : rest,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    color: selected ? AppColors.brand700 : rest,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
