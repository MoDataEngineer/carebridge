import 'dart:async';

import 'package:flutter/material.dart';
import '../../shared/widgets/pills_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/enums.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import '../auth/clinic/clinic_sign_out_button.dart';
import 'doctor_models.dart';
import 'queue_repository.dart';

/// Live appointment/token tracker (Phase 10, paid tier — Section 9).
/// Doctor-scoped: own queue with check-in + "Call next". Admin-scoped:
/// clinic-wide tracker grouped by doctor (check-in = front desk; calling the
/// next patient stays doctor-only, enforced in the DB too).
/// Updates arrive via Supabase Realtime — each change signal refetches the
/// queue (Section 10: seconds, not polling).
class LiveQueueScreen extends ConsumerStatefulWidget {
  const LiveQueueScreen({super.key, required this.scope});
  final DoctorScope scope;

  @override
  ConsumerState<LiveQueueScreen> createState() => _LiveQueueScreenState();
}

class _LiveQueueScreenState extends ConsumerState<LiveQueueScreen> {
  List<QueueEntry>? _entries;
  StreamSubscription<void>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = ref
        .read(queueRepositoryProvider)
        .changes()
        .listen((_) => _reload());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final rows = await ref.read(queueRepositoryProvider).liveQueue();
      if (mounted) setState(() => _entries = rows);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Queue load failed: $e')));
      }
    }
  }

  Future<void> _checkIn(QueueEntry e) async {
    setState(() => _busy = true);
    try {
      final token = await ref.read(queueRepositoryProvider).checkIn(e.appointmentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.patientName} checked in — token $token')));
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Check-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _callNext() async {
    setState(() => _busy = true);
    try {
      final called = await ref.read(queueRepositoryProvider).callNext();
      if (!mounted) return;
      if (called == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No one is waiting.')));
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Call next failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.scope.role == ActiveRole.admin;
    final entries = _entries;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Clinic queue — all doctors' : 'Live queue'),
        automaticallyImplyLeading: false,
        actions: const [ThemeToggleButton(), ClinicSignOutButton()],
      ),
      // "Call next" is the doctor's action (AC-9-adjacent: who enters the
      // room is the doctor's call, not the front desk's).
      floatingActionButton: widget.scope.canWrite
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _callNext,
              icon: const Icon(Icons.campaign),
              label: const Text('Call next'),
            )
          : null,
      body: entries == null
          ? const Center(child: PillsLoader())
          : entries.isEmpty
              ? const Center(child: Text('No appointments today.'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final e in entries) _entryTile(e, isAdmin),
                  ],
                ),
    );
  }

  Widget _entryTile(QueueEntry e, bool isAdmin) {
    final (icon, label) = switch (e.status) {
      'in_consultation' => (Icons.meeting_room, 'In consultation'),
      'waiting' => (Icons.hourglass_top, 'Waiting'),
      'completed' => (Icons.check_circle_outline, 'Done'),
      _ => (Icons.event, 'Scheduled'),
    };
    final time = TimeOfDay.fromDateTime(e.scheduledTime.toLocal()).format(context);
    return Card(
      child: ListTile(
        leading: e.queuePosition != null
            ? CircleAvatar(child: Text('${e.queuePosition}'))
            : Icon(icon),
        title: Text(e.patientName),
        subtitle: Text(
            '$label · $time${isAdmin ? ' · ${e.doctorName}' : ''}'),
        trailing: e.status == 'scheduled'
            ? TextButton(
                onPressed: _busy ? null : () => _checkIn(e),
                child: const Text('Check in'),
              )
            : null,
      ),
    );
  }
}
