import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/vitals/vitals_models.dart';
import 'package:carebridge/features/vitals/vitals_repository.dart';
import 'package:carebridge/features/vitals/vitals_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 12 wearables — patient daily view. Trust/behaviour with a fake repo:
///   - a connected patient sees their raw daily figures + workouts;
///   - with nothing connected, the view is a connect prompt (never fabricated
///     numbers), and no doctor/sharing surface appears (that is Phase 13).
class _FakeVitalsRepo implements VitalsRepository {
  _FakeVitalsRepo({required this.connected});
  final bool connected;

  int? bpSys;
  int? bpDia;

  @override
  bool get anyConnected => connected;

  @override
  Future<void> recordBloodPressure(int systolic, int diastolic) async {
    bpSys = systolic;
    bpDia = diastolic;
  }

  @override
  Future<List<VitalsConnection>> connections() async => [
        for (final p in WearableProvider.values)
          VitalsConnection(
              provider: p,
              connected: connected && p == WearableProvider.healthConnect),
      ];

  @override
  Future<void> connect(WearableProvider provider) async {}
  @override
  Future<void> disconnect(WearableProvider provider) async {}

  @override
  Future<DailyVitals> today() async => DailyVitals(
        steps: 6420,
        activeMinutes: 22,
        calories: 380,
        restingHr: 62,
        sleepMinutes: 400,
        spo2: 97,
        streakDays: 4,
        bpSystolic: bpSys,
        bpDiastolic: bpDia,
      );

  @override
  Future<List<MetricPoint>> weekTrend(String metric) async =>
      [MetricPoint(DateTime(2026, 7, 20), 7200)];

  @override
  Future<List<WorkoutSummary>> recentWorkouts() async => [
        WorkoutSummary(
          type: 'Walking',
          startedAt: DateTime.now().subtract(const Duration(hours: 2)),
          durationMin: 32,
          distanceM: 2400,
        ),
      ];
}

Widget _harness(_FakeVitalsRepo repo) => ProviderScope(
      overrides: [vitalsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: VitalsTab()),
      ),
    );

void main() {
  testWidgets('connected patient sees raw daily figures + a workout', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness(_FakeVitalsRepo(connected: true)));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('6.4k'), findsOneWidget); // steps ring, compacted
    expect(find.text('4-day streak'), findsOneWidget);
    expect(find.text('Walking'), findsOneWidget);
    // Non-diagnostic boundary is stated to the patient.
    expect(find.textContaining('not a diagnostic measurement'), findsOneWidget);
  });

  testWidgets('no connection → connect prompt, never fabricated numbers',
      (tester) async {
    await tester.pumpWidget(_harness(_FakeVitalsRepo(connected: false)));
    await tester.pumpAndSettle();

    expect(find.text('Connect a tracker'), findsOneWidget);
    expect(find.text('6.4k'), findsNothing);
  });

  // P14: manual BP entry records and shows the reading.
  testWidgets('logging blood pressure records it and shows the reading',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeVitalsRepo(connected: true);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log blood pressure'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Systolic'), '120');
    await tester.enterText(find.widgetWithText(TextField, 'Diastolic'), '80');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.bpSys, 120);
    expect(repo.bpDia, 80);
    expect(find.text('120/80'), findsOneWidget);
  });
}
