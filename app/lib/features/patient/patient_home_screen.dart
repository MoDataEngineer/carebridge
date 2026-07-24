import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../shared/sound/notification_sound.dart';
import '../../shared/widgets/pill_nav_bar.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import '../diagnostics/test_orders_view.dart';
import '../notifications/notifications_controller.dart';
import '../notifications/notifications_screen.dart';
import 'book_appointment_tab.dart';
import 'history_tab.dart';
import 'home_tab.dart';

/// Patient app shell (Section 5.1). Bottom navigation (UI brief §3): 5
/// thumb-reachable destinations with icon + label. An [IndexedStack] keeps each
/// tab's state alive when switching. Navigation *destinations* are unchanged
/// from the previous top-tab layout — this is a visual reshape only (§7).
///
/// Gap B: the bell carries a live unread badge, and a chime plays when a new
/// notification arrives while the app is open (check-in, your-turn, approval…).
class PatientHomeScreen extends ConsumerStatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  int _index = 0;
  // Tabs are built lazily on first visit, then kept alive by the IndexedStack —
  // so a tab's data isn't loaded until the user opens it.
  final _visited = <int>{0};

  // Home shows an empty app-bar title (the greeting lives in the body).
  // Privacy moved under Profile (Home header avatar), so the bar is 4 tabs —
  // which also keeps the selected pill from crowding Home off the edge.
  static const _titles = ['', 'Book', 'History', 'Tests'];

  void _select(int i) => setState(() {
        _index = i;
        _visited.add(i);
      });

  // Only glyphs observed to render in this project's icon font. `home_outlined`
  // and the `_rounded` variants paint blank here, so Home uses the filled
  // `Icons.home` while the rest keep their `_outlined` forms (all confirmed
  // rendering).
  static const _destinations = [
    PillNavItem(icon: Icons.home, label: 'Home'),
    PillNavItem(icon: Icons.event_outlined, label: 'Book'),
    PillNavItem(icon: Icons.history_outlined, label: 'History'),
    PillNavItem(icon: Icons.science_outlined, label: 'Tests'),
  ];

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider);
    // Chime on arrival: only when the feed GROWS after its first snapshot —
    // never on the initial load (old rows aren't "news").
    ref.listen(notificationsFeedProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final after = next.valueOrNull;
      if (before != null && after != null && after.length > before.length) {
        playNotificationBeep();
      }
    });

    // Home gets a callback so its feature tiles switch the bottom-nav tab.
    final tabs = <Widget>[
      HomeTab(onNavigate: _select),
      const BookAppointmentTab(),
      const HistoryTab(),
      const TestOrdersView(), // my own orders (patientId null → RLS scopes)
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () {
              // Opening the feed clears the badge (everything becomes "seen").
              ref.read(notificationsSeenProvider.notifier).markSeen();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              ));
            },
          ),
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.go(Routes.entry),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < tabs.length; i++)
            _visited.contains(i) ? tabs[i] : const SizedBox.shrink(),
        ],
      ),
      // Floating pill nav (custom): the active tab is a dark ink pill with its
      // icon + label; Home is always present (Material's NavigationBar dropped
      // it when a later tab was selected).
      bottomNavigationBar: PillNavBar(
        currentIndex: _index,
        items: _destinations,
        onTap: _select,
      ),
    );
  }
}
