import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/pills_loader.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/vital_tile.dart';
import '../../shared/widgets/week_bars.dart';
import 'doctor_vitals_repository.dart';
import 'vitals_models.dart';

/// Doctor's per-patient vitals trend + adherence view (epic §2, Phase 13).
/// PAID + consent gated: only reached when the clinic is paid, and the data
/// call itself only succeeds with an active `wearable` grant (enforced in the
/// DB, which also logs the read). Shows RAW trends and an advice-vs-actual
/// overlay — never a score or interpretation (§6).
class DoctorVitalsTab extends ConsumerStatefulWidget {
  const DoctorVitalsTab({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<DoctorVitalsTab> createState() => _DoctorVitalsTabState();
}

class _DoctorVitalsTabState extends ConsumerState<DoctorVitalsTab> {
  late Future<PatientVitalsView> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(doctorVitalsRepositoryProvider).forPatient(widget.patientId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PatientVitalsView>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: PillsLoader());
        }
        if (snap.hasError) {
          // The RPC raises when there's no wearable grant (or the clinic isn't
          // paid) — surface it as "not shared", never as a raw error.
          return const _NotShared();
        }
        return _VitalsContent(view: snap.data!);
      },
    );
  }
}

class _NotShared extends StatelessWidget {
  const _NotShared();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Vitals not shared',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'This patient has not shared their wearable vitals with you. They '
              'can turn on "Share my vitals" for you under Privacy & access.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _VitalsContent extends StatelessWidget {
  const _VitalsContent({required this.view});
  final PatientVitalsView view;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static String _fmt(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  List<MetricPoint> _last7(String metric) {
    final s = view.series(metric);
    return s.length <= 7 ? s : s.sublist(s.length - 7);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final steps = _last7('steps');
    final restingHr = view.latest('resting_hr');
    final hrv = view.latest('hrv');
    final sleep = view.latest('sleep_minutes');
    final active = _last7('active_minutes');
    final avgActive = active.isEmpty
        ? null
        : (active.map((p) => p.value).reduce((a, b) => a + b) / active.length).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Trust reassurance: the patient shared this, and the doctor's read is
        // logged for them (§5).
        Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Shared by the patient · this view is logged',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        if (view.advice?.hasTarget == true)
          _AdherenceCard(advice: view.advice!, active: active),

        if (steps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('This week · steps'),
          const SizedBox(height: AppSpacing.md),
          WeekBars(points: steps),
        ],

        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            if (avgActive != null)
              VitalTile(label: 'Avg active', value: '$avgActive', unit: 'min/day'),
            if (restingHr != null)
              VitalTile(label: 'Resting HR', value: '${restingHr.round()}', unit: 'bpm'),
            if (hrv != null)
              VitalTile(label: 'HRV', value: '${hrv.round()}', unit: 'ms'),
            if (sleep != null)
              VitalTile(
                  label: 'Sleep',
                  value: '${sleep ~/ 60}h ${(sleep % 60).round()}m'),
          ],
        ),

        if (view.workouts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Recent workouts'),
          const SizedBox(height: AppSpacing.sm),
          for (final w in view.workouts.take(6))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fitness_center, size: 18),
              title: Text(w.type),
              subtitle: Text([
                _fmt(w.startedAt),
                if (w.durationMin != null) '${w.durationMin} min',
                if (w.distanceM != null) '${(w.distanceM! / 1000).toStringAsFixed(1)} km',
                if (w.calories != null) '${w.calories} kcal',
              ].join(' · ')),
            ),
        ],

        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Icon(Icons.info_outline, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Informational, from the patient\'s device — not a diagnostic '
                'measurement.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Advice-vs-actual overlay — the objective follow-up loop. Shows what the
/// doctor advised at a visit and, factually, how many days this week the
/// patient met it. No judgement, no score — just target vs actual (§6).
class _AdherenceCard extends StatelessWidget {
  const _AdherenceCard({required this.advice, required this.active});
  final VisitAdvice advice;
  final List<MetricPoint> active;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final target = advice.activityMinutesTarget!;
    final daysTarget = advice.daysPerWeek ?? 7;
    final daysMet = active.where((p) => p.value >= target).length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        borderRadius: AppRadii.rCard,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand600, AppColors.brand800],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FOLLOW-UP ON ADVICE',
              style: text.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(
            'Advised $target min activity × $daysTarget/week'
            '${advice.note != null ? ' — ${advice.note}' : ''}',
            style: text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('$daysMet',
                  style: text.headlineMedium
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('of $daysTarget days met this week',
                    style: text.bodyMedium?.copyWith(color: Colors.white)),
              ),
            ],
          ),
          if (advice.visitDate != null)
            Text('From the visit on ${_VitalsContent._fmt(advice.visitDate!)}',
                style: text.bodySmall?.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }
}
