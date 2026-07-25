import '../vitals_models.dart';

// Conditional import: on native (dart.library.io true) the real HealthKit /
// Health Connect reader; on web the no-op stub. This keeps `package:health`
// (mobile-only) entirely out of the web build — same pattern as
// report_pdf_view. See health_source_native.dart / health_source_stub.dart.
import 'health_source_stub.dart'
    if (dart.library.io) 'health_source_native.dart';

/// Reads the patient's on-device health hub (Apple HealthKit / Android Health
/// Connect). Returns ONLY raw, standardized platform types — HR, RHR, HRV,
/// respiratory rate, SpO2, skin temperature, sleep, workouts, steps, distance,
/// floors, energy, blood pressure. It never derives a composite score or
/// interpretation (non-diagnostic, epic §6).
abstract class HealthSource {
  /// True only on iOS/Android (a HealthKit/Health Connect host). Web, desktop
  /// and the test VM return false — the app then falls back to the demo source.
  bool get platformSupported;

  /// Health Connect can be absent on Android (needs install/update). iOS
  /// HealthKit is always present on a real device.
  Future<bool> isAvailable();

  /// Requests OS read permission for the raw types we surface. This is consent
  /// layer (a) in §5 — separate from sharing anything with a doctor.
  Future<bool> requestPermissions();

  Future<bool> hasPermissions();

  Future<DailyVitals> readToday();
  Future<List<MetricPoint>> readWeekSteps();
  Future<List<WorkoutSummary>> readWorkouts();
}

/// Built via conditional import — native reader on device, no-op stub on web.
HealthSource createHealthSource() => makeHealthSource();
