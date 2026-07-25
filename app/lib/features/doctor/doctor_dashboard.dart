import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../shared/models/enums.dart';
import '../../shared/widgets/pills_loader.dart';
import '../../shared/widgets/stat_card.dart';
import 'doctor_models.dart';
import 'paid_tools_repository.dart';
import 'queue_repository.dart';

/// Today-first doctor landing (prototype "Dr. …" screen). Surfaces the day at a
/// glance — who's waiting now, how many are booked today, follow-ups due — plus
/// the next patient to call, above the patient search. It reuses the existing
/// queue + follow-up repositories; it introduces no new backend and never
/// decides visibility itself (RLS scopes every row per [DoctorScope]).
///
/// The stat/next-patient cards don't deep-link by id (the queue RPC returns
/// names, not patient ids) — tapping "Open" hands the name back to the search
/// box via [onOpenByName], which the workspace already knows how to resolve.
class DoctorDashboard extends ConsumerStatefulWidget {
  const DoctorDashboard({
    super.key,
    required this.scope,
    required this.onOpenByName,
  });

  final DoctorScope scope;
  final void Function(String name) onOpenByName;

  @override
  ConsumerState<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends ConsumerState<DoctorDashboard> {
  List<QueueEntry> _queue = const [];
  int? _followUpsDue; // null when free tier or unavailable
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<QueueEntry> queue = const [];
    int? followUps;
    try {
      queue = await ref.read(queueRepositoryProvider).liveQueue();
    } catch (_) {
      // Queue repo/RPC unavailable (e.g. not deployed, or no Supabase in a
      // widget test) — degrade to an empty day.
    }
    if (widget.scope.paid) {
      try {
        followUps = (await ref.read(paidToolsRepositoryProvider).followUps()).length;
      } catch (_) {
        followUps = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _queue = queue;
      _followUpsDue = followUps;
      _loading = false;
    });
  }

  bool _isToday(DateTime t) {
    final now = DateTime.now();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  List<QueueEntry> get _today =>
      [for (final e in _queue) if (_isToday(e.scheduledTime)) e];

  int get _waitingNow =>
      _today.where((e) => e.status == 'waiting').length;

  /// The next patient to see: the lowest-token waiting entry, else the soonest
  /// still-upcoming scheduled one.
  QueueEntry? get _nextPatient {
    final waiting = [for (final e in _today) if (e.status == 'waiting') e]
      ..sort((a, b) =>
          (a.queuePosition ?? 1 << 30).compareTo(b.queuePosition ?? 1 << 30));
    if (waiting.isNotEmpty) return waiting.first;
    final scheduled = [
      for (final e in _today)
        if (e.status == 'scheduled') e
    ]..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return scheduled.isEmpty ? null : scheduled.first;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PillsLoader());

    final text = Theme.of(context).textTheme;
    final adminWide = widget.scope.role == ActiveRole.admin;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          Text('Today', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            adminWide ? 'Across all doctors in the clinic' : 'Your queue',
            style: text.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  value: '$_waitingNow',
                  label: 'Waiting now',
                  icon: Icons.person,
                  tint: AppColors.tintMint,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  value: '${_today.length}',
                  label: 'Booked today',
                  icon: Icons.event,
                  tint: AppColors.tintSky,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  value: '${_followUpsDue ?? 0}',
                  label: 'Follow-ups due',
                  icon: Icons.history,
                  tint: AppColors.tintPeach,
                  // Free-tier follow-up tracker is a Pro feature (Section 9).
                  locked: !widget.scope.paid,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _NextPatientCard(
            next: _nextPatient,
            onOpen: widget.onOpenByName,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Find a patient',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Search above by name, phone, or ABHA.',
            style: text.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _NextPatientCard extends StatelessWidget {
  const _NextPatientCard({required this.next, required this.onOpen});

  final QueueEntry? next;
  final void Function(String name) onOpen;

  String _time(DateTime t) {
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (next == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppRadii.rCard,
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined, color: AppColors.brand600),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('No one in the queue right now.',
                  style: text.bodyMedium),
            ),
          ],
        ),
      );
    }

    final e = next!;
    final waiting = e.status == 'waiting';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadii.rCard,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand600, AppColors.brand800],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand700.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(waiting ? 'NEXT TO SEE' : 'NEXT APPOINTMENT',
              style: text.labelSmall
                  ?.copyWith(color: Colors.white70, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(e.patientName,
              style: text.titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            [
              _time(e.scheduledTime),
              if (waiting && e.queuePosition != null) 'token #${e.queuePosition}',
              if (e.doctorName.isNotEmpty) e.doctorName,
            ].join(' · '),
            style: text.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: () => onOpen(e.patientName),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.brand700,
              minimumSize: const Size(140, 44),
            ),
            child: const Text('Open record'),
          ),
        ],
      ),
    );
  }
}
