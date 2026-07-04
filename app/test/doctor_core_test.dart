import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/doctor/doctor_models.dart';
import 'package:carebridge/features/doctor/doctor_repository.dart';
import 'package:carebridge/features/doctor/doctor_workspace_screen.dart';
import 'package:carebridge/features/summary/summary_models.dart';
import 'package:carebridge/features/summary/summary_repository.dart';
import 'package:carebridge/shared/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 4 doctor-core tests with a fake repository (no network). The fake
/// simulates the RLS row-scoping that the real DB enforces, so the widget tests
/// assert the same trust guarantees at the app layer:
///   - doctor-scoped search excludes other doctors' patients;
///   - admin-scoped search sees all clinic patients;
///   - a visit write is rejected when the scope has no doctor identity (AC-9).
class _FakeDoctorRepo implements DoctorRepository {
  _FakeDoctorRepo();

  final List<({String id, String name, String phone, String owningDoctorId, String clinicId})>
      patients = [
    (id: 'p1', name: 'Asha Rao', phone: '+910000000001', owningDoctorId: 'doc1', clinicId: 'c1'),
    (id: 'p2', name: 'Bilal Khan', phone: '+910000000002', owningDoctorId: 'doc2', clinicId: 'c1'),
  ];

  // Captures the scope a search ran under, so the test can simulate RLS.
  DoctorScope? scope;
  final List<({String patientId, String doctorId})> writes = [];

  @override
  Future<List<PatientSearchResult>> searchPatients(String query) async {
    final s = scope!;
    // Simulated RLS: doctor-scoped sees only its own patients; admin sees all
    // patients in its clinic (AC-8).
    final visible = patients.where((p) {
      if (s.role == ActiveRole.admin) return p.clinicId == s.clinicId;
      return p.owningDoctorId == s.doctorId;
    });
    final q = query.trim().toLowerCase();
    return visible
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .map((p) => PatientSearchResult(id: p.id, name: p.name, phone: p.phone))
        .toList();
  }

  @override
  Future<List<VisitRecord>> patientHistory(String patientId) async => const [];

  @override
  Future<void> addVisit({
    required String patientId,
    required String doctorId,
    required String clinicId,
    required NewVisit visit,
  }) async {
    writes.add((patientId: patientId, doctorId: doctorId));
  }

  @override
  Future<String> redeemConsentCode(String code) async => 'p1';

  @override
  Future<List<PatientSearchResult>> lookupForRequest(String query) async => const [];

  @override
  Future<void> requestAccess(String patientId) async {}

  // Audit fix M2: opening a patient record must be logged (Section 10).
  final List<({String patientId, String what})> viewLogs = [];

  @override
  Future<void> logView(String patientId, String what) async {
    viewLogs.add((patientId: patientId, what: what));
  }
}

// Inert summary repo: the detail view's Summary tab (Phase 7) mounts on open,
// so it needs an override; these tests don't exercise it.
class _StubSummaryRepo implements SummaryRepository {
  @override
  Future<SafetyBanner> banner(String patientId) async => const SafetyBanner();
  @override
  Future<AiSummaryResult> generate(String patientId) async =>
      const AiSummaryResult(banner: SafetyBanner());
}

Widget _harness(_FakeDoctorRepo repo, DoctorScope scope) {
  repo.scope = scope;
  return ProviderScope(
    overrides: [
      doctorRepositoryProvider.overrideWithValue(repo),
      summaryRepositoryProvider.overrideWithValue(_StubSummaryRepo()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: DoctorWorkspaceScreen(scope: scope),
    ),
  );
}

void main() {
  const doctorScope = DoctorScope(role: ActiveRole.doctor, clinicId: 'c1', doctorId: 'doc1');
  const adminScope = DoctorScope(role: ActiveRole.admin, clinicId: 'c1');

  testWidgets('doctor-scoped search excludes other doctors\' patients', (tester) async {
    await tester.pumpWidget(_harness(_FakeDoctorRepo(), doctorScope));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Asha Rao'), findsOneWidget); // own patient
    expect(find.text('Bilal Khan'), findsNothing); // other doctor's patient
  });

  testWidgets('admin-scoped search sees all clinic patients', (tester) async {
    await tester.pumpWidget(_harness(_FakeDoctorRepo(), adminScope));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('Bilal Khan'), findsOneWidget);
  });

  testWidgets('admin-only scope cannot author a visit (AC-9)', (tester) async {
    final repo = _FakeDoctorRepo();
    await tester.pumpWidget(_harness(repo, adminScope));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha Rao'));
    await tester.pumpAndSettle();

    // M2: opening the record wrote an access-log entry (Section 10).
    expect(repo.viewLogs.single.patientId, 'p1');

    // The "Add visit" tab shows the AC-9 lock, not a writable form.
    await tester.tap(find.text('Add visit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('requires a specific doctor identity'), findsOneWidget);
    expect(find.text('Save visit'), findsNothing);
    expect(repo.writes, isEmpty);
  });

  testWidgets('doctor scope can author a visit under its own identity', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeDoctorRepo();
    await tester.pumpWidget(_harness(repo, doctorScope));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha Rao'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add visit'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Diagnosis'), 'Seasonal allergic rhinitis');
    await tester.tap(find.text('Save visit'));
    await tester.pumpAndSettle();

    expect(repo.writes, hasLength(1));
    expect(repo.writes.single.doctorId, 'doc1');
    expect(repo.writes.single.patientId, 'p1');
  });
}
