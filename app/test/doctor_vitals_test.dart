import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/vitals/doctor_vitals_repository.dart';
import 'package:carebridge/features/vitals/doctor_vitals_tab.dart';
import 'package:carebridge/features/vitals/vitals_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 13 doctor vitals view — trust/behaviour with a fake repo:
///   - when the patient hasn't shared (repo throws), a "not shared" state shows,
///     never fabricated data;
///   - when shared, raw trends + the advice-vs-actual overlay render.
class _NotSharedRepo implements DoctorVitalsRepository {
  @override
  Future<PatientVitalsView> forPatient(String patientId) async =>
      throw VitalsNotSharedException();
}

class _SharedRepo implements DoctorVitalsRepository {
  @override
  Future<PatientVitalsView> forPatient(String patientId) async {
    final now = DateTime.now();
    List<MetricPoint> s(List<double> v) => [
          for (var i = 0; i < v.length; i++)
            MetricPoint(now.subtract(Duration(days: v.length - 1 - i)), v[i]),
        ];
    return PatientVitalsView(
      daily: {
        'steps': s([7200, 5400, 9100, 6800, 4300, 8800, 6420]),
        'active_minutes': s([35, 20, 40, 25, 10, 45, 22]),
      },
      workouts: const [],
      advice: VisitAdvice(
        activityMinutesTarget: 30,
        daysPerWeek: 5,
        note: 'Brisk walk',
        visitDate: now.subtract(const Duration(days: 12)),
      ),
    );
  }
}

Widget _harness(DoctorVitalsRepository repo) => ProviderScope(
      overrides: [doctorVitalsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: DoctorVitalsTab(patientId: 'p1')),
      ),
    );

void main() {
  testWidgets('no wearable share → "not shared", never fabricated data',
      (tester) async {
    await tester.pumpWidget(_harness(_NotSharedRepo()));
    await tester.pumpAndSettle();

    expect(find.text('Vitals not shared'), findsOneWidget);
    expect(find.textContaining('This week'), findsNothing);
  });

  testWidgets('shared → raw trends + advice-vs-actual overlay', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness(_SharedRepo()));
    await tester.pumpAndSettle();

    expect(find.text('FOLLOW-UP ON ADVICE'), findsOneWidget);
    expect(find.textContaining('30 min activity × 5/week'), findsOneWidget);
    // 3 of the 7 demo days meet the 30-min target (35, 40, 45).
    expect(find.textContaining('of 5 days met this week'), findsOneWidget);
    expect(find.textContaining('not a diagnostic measurement'), findsOneWidget);
  });
}
