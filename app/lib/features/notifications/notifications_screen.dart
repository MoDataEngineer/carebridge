import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications_repository.dart';

/// Patient notification feed (Section 5.1): appointment, medication,
/// follow-up, and report-ready entries. This in-app feed works today; FCM
/// push delivery of the same rows activates once Firebase is configured.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<PatientNotification>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(notificationsRepositoryProvider).feed();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  static const _icons = {
    'appointment_reminder': Icons.event,
    'follow_up': Icons.event_repeat,
    'report_ready': Icons.science,
    'medication_reminder': Icons.medication,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load notifications: $_error'),
                ),
              ])
            : _items == null
                ? const Center(child: CircularProgressIndicator())
                : _items!.isEmpty
                    ? ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No notifications yet.')),
                        ),
                      ])
                    : ListView.separated(
                        itemCount: _items!.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final n = _items![i];
                          return ListTile(
                            leading: Icon(_icons[n.type] ?? Icons.notifications),
                            title: Text(n.message),
                            subtitle: n.scheduledFor != null
                                ? Text(n.scheduledFor!
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
}
