import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import 'vitals_models.dart';

/// Structured advice a doctor wrote at a visit — the target the adherence
/// overlay compares against.
class VisitAdvice {
  const VisitAdvice({
    this.activityMinutesTarget,
    this.daysPerWeek,
    this.note,
    this.visitDate,
    this.followUpDate,
  });

  final int? activityMinutesTarget;
  final int? daysPerWeek;
  final String? note;
  final DateTime? visitDate;
  final DateTime? followUpDate;

  bool get hasTarget => activityMinutesTarget != null;

  factory VisitAdvice.fromJson(Map<String, dynamic> m) {
    final a = (m['advice'] as Map?)?.cast<String, dynamic>() ?? const {};
    return VisitAdvice(
      activityMinutesTarget: (a['activity_minutes_target'] as num?)?.toInt(),
      daysPerWeek: (a['days_per_week'] as num?)?.toInt(),
      note: a['note'] as String?,
      visitDate: m['visit_date'] != null
          ? DateTime.tryParse(m['visit_date'].toString())
          : null,
      followUpDate: m['follow_up_date'] != null
          ? DateTime.tryParse(m['follow_up_date'].toString())
          : null,
    );
  }
}

/// A patient's shared vitals as the doctor sees them: daily metric series
/// (keyed by metric_type), recent workouts, and the latest visit advice.
class PatientVitalsView {
  const PatientVitalsView({
    required this.daily,
    required this.workouts,
    this.advice,
  });

  final Map<String, List<MetricPoint>> daily;
  final List<WorkoutSummary> workouts;
  final VisitAdvice? advice;

  List<MetricPoint> series(String metric) => daily[metric] ?? const [];

  /// Latest value of a metric, if any.
  double? latest(String metric) {
    final s = series(metric);
    return s.isEmpty ? null : s.last.value;
  }
}

/// Thrown when the patient has not shared vitals with this doctor (the RPC
/// enforces the grant + paid gate server-side).
class VitalsNotSharedException implements Exception {}

abstract class DoctorVitalsRepository {
  Future<PatientVitalsView> forPatient(String patientId);
}

/// Real read via the P13 RPC (grant + paid gated + audit-logged in the DB).
class SupabaseDoctorVitalsRepository implements DoctorVitalsRepository {
  SupabaseDoctorVitalsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<PatientVitalsView> forPatient(String patientId) async {
    try {
      final res = await _client
          .rpc('carebridge_patient_wearables', params: {'p_patient': patientId});
      return _parse((res as Map).cast<String, dynamic>());
    } on PostgrestException {
      // The RPC raises when there's no wearable grant or the clinic isn't paid.
      throw VitalsNotSharedException();
    }
  }

  PatientVitalsView _parse(Map<String, dynamic> m) {
    final daily = <String, List<MetricPoint>>{};
    for (final r in (m['daily'] as List? ?? const [])) {
      final row = (r as Map).cast<String, dynamic>();
      final type = row['metric_type'] as String;
      (daily[type] ??= []).add(MetricPoint(
        DateTime.parse(row['metric_date'].toString()),
        ((row['value'] as num?) ?? 0).toDouble(),
      ));
    }
    final workouts = [
      for (final w in (m['workouts'] as List? ?? const []))
        WorkoutSummary(
          type: (w as Map)['type'] as String,
          startedAt: DateTime.parse(w['started_at'].toString()),
          durationMin: w['duration_min'] as int?,
          distanceM: (w['distance_m'] as num?)?.toDouble(),
          calories: w['calories'] as int?,
        )
    ];
    return PatientVitalsView(
      daily: daily,
      workouts: workouts,
      advice: m['advice'] != null
          ? VisitAdvice.fromJson((m['advice'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}

/// Demo source so the doctor trend view is verifiable before migration 0036 is
/// deployed. Flip [_demoDoctorVitals] off once `supabase db push` has run.
class DemoDoctorVitalsRepository implements DoctorVitalsRepository {
  @override
  Future<PatientVitalsView> forPatient(String patientId) async {
    final now = DateTime.now();
    List<MetricPoint> series(List<double> v) => [
          for (var i = 0; i < v.length; i++)
            MetricPoint(now.subtract(Duration(days: v.length - 1 - i)), v[i]),
        ];
    return PatientVitalsView(
      daily: {
        'steps': series([7200, 5400, 9100, 6800, 4300, 8800, 6420]),
        'active_minutes': series([35, 20, 40, 25, 10, 45, 22]),
        'resting_hr': series([64, 63, 62, 63, 65, 61, 62]),
        'hrv': series([44, 46, 49, 47, 43, 50, 48]),
        'sleep_minutes': series([395, 410, 380, 420, 350, 430, 400]),
      },
      workouts: [
        WorkoutSummary(
            type: 'Walking',
            startedAt: now.subtract(const Duration(hours: 3)),
            durationMin: 32,
            distanceM: 2400,
            calories: 160),
        WorkoutSummary(
            type: 'Cycling',
            startedAt: now.subtract(const Duration(days: 1, hours: 5)),
            durationMin: 45,
            distanceM: 12800,
            calories: 410),
      ],
      advice: VisitAdvice(
        activityMinutesTarget: 30,
        daysPerWeek: 5,
        note: 'Brisk walk, cut salt',
        visitDate: now.subtract(const Duration(days: 12)),
        followUpDate: now.add(const Duration(days: 2)),
      ),
    );
  }
}

// Migrations 0034/0035/0036 are deployed (2026-07-28), so the doctor view reads
// the real RPC. Demo remains the fallback only when Supabase isn't initialized
// (e.g. a widget test without an override). Set back to true only to demo the
// trend view without a real phone-synced, vitals-sharing patient.
const bool _demoDoctorVitals = false;

final doctorVitalsRepositoryProvider = Provider<DoctorVitalsRepository>((ref) {
  if (_demoDoctorVitals || !SupabaseService.isInitialized) {
    return DemoDoctorVitalsRepository();
  }
  return SupabaseDoctorVitalsRepository(SupabaseService.client);
});
