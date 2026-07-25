import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import 'vitals_models.dart';

/// Data for the patient's own daily fitness view (epic §2, Phase 12). Abstracted
/// so the UI can be widget-tested with a fake and demoed with fabricated data
/// before the on-device sync lands.
///
/// P12 boundary: this is the PATIENT's own view of their OWN data. The doctor
/// trend view and the `wearable` sharing grant are Phase 13. Everything returned
/// here is a raw device figure — never scored or interpreted (§6).
abstract class VitalsRepository {
  Future<List<VitalsConnection>> connections();
  Future<void> connect(WearableProvider provider);
  Future<void> disconnect(WearableProvider provider);
  Future<DailyVitals> today();
  Future<List<MetricPoint>> weekTrend(String metric);
  Future<List<WorkoutSummary>> recentWorkouts();

  bool get anyConnected;
}

/// Demo source — fabricates a realistic day so the tracker is usable and
/// web-verifiable BEFORE the on-device HealthKit / Health Connect sync (which
/// needs the `health` plugin, a new dependency pending approval) is wired.
/// It holds connection state in memory; nothing leaves the app.
class DemoVitalsRepository implements VitalsRepository {
  final Set<WearableProvider> _connected = {WearableProvider.healthConnect};

  @override
  bool get anyConnected => _connected.isNotEmpty;

  @override
  Future<List<VitalsConnection>> connections() async => [
        for (final p in WearableProvider.values)
          VitalsConnection(provider: p, connected: _connected.contains(p)),
      ];

  @override
  Future<void> connect(WearableProvider provider) async =>
      _connected.add(provider);

  @override
  Future<void> disconnect(WearableProvider provider) async =>
      _connected.remove(provider);

  @override
  Future<DailyVitals> today() async {
    if (_connected.isEmpty) return const DailyVitals();
    return const DailyVitals(
      steps: 6420,
      activeMinutes: 22,
      calories: 380,
      restingHr: 62,
      sleepMinutes: 400, // 6h 40m
      spo2: 97,
      streakDays: 4,
    );
  }

  @override
  Future<List<MetricPoint>> weekTrend(String metric) async {
    if (_connected.isEmpty) return const [];
    final now = DateTime.now();
    const steps = <double>[7200, 5400, 9100, 6800, 4300, 8800, 6420];
    return [
      for (var i = 0; i < 7; i++)
        MetricPoint(now.subtract(Duration(days: 6 - i)), steps[i]),
    ];
  }

  @override
  Future<List<WorkoutSummary>> recentWorkouts() async {
    if (_connected.isEmpty) return const [];
    final now = DateTime.now();
    return [
      WorkoutSummary(
        type: 'Walking',
        startedAt: now.subtract(const Duration(hours: 3)),
        durationMin: 32,
        distanceM: 2400,
        avgHr: 104,
        calories: 160,
      ),
      WorkoutSummary(
        type: 'Cycling',
        startedAt: now.subtract(const Duration(days: 1, hours: 5)),
        durationMin: 45,
        distanceM: 12800,
        avgHr: 128,
        calories: 410,
      ),
    ];
  }
}

/// Real reader/writer over the Phase-12 wearable tables (RLS scopes every row to
/// the signed-in patient). Becomes the active source once the on-device sync
/// (the `health` plugin) pushes aggregates into `wearable_metrics_daily`; until
/// then those tables are empty, so P12 ships [DemoVitalsRepository] as the
/// default (see [vitalsRepositoryProvider]).
class SupabaseVitalsRepository implements VitalsRepository {
  SupabaseVitalsRepository(this._client);
  final SupabaseClient _client;

  Set<WearableProvider> _live = {};

  @override
  bool get anyConnected => _live.isNotEmpty;

  Future<String?> _patientId() async {
    // RLS returns only the caller's own patient row.
    final rows = await _client.from('patients').select('id').limit(1);
    final list = rows as List;
    return list.isEmpty ? null : (list.first as Map)['id'] as String;
  }

  @override
  Future<List<VitalsConnection>> connections() async {
    final rows = await _client
        .from('wearable_connections')
        .select('provider, status')
        .eq('status', 'active');
    _live = {
      for (final m in rows as List)
        WearableProviderX.fromDb((m as Map)['provider'] as String)
    };
    return [
      for (final p in WearableProvider.values)
        VitalsConnection(provider: p, connected: _live.contains(p)),
    ];
  }

  @override
  Future<void> connect(WearableProvider provider) async {
    final pid = await _patientId();
    if (pid == null) return;
    await _client.from('wearable_connections').upsert({
      'patient_id': pid,
      'provider': provider.db,
      'status': 'active',
      'revoked_at': null,
    }, onConflict: 'patient_id,provider');
    _live.add(provider);
  }

  @override
  Future<void> disconnect(WearableProvider provider) async {
    await _client
        .from('wearable_connections')
        .update({'status': 'revoked', 'revoked_at': DateTime.now().toIso8601String()})
        .eq('provider', provider.db);
    _live.remove(provider);
  }

  int _metricInt(List rows, String type) {
    for (final m in rows) {
      if ((m as Map)['metric_type'] == type) {
        return (m['value'] as num?)?.round() ?? 0;
      }
    }
    return 0;
  }

  @override
  Future<DailyVitals> today() async {
    final day = DateTime.now().toIso8601String().split('T').first;
    final rows = await _client
        .from('wearable_metrics_daily')
        .select('metric_type, value')
        .eq('metric_date', day) as List;
    if (rows.isEmpty) return const DailyVitals();
    return DailyVitals(
      steps: _metricInt(rows, 'steps'),
      activeMinutes: _metricInt(rows, 'active_minutes'),
      calories: _metricInt(rows, 'calories'),
      restingHr: _metricInt(rows, 'resting_hr'),
      sleepMinutes: _metricInt(rows, 'sleep_minutes'),
    );
  }

  @override
  Future<List<MetricPoint>> weekTrend(String metric) async {
    final since = DateTime.now()
        .subtract(const Duration(days: 6))
        .toIso8601String()
        .split('T')
        .first;
    final rows = await _client
        .from('wearable_metrics_daily')
        .select('metric_date, value')
        .eq('metric_type', metric)
        .gte('metric_date', since)
        .order('metric_date') as List;
    return [
      for (final m in rows)
        MetricPoint(DateTime.parse((m as Map)['metric_date'].toString()),
            ((m['value'] as num?) ?? 0).toDouble())
    ];
  }

  @override
  Future<List<WorkoutSummary>> recentWorkouts() async {
    final rows = await _client
        .from('wearable_workouts')
        .select('type, started_at, duration_min, distance_m, avg_hr, calories')
        .order('started_at', ascending: false)
        .limit(20) as List;
    return [
      for (final m in rows)
        WorkoutSummary(
          type: (m as Map)['type'] as String,
          startedAt: DateTime.parse(m['started_at'].toString()),
          durationMin: m['duration_min'] as int?,
          distanceM: (m['distance_m'] as num?)?.toDouble(),
          avgHr: m['avg_hr'] as int?,
          calories: m['calories'] as int?,
        )
    ];
  }
}

/// P12 default = the demo source, so the patient tracker is usable and
/// verifiable before the on-device sync (a new `health` dependency, pending
/// approval) lands. Flip [_useDemo] to false once devices push real aggregates
/// into the wearable tables.
const bool _useDemo = true;

final vitalsRepositoryProvider = Provider<VitalsRepository>((ref) {
  if (_useDemo || !SupabaseService.isInitialized) {
    return DemoVitalsRepository();
  }
  return SupabaseVitalsRepository(SupabaseService.client);
});
