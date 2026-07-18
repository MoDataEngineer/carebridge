import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications_controller.dart';
import 'notifications_repository.dart';

/// Patient notification feed (Section 5.1): appointment, medication,
/// follow-up, report-ready, and live queue entries. LIVE (Gap B): watches the
/// Realtime stream, so check-in / your-turn / approval rows appear the moment
/// they land — no pull-to-refresh needed (though it stays as reassurance).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static const _icons = {
    'appointment_reminder': Icons.event,
    'follow_up': Icons.event_repeat,
    'report_ready': Icons.science,
    'medication_reminder': Icons.medication,
    'checked_in': Icons.confirmation_number,
    'your_turn': Icons.meeting_room,
    'appointment_approved': Icons.event_available,
    'appointment_rejected': Icons.event_busy,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(notificationsFeedProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load notifications: $e'),
          ),
        ]),
        data: (items) => items.isEmpty
            ? ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No notifications yet.')),
                ),
              ])
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final n = items[i];
                  return ListTile(
                    leading: Icon(_icons[n.type] ?? Icons.notifications),
                    title: Text(n.message),
                    subtitle: _timestamp(n) != null
                        ? Text(_timestamp(n)!
                            .toLocal()
                            .toString()
                            .substring(0, 16))
                        : null,
                  );
                },
              ),
      ),
    );
  }

  DateTime? _timestamp(PatientNotification n) => n.sentAt ?? n.scheduledFor;
}
