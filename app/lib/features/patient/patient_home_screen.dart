import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../shared/sound/notification_sound.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import '../consent/privacy_tab.dart';
import '../diagnostics/test_orders_view.dart';
import '../notifications/notifications_controller.dart';
import '../notifications/notifications_screen.dart';
import 'book_appointment_tab.dart';
import 'history_tab.dart';
import 'profile_tab.dart';

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

  static const _titles = ['Profile', 'Book', 'History', 'Tests', 'Privacy'];

  static const _tabs = [
    ProfileTab(),
    BookAppointmentTab(),
    HistoryTab(),
    TestOrdersView(), // my own orders (patientId null → RLS scopes)
    PrivacyTab(),
  ];

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'Profile',
    ),
    NavigationDestination(
      icon: Icon(Icons.event_outlined),
      selectedIcon: Icon(Icons.event),
      label: 'Book',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: 'History',
    ),
    NavigationDestination(
      icon: Icon(Icons.science_outlined),
      selectedIcon: Icon(Icons.science),
      label: 'Tests',
    ),
    NavigationDestination(
      icon: Icon(Icons.shield_outlined),
      selectedIcon: Icon(Icons.shield),
      label: 'Privacy',
    ),
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
          for (var i = 0; i < _tabs.length; i++)
            _visited.contains(i) ? _tabs[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: _destinations,
      ),
    );
  }
}
