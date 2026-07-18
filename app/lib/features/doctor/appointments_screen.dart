import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/enums.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import '../auth/clinic/availability_screen.dart';
import '../auth/clinic/clinic_sign_out_button.dart';
import '../auth/clinic/session_controller.dart';
import 'appointments_repository.dart';

/// Clinic appointments dashboard (founder request 2026-07-07): TODAY + FUTURE
/// requests for the active scope, with Approve (pending → confirmed) and Reject
/// (emergency cancel, notifies the patient). Live via Realtime. This is the
/// free-tier "what's booked" view; the paid live TOKEN queue is a separate
/// destination.
class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  List<UpcomingAppointment>? _appts;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = ref.read(appointmentsRepositoryProvider).changes().listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(appointmentsRepositoryProvider).upcoming();
      if (mounted) setState(() => _appts = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load appointments: $e')));
      }
    }
  }

  Future<void> _approve(UpcomingAppointment a) async {
    try {
      await ref.read(appointmentsRepositoryProvider).approve(a.appointmentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Approved ${a.patientName}\'s request')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not approve: $e')));
      }
    }
  }

  Future<void> _reject(UpcomingAppointment a) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel ${a.patientName}\'s appointment?'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'e.g. doctor unavailable — emergency',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel appointment'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(appointmentsRepositoryProvider).reject(
            a.appointmentId,
            reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cancelled — ${a.patientName} was notified')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appts = _appts;
    // Gap A (founder 2026-07-18): a DOCTOR-scoped session (incl. solo — which
    // never sees the admin roster) needs its own way into the availability
    // editor; without sessions set, patients see nothing to book. The RPC
    // already allows a doctor to edit their own schedule (0025).
    final session = ref.watch(clinicSessionControllerProvider);
    final active = session.active;
    final ownDoctorId =
        (active?.role == ActiveRole.doctor) ? active?.doctorId : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        automaticallyImplyLeading: false,
        actions: [
          if (ownDoctorId != null)
            IconButton(
              tooltip: 'My availability',
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: () {
                var name = 'My schedule';
                for (final d in session.login?.doctors ?? const []) {
                  if (d.id == ownDoctorId) {
                    name = d.name;
                    break;
                  }
                }
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AvailabilityScreen(
                      doctorId: ownDoctorId, doctorName: name),
                ));
              },
            ),
          const ThemeToggleButton(),
          const ClinicSignOutButton(),
        ],
      ),
      body: appts == null
          ? const SkeletonLoader()
          : appts.isEmpty
              ? EmptyState(
                  icon: Icons.event_available,
                  title: 'No upcoming appointments',
                  message: ownDoctorId != null
                      ? 'Requests patients make — for today and future days — '
                          'show up here. Patients can only book once you\'ve set '
                          'your consultation times: tap the calendar icon above.'
                      : 'Requests patients make — for today and future days — show '
                          'up here to approve or decline.')
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: _buildGrouped(context, appts),
                ),
    );
  }

  List<Widget> _buildGrouped(BuildContext context, List<UpcomingAppointment> appts) {
    final widgets = <Widget>[];
    String? lastDay;
    for (final a in appts) {
      final day = a.scheduledTime.toString().substring(0, 10);
      if (day != lastDay) {
        lastDay = day;
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(_dayLabel(a.scheduledTime),
              style: Theme.of(context).textTheme.titleSmall),
        ));
      }
      widgets.add(_ApptCard(appt: a, onApprove: () => _approve(a), onReject: () => _reject(a)));
    }
    return widgets;
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow =
        d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day;
    final base = d.toString().substring(0, 10);
    if (isToday) return 'Today · $base';
    if (isTomorrow) return 'Tomorrow · $base';
    return base;
  }
}

class _ApptCard extends StatelessWidget {
  const _ApptCard({required this.appt, required this.onApprove, required this.onReject});
  final UpcomingAppointment appt;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final time = appt.scheduledTime.toString().substring(11, 16);
    final sub = [
      time,
      if (appt.sessionLabel != null && appt.sessionLabel!.isNotEmpty) appt.sessionLabel!,
      appt.doctorName,
    ].join(' · ');
    final closed = appt.status == 'completed';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(appt.patientName,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                _ApptStatusPill(appt.status),
              ],
            ),
            Text(sub, style: Theme.of(context).textTheme.bodySmall),
            if (!closed) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (appt.isPending)
                    FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(appt.isPending ? 'Decline' : 'Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Appointment status as colour + icon + label (§5). Distinct from the
/// test-status StatusPill — appointment statuses differ.
class _ApptStatusPill extends StatelessWidget {
  const _ApptStatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = AppStatusColors.of(context);
    final (String label, IconData icon, Color color) = switch (status) {
      'requested' => ('Pending', Icons.hourglass_bottom, s.warning),
      'scheduled' => ('Confirmed', Icons.event_available, s.info),
      'waiting' => ('Checked in', Icons.confirmation_number, s.info),
      'in_consultation' => ('In consultation', Icons.meeting_room, scheme.primary),
      'completed' => ('Done', Icons.check_circle, s.success),
      _ => (status, Icons.help_outline, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
