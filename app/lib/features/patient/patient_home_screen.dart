import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../consent/privacy_tab.dart';
import '../diagnostics/test_orders_view.dart';
import '../notifications/notifications_screen.dart';
import 'book_appointment_tab.dart';
import 'history_tab.dart';
import 'profile_tab.dart';

/// Patient app shell (Section 5.1): Profile / Book / History tabs.
/// Reached after (placeholder) phone-OTP sign-in.
class PatientHomeScreen extends ConsumerWidget {
  const PatientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My health record'),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              )),
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => context.go(Routes.entry),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.person), text: 'Profile'),
              Tab(icon: Icon(Icons.event), text: 'Book'),
              Tab(icon: Icon(Icons.history), text: 'History'),
              Tab(icon: Icon(Icons.science), text: 'Tests'),
              Tab(icon: Icon(Icons.shield), text: 'Privacy'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ProfileTab(),
            BookAppointmentTab(),
            HistoryTab(),
            TestOrdersView(), // my own orders (patientId null → RLS scopes)
            PrivacyTab(),
          ],
        ),
      ),
    );
  }
}
