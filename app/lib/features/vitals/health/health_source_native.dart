import 'dart:io' show Platform;

// Our WorkoutSummary (vitals_models) shadows the package's same-named class.
import 'package:health/health.dart' hide WorkoutSummary;

import '../vitals_models.dart';
import 'health_source.dart';

HealthSource makeHealthSource() => NativeHealthSource();

/// Real on-device reader over Apple HealthKit (iOS) and Android Health Connect,
/// via `package:health`. Reads ONLY raw standardized types (epic §3) and never
/// derives a composite score (§6). HRV differs by platform — RMSSD on Android,
/// SDNN on iOS — and we carry that label through so the two are never conflated.
class NativeHealthSource implements HealthSource {
  final Health _health = Health();
  bool _configured = false;

  @override
  bool get platformSupported => Platform.isIOS || Platform.isAndroid;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// HRV type name differs per platform (§3 caveat).
  HealthDataType get _hrvType => Platform.isIOS
      ? HealthDataType.HEART_RATE_VARIABILITY_SDNN
      : HealthDataType.HEART_RATE_VARIABILITY_RMSSD;

  HealthDataType get _distanceType => Platform.isIOS
      ? HealthDataType.DISTANCE_WALKING_RUNNING
      : HealthDataType.DISTANCE_DELTA;

  /// The raw types we surface, filtered to those the current OS/device exposes
  /// (requesting an unavailable type throws).
  List<HealthDataType> get _types {
    final wanted = <HealthDataType>[
      HealthDataType.STEPS,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.HEART_RATE,
      HealthDataType.RESTING_HEART_RATE,
      _hrvType,
      HealthDataType.RESPIRATORY_RATE,
      HealthDataType.BLOOD_OXYGEN,
      HealthDataType.SKIN_TEMPERATURE,
      _distanceType,
      HealthDataType.FLIGHTS_CLIMBED,
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_SESSION,
      HealthDataType.EXERCISE_TIME,
      HealthDataType.WORKOUT,
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    ];
    return [
      for (final t in wanted)
        if (_isAvailable(t)) t,
    ];
  }

