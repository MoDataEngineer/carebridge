import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
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
          padding: EdgeInsets.fromLTRB(4, widgets.isEmpty ? 4 : 20, 4, 8),
          child: Text(_dayLabel(a.scheduledTime).toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  )),
        ));
      }
      widgets.add(_ApptCard(appt: a, onApprove: () => _approve(a), onReject: () => _reject(a)));
    }
    return widgets;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow =
        d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day;
    final base = '${d.day} ${_months[d.month - 1]} ${d.year}';
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

  /// "09:30" (24h from the timestamp) -> "9:30 AM".
  String _time(DateTime t) {
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sub = [
      if (appt.sessionLabel != null && appt.sessionLabel!.isNotEmpty) appt.sessionLabel!,
      appt.doctorName,
    ].join(' · ');
    final closed = appt.status == 'completed';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadii.rCard,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Time chip — soft mint pill so the slot reads at a glance.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.tintMint,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(_time(appt.scheduledTime),
                    style: text.labelMedium?.copyWith(
                        color: AppColors.brand700, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              _ApptStatusPill(appt.status),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(appt.patientName,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (sub.isNotEmpty)
            Text(sub, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (appt.patientPhone != null && appt.patientPhone!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.phone, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  SelectableText(appt.patientPhone!,
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          if (!closed) ...[
              const SizedBox(height: 8),
              // The app theme sets minimumSize: Size.fromHeight(52) — INFINITE
              // min width. Fine where parents bound width (ListView/stretched
              // Column), but inside an unbounded Row it forces an impossible
              // layout and the buttons silently failed to paint in release
              // ("pending but no approve" bug, 2026-07-18). Compact minimums +
              // a Wrap (flows on narrow widths) keep the actions visible.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (appt.isPending)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(44, 44)),
                      onPressed: onApprove,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44)),
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(appt.isPending ? 'Decline' : 'Cancel'),
                  ),
                ],
              ),
            ],
          ],
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
