import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/doctor/follow_ups_screen.dart';
import 'package:carebridge/features/doctor/paid_tools_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 9 — follow-up tracker widget tests with a fake repository:
/// due/overdue rows render; one-tap reminder calls the (DB-gated) rpc;
/// mark-done removes the row.
class _FakePaidTools implements PaidToolsRepository {
  _FakePaidTools(this.items);
  final List<FollowUpItem> items;
  final List<String> reminded = [];
  final List<String> completed = [];

  @override
  Future<List<FollowUpItem>> followUps() async =>
      items.where((f) => !completed.contains(f.visitId)).toList();

  @override
  Future<void> sendFollowUpReminder(String visitId) async => reminded.add(visitId);

  @override
  Future<void> markFollowUpDone(String visitId) async => completed.add(visitId);

  @override
  Future<List<String>> myDrugNames() async => const ['Metformin', 'Paracetamol'];

  @override
  Future<List<RxTemplate>> templates() async => const [];

  @override
  Future<void> saveTemplate(String name, List<Map<String, dynamic>> items) async {}

  @override
  Future<void> deleteTemplate(String id) async {}
}

void main() {
  testWidgets('tracker lists due/overdue, sends reminder, marks done', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakePaidTools([
      FollowUpItem(
        visitId: 'v1',
        patientId: 'p1',
        patientName: 'Asha Rao',
        diagnosis: 'Type 2 diabetes',
        dueDate: DateTime.now().subtract(const Duration(days: 2)), // overdue
      ),
      FollowUpItem(
        visitId: 'v2',
        patientId: 'p2',
        patientName: 'Bilal Khan',
        diagnosis: 'Hypertension',
        dueDate: DateTime.now().add(const Duration(days: 3)),
      ),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [paidToolsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light, home: const FollowUpsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget); // v1 flagged overdue
    expect(find.text('Bilal Khan'), findsOneWidget);

    // One-tap reminder on the first card.
    await tester.tap(find.text('Send reminder').first);
    await tester.pumpAndSettle();
    expect(repo.reminded, ['v1']);
    expect(find.textContaining('Reminder sent to Asha Rao'), findsOneWidget);

    // Mark done removes the row.
    await tester.tap(find.text('Mark done').first);
    await tester.pumpAndSettle();
    expect(repo.completed, ['v1']);
    expect(find.text('Asha Rao'), findsNothing);
    expect(find.text('Bilal Khan'), findsOneWidget);
  });
}
