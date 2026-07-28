import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/metric_ring.dart';
import '../../shared/widgets/pills_loader.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/vital_tile.dart';
import '../../shared/widgets/week_bars.dart';
import 'connect_tracker_screen.dart';
import 'vitals_models.dart';
import 'vitals_repository.dart';

/// Patient's own daily fitness view (epic §2, Phase 12) — a Strava-style glance:
/// today's activity rings, resting HR / sleep / SpO2 tiles, a week trend, and a
/// workouts feed. Free and standalone; works with no doctor and no sharing.
///
/// STRICTLY NON-DIAGNOSTIC (§6): every figure is shown exactly as the device
/// reported it. Nothing here scores, grades, alerts, or interprets a value.
class VitalsTab extends ConsumerStatefulWidget {
  const VitalsTab({super.key});

  @override
  ConsumerState<VitalsTab> createState() => _VitalsTabState();
}

class _VitalsTabState extends ConsumerState<VitalsTab> {
  bool _loading = true;
  bool _connected = false;
  DailyVitals _today = const DailyVitals();
  List<MetricPoint> _week = const [];
  List<WorkoutSummary> _workouts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(vitalsRepositoryProvider);
    final conns = await repo.connections();
    final connected = conns.any((c) => c.connected);
    if (!connected) {
      if (mounted) {
        setState(() {
          _connected = false;
          _loading = false;
        });
      }
      return;
    }
    final results = await Future.wait([
      repo.today(),
      repo.weekTrend('steps'),
      repo.recentWorkouts(),
    ]);
    if (!mounted) return;
    setState(() {
      _connected = true;
      _today = results[0] as DailyVitals;
      _week = results[1] as List<MetricPoint>;
      _workouts = results[2] as List<WorkoutSummary>;
      _loading = false;
    });
  }

  Future<void> _manage() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ConnectTrackerScreen(),
    ));
    if (mounted) {
      setState(() => _loading = true);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PillsLoader());
    if (!_connected) return _NotConnected(onConnect: _manage);

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Today',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (_today.streakDays > 0) _streakPill(context, _today.streakDays),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Activity rings — raw counts against the patient's goals.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              MetricRing(
                value: _today.steps.toDouble(),
                goal: _today.stepsGoal.toDouble(),
                label: 'steps',
                color: AppColors.brand600,
              ),
              MetricRing(
                value: _today.activeMinutes.toDouble(),
                goal: _today.activeGoal.toDouble(),
                label: 'active min',
                color: AppColors.ctaGreen,
                centerText: '${_today.activeMinutes}',
              ),
              MetricRing(
                value: _today.calories.toDouble(),
                goal: _today.caloriesGoal.toDouble(),
                label: 'kcal',
                color: AppColors.pillPeach,
                centerText: '${_today.calories}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              if (_today.restingHr != null)
                VitalTile(label: 'Resting HR', value: '${_today.restingHr}', unit: 'bpm'),
              if (_today.sleepMinutes != null)
                VitalTile(label: 'Sleep', value: _sleep(_today.sleepMinutes!)),
              if (_today.hrv != null)
                VitalTile(
                    label: 'HRV',
                    value: '${_today.hrv}',
                    unit: _today.hrvIsRmssd ? 'ms rmssd' : 'ms sdnn'),
              if (_today.respiratoryRate != null)
                VitalTile(
                    label: 'Respiration',
                    value: _today.respiratoryRate!.toStringAsFixed(0),
                    unit: '/min'),
              if (_today.spo2 != null)
                VitalTile(label: 'SpO₂', value: '${_today.spo2}', unit: '%'),
              if (_today.distanceKm != null)
                VitalTile(
                    label: 'Distance',
                    value: _today.distanceKm!.toStringAsFixed(1),
                    unit: 'km'),
              if (_today.floors != null && _today.floors! > 0)
                VitalTile(label: 'Floors', value: '${_today.floors}'),
              if (_today.skinTempDelta != null)
                VitalTile(
                    label: 'Skin temp',
                    value: '${_today.skinTempDelta! >= 0 ? '+' : ''}'
                        '${_today.skinTempDelta!.toStringAsFixed(1)}',
                    unit: '°C'),
              if (_today.hasBloodPressure)
                VitalTile(
                    label: 'Blood pressure',
                    value: '${_today.bpSystolic}/${_today.bpDiastolic}',
                    unit: 'mmHg'),
            ],
          ),
          if (_week.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader('This week · steps'),
            const SizedBox(height: AppSpacing.md),
            WeekBars(points: _week),
          ],
          if (_workouts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader('Recent workouts'),
            const SizedBox(height: AppSpacing.md),
            for (final w in _workouts) _WorkoutCard(w: w),
          ],
          const SizedBox(height: AppSpacing.lg),
          // Non-diagnostic boundary made explicit to the patient (§6).
          Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Informational, from your device — not a diagnostic measurement.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: TextButton.icon(
              onPressed: _manage,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Manage trackers'),
            ),
          ),
        ],
      ),
    );
  }

  String _sleep(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

  Widget _streakPill(BuildContext context, int days) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.tintPeach,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department, size: 15, color: AppColors.pillPeach),
          const SizedBox(width: 5),
          Text('$days-day streak',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.brand800, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Empty state when no health source is connected yet.
class _NotConnected extends StatelessWidget {
  const _NotConnected({required this.onConnect});
  final VoidCallback onConnect;

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
            const CircleAvatar(
              radius: 34,
              backgroundColor: AppColors.tintMint,
              child: Icon(Icons.favorite, size: 30, color: AppColors.brand700),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Track your fitness',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Connect a health app to see your steps, workouts, sleep and heart '
              'rate — all in one place, always free.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Connect a tracker'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.w});
  final WorkoutSummary w;

  IconData get _icon => switch (w.type.toLowerCase()) {
        'walking' => Icons.directions_walk,
        'running' => Icons.directions_run,
        'cycling' => Icons.directions_bike,
        'swimming' => Icons.pool,
        _ => Icons.fitness_center,
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final bits = <String>[
      if (w.durationMin != null) '${w.durationMin} min',
      if (w.distanceM != null) '${(w.distanceM! / 1000).toStringAsFixed(1)} km',
      if (w.avgHr != null) '${w.avgHr} bpm',
      if (w.calories != null) '${w.calories} kcal',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadii.rCard,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.tintMint,
            child: Icon(_icon, size: 20, color: AppColors.brand700),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.type,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(bits.join(' · '),
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(_ago(w.startedAt),
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