  bool _isAvailable(HealthDataType t) {
    try {
      return _health.isDataTypeAvailable(t);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (!platformSupported) return false;
    await _ensureConfigured();
    if (Platform.isAndroid) {
      try {
        return await _health.isHealthConnectAvailable();
      } catch (_) {
        return false;
      }
    }
    return true; // HealthKit is present on any real iOS device.
  }

  @override
  Future<bool> requestPermissions() async {
    if (!platformSupported) return false;
    await _ensureConfigured();
    final types = _types;
    try {
      return await _health.requestAuthorization(
        types,
        permissions: [for (final _ in types) HealthDataAccess.READ],
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasPermissions() async {
    if (!platformSupported) return false;
    await _ensureConfigured();
    try {
      return (await _health.hasPermissions(_types)) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---- reads ----------------------------------------------------------------

  Future<List<HealthDataPoint>> _points(
      List<HealthDataType> types, DateTime start, DateTime end) async {
    final avail = [for (final t in types) if (_isAvailable(t)) t];
    if (avail.isEmpty) return const [];
    try {
      return await _health.getHealthDataFromTypes(
          types: avail, startTime: start, endTime: end);
    } catch (_) {
      return const [];
    }
  }

  double? _latest(List<HealthDataPoint> pts, HealthDataType type) {
    HealthDataPoint? best;
    for (final p in pts) {
      if (p.type != type) continue;
      if (best == null || p.dateTo.isAfter(best.dateTo)) best = p;
    }
    final v = best?.value;
    return v is NumericHealthValue ? v.numericValue.toDouble() : null;
  }

  double _sum(List<HealthDataPoint> pts, HealthDataType type) {
    var total = 0.0;
    for (final p in pts) {
      if (p.type != type) continue;
      final v = p.value;
      if (v is NumericHealthValue) total += v.numericValue.toDouble();
    }
    return total;
  }

  @override
  Future<DailyVitals> readToday() async {
    await _ensureConfigured();
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final pts = await _points(_types, startOfDay, now);

    // Steps: the dedicated helper is more accurate than summing samples.
    int steps = 0;
    try {
      steps = (await _health.getTotalStepsInInterval(startOfDay, now)) ?? 0;
    } catch (_) {
      steps = _sum(pts, HealthDataType.STEPS).round();
    }

    final distanceM = _sum(pts, _distanceType);
    final exerciseMin = _sum(pts, HealthDataType.EXERCISE_TIME);

    // Sleep from last night (yesterday 18:00 → today noon).
    final sleepStart = DateTime(now.year, now.month, now.day - 1, 18);
    final sleepEnd = DateTime(now.year, now.month, now.day, 12);
    final sleepPts = await _points(
        [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_SESSION],
        sleepStart, sleepEnd);
    var sleepMin = 0;
    for (final p in sleepPts) {
      sleepMin += p.dateTo.difference(p.dateFrom).inMinutes;
    }

    final hrv = _latest(pts, _hrvType);

    return DailyVitals(
      steps: steps,
      activeMinutes: exerciseMin.round(),
      calories: _sum(pts, HealthDataType.ACTIVE_ENERGY_BURNED).round(),
      restingHr: _latest(pts, HealthDataType.RESTING_HEART_RATE)?.round(),
      sleepMinutes: sleepMin > 0 ? sleepMin : null,
      spo2: _pct(_latest(pts, HealthDataType.BLOOD_OXYGEN)),
      hrv: hrv?.round(),
      hrvIsRmssd: !Platform.isIOS,
      respiratoryRate: _latest(pts, HealthDataType.RESPIRATORY_RATE),
      skinTempDelta: _latest(pts, HealthDataType.SKIN_TEMPERATURE),
      distanceKm: distanceM > 0 ? distanceM / 1000 : null,
      floors: _sum(pts, HealthDataType.FLIGHTS_CLIMBED).round(),
      bpSystolic: _latest(pts, HealthDataType.BLOOD_PRESSURE_SYSTOLIC)?.round(),
      bpDiastolic: _latest(pts, HealthDataType.BLOOD_PRESSURE_DIASTOLIC)?.round(),
    );
  }

  /// SpO2 comes back as a fraction (0–1) on some sources, a percent on others.
  int? _pct(double? v) {
    if (v == null) return null;
    return (v <= 1 ? v * 100 : v).round();
  }

  @override
  Future<List<MetricPoint>> readWeekSteps() async {
    await _ensureConfigured();
    final now = DateTime.now();
    final out = <MetricPoint>[];
    for (var i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      final next = day.add(const Duration(days: 1));
      int steps = 0;
      try {
        steps = (await _health.getTotalStepsInInterval(day, next)) ?? 0;
      } catch (_) {}
      out.add(MetricPoint(day, steps.toDouble()));
    }
    return out;
  }

  @override
  Future<List<WorkoutSummary>> readWorkouts() async {
    await _ensureConfigured();
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 7));
    final pts = await _points([HealthDataType.WORKOUT], since, now);
    final out = <WorkoutSummary>[];
    for (final p in pts) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      out.add(WorkoutSummary(
        type: _workoutLabel(v.workoutActivityType),
        startedAt: p.dateFrom,
        durationMin: p.dateTo.difference(p.dateFrom).inMinutes,
        distanceM: v.totalDistance?.toDouble(),
        calories: v.totalEnergyBurned,
      ));
    }
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }

  /// Map the platform workout enum to a readable label. Covers the common and
  /// India-popular sports; anything else falls back to a title-cased name.
  String _workoutLabel(HealthWorkoutActivityType t) => switch (t) {
        HealthWorkoutActivityType.WALKING => 'Walking',
        HealthWorkoutActivityType.RUNNING => 'Running',
        HealthWorkoutActivityType.BIKING => 'Cycling',
        HealthWorkoutActivityType.SWIMMING => 'Swimming',
        HealthWorkoutActivityType.STRENGTH_TRAINING => 'Strength',
        HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING => 'HIIT',
        HealthWorkoutActivityType.YOGA => 'Yoga',
        HealthWorkoutActivityType.PILATES => 'Pilates',
        HealthWorkoutActivityType.ELLIPTICAL => 'Elliptical',
        HealthWorkoutActivityType.ROWING => 'Rowing',
        HealthWorkoutActivityType.HIKING => 'Hiking',
        HealthWorkoutActivityType.CRICKET => 'Cricket',
        HealthWorkoutActivityType.TENNIS => 'Tennis',
        HealthWorkoutActivityType.BADMINTON => 'Badminton',
        _ => _title(t.name),
      };

  String _title(String enumName) {
    final words = enumName.toLowerCase().split('_');
    return words.map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
}
