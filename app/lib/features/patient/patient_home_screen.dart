import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My health record'),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => context.go(Routes.entry),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.person), text: 'Profile'),
              Tab(icon: Icon(Icons.event), text: 'Book'),
              Tab(icon: Icon(Icons.history), text: 'History'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ProfileTab(),
            BookAppointmentTab(),
            HistoryTab(),
          ],
        ),
      ),
    );
  }
}
