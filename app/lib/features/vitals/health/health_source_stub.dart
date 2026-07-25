import '../vitals_models.dart';
import 'health_source.dart';

/// Web / unsupported-platform stub. Never reads anything; [platformSupported] is
/// false so the app uses the demo source instead. Keeps `package:health` out of
/// the web build entirely.
HealthSource makeHealthSource() => _StubHealthSource();

class _StubHealthSource implements HealthSource {
  @override
  bool get platformSupported => false;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<bool> hasPermissions() async => false;

  @override
  Future<DailyVitals> readToday() async => const DailyVitals();

  @override
  Future<List<MetricPoint>> readWeekSteps() async => const [];

  @override
  Future<List<WorkoutSummary>> readWorkouts() async => const [];
}
