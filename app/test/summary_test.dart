import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/summary/summary_models.dart';
import 'package:carebridge/features/summary/summary_repository.dart';
import 'package:carebridge/features/summary/summary_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 7 one-touch AI summary UI tests with a fake repository (no network).
/// Asserts the Section 8 layering rules as user-visible behaviour:
///   - the deterministic safety banner renders IMMEDIATELY, before any AI call;
///   - the narrative appears only after the one-touch generate, and always
///     under the mandatory "AI-generated summary — verify against full record."
///     label, with tap-to-source sentences;
///   - a patient with no structured data gets the plain "nothing to summarize"
///     path instead of an invented narrative.
class _FakeSummaryRepo implements SummaryRepository {
  _FakeSummaryRepo({this.empty = false});

  final bool empty;
  int generateCalls = 0;

  @override
  Future<SafetyBanner> banner(String patientId) async => const SafetyBanner(
        allergies: ['Penicillin'],
        chronicConditions: ['Type 2 diabetes'],
        currentMedications: ['Metformin 500mg'],
      );

  @override
  Future<AiSummaryResult> generate(String patientId) async {
    generateCalls++;
    if (empty) {
      return const AiSummaryResult(
        banner: SafetyBanner(),
        summary: null,
        detail: 'no structured visits or test results yet',
      );
    }
    return const AiSummaryResult(
      banner: SafetyBanner(),
      summary: '3 visits over 6 months for recurring headaches. '
          'Currently on Metformin since January.',
      sources: [
        SentenceSource(sentence: '3 visits over 6 months.', visitId: 'v1'),
        SentenceSource(sentence: 'HbA1c 7.2 on latest test.', testOrderId: 'o1'),
      ],
      cached: false,
    );
  }
}

Widget _harness(_FakeSummaryRepo repo) => ProviderScope(
      overrides: [summaryRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: PatientSummaryTab(patientId: 'p1')),
      ),
    );

void main() {
  testWidgets('safety banner renders immediately without any AI call', (tester) async {
    final repo = _FakeSummaryRepo();
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    // Layer 1 chips are up, deterministic, straight from structured fields.
    expect(find.text('Penicillin'), findsOneWidget);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
    expect(find.text('Metformin 500mg'), findsOneWidget);
    // No narrative and NO AI call yet — one-touch means the doctor asks.
    expect(repo.generateCalls, 0);
    expect(find.textContaining('AI-generated summary'), findsNothing);
    expect(find.text('Generate AI summary'), findsOneWidget);
  });

  testWidgets('one-touch generate shows labelled narrative with sources', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeSummaryRepo();
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate AI summary'));
    await tester.pumpAndSettle();

    expect(repo.generateCalls, 1);
    // Mandatory label (Section 8) shown with the narrative.
    expect(find.text('AI-generated summary — verify against full record.'),
        findsOneWidget);
    expect(find.textContaining('3 visits over 6 months for recurring'),
        findsOneWidget);
    // Tap-to-source sentences are present and tappable.
    expect(find.text('HbA1c 7.2 on latest test.'), findsOneWidget);
    await tester.tap(find.text('HbA1c 7.2 on latest test.'));
    await tester.pump();
    expect(find.textContaining('test order o1'), findsOneWidget);
  });

  testWidgets('no structured data -> plain message, never an invented summary',
      (tester) async {
    final repo = _FakeSummaryRepo(empty: true);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate AI summary'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no structured visits or test results yet'),
        findsOneWidget);
    expect(find.textContaining('AI-generated summary'), findsNothing);
  });
}
