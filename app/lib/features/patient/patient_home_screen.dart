import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import '../consent/privacy_tab.dart';
import '../diagnostics/test_orders_view.dart';
import '../notifications/notifications_screen.dart';
import 'book_appointment_tab.dart';
import 'history_tab.dart';
import 'profile_tab.dart';

/// Patient app shell (Section 5.1). Bottom navigation (UI brief §3): 5
/// thumb-reachable destinations with icon + label. An [IndexedStack] keeps each
/// tab's state alive when switching. Navigation *destinations* are unchanged
/// from the previous top-tab layout — this is a visual reshape only (§7).
class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const NotificationsScreen(),
            )),
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
