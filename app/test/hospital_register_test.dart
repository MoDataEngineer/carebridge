import 'package:carebridge/core/routing/app_router.dart';
import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/auth/clinic/clinic_auth_repository.dart';
import 'package:carebridge/features/auth/clinic/clinic_models.dart';
import 'package:carebridge/features/auth/clinic/manage_doctors_screen.dart';
import 'package:carebridge/features/auth/clinic/roster_repository.dart';
import 'package:carebridge/shared/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hospital self-registration flow (founder decision 2026-07-04):
///   - entry button says "Hospital";
///   - a new hospital registers (name + reg number + admin PIN) and lands on
///     "Who are you?" with the empty-roster guidance + Admin tile;
///   - the manage-doctors screen adds a doctor (ID-4 fields + PIN).
class _FakeAuthRepo implements ClinicAuthRepository {
  String? registeredName;

  @override
  Future<ClinicLoginResult> login({
    required String phone,
    String? otpCode,
  }) async =>
      throw UnimplementedError();

  @override
  Future<ClinicLoginResult> register({
    required String name,
    required String registrationNumber,
    required String phone,
    required String state,
    required String city,
    required String adminPin,
    String? address,
  }) async {
    registeredName = name;
    return ClinicLoginResult(
      clinicId: 'clinic-new',
      clinicName: name,
      baseToken: 'base',
      doctors: const [],
    );
  }

  @override
  Future<ScopedSession> mintScope({
    required String clinicId,
    required ActiveRole role,
    String? doctorId,
    required String pin,
  }) async =>
      ScopedSession(
        clinicId: clinicId,
        role: role,
        doctorId: doctorId,
        accessToken: 'scoped',
        expiresIn: 2700,
      );
}

class _FakeRosterRepo implements RosterRepository {
  final List<DoctorSummary> roster = [];

  @override
  Future<List<DoctorSummary>> listDoctors({bool includeInactive = false}) async =>
      includeInactive ? List.of(roster) : roster.where((d) => d.isActive).toList();

  @override
  Future<DoctorSummary> addDoctor({
    required String name,
    required String councilRegNumber,
    required String councilName,
    required String specialty,
    String? hprId,
    required String pin,
    String? phone,
  }) async {
    final d = DoctorSummary(
      id: 'doc-${roster.length + 1}',
      name: name,
      specialty: specialty,
      councilRegNumber: councilRegNumber,
      councilName: councilName,
      hprId: hprId,
      phone: phone,
    );
    roster.add(d);
    return d;
  }

  @override
  Future<DoctorSummary> updateDoctor({
    required String doctorId,
    required String name,
    required String councilRegNumber,
    required String councilName,
    required String specialty,
    String? hprId,
    String? phone,
    String? pin,
  }) async {
    final i = roster.indexWhere((d) => d.id == doctorId);
    final updated = DoctorSummary(
      id: doctorId,
      name: name,
      specialty: specialty,
      councilRegNumber: councilRegNumber,
      councilName: councilName,
      hprId: hprId,
      phone: phone,
      isActive: roster[i].isActive,
    );
    roster[i] = updated;
    return updated;
  }

  @override
  Future<void> setDoctorActive(String doctorId, bool active) async {
    final i = roster.indexWhere((d) => d.id == doctorId);
    final d = roster[i];
    roster[i] = DoctorSummary(
      id: d.id,
      name: d.name,
      specialty: d.specialty,
      councilRegNumber: d.councilRegNumber,
      councilName: d.councilName,
      hprId: d.hprId,
      phone: d.phone,
      isActive: active,
    );
  }
}

void main() {
  testWidgets('entry shows Hospital; registration lands on empty-roster picker',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = _FakeAuthRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [clinicAuthRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: createAppRouter()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Hospital / Doctor'), findsOneWidget);
    await tester.tap(find.text('Hospital / Doctor'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New hospital? Register here'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Hospital / clinic name'), 'Lotus Care');
    await tester.enterText(
        find.widgetWithText(TextField, 'Hospital registration / license number'),
        'KA-2026-778');
    await tester.enterText(
        find.widgetWithText(TextField, 'Mobile number'), '9876543210');
    // State + city are required (2026-07-06 — patients filter by place).
    await tester.tap(find.text('State'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karnataka').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'City / town'), 'Mysuru');
    await tester.enterText(
        find.widgetWithText(TextField, 'Set an Admin PIN (4–6 digits)'), '5566');
    await tester.tap(find.text('Register hospital'));
    await tester.pumpAndSettle();

    expect(auth.registeredName, 'Lotus Care');
    // Landed on the picker with the empty-roster guidance + Admin tile only.
    expect(find.text('Who are you?'), findsOneWidget);
    expect(find.textContaining('No doctors yet'), findsOneWidget);
    expect(find.text('Clinic Admin / View All'), findsOneWidget);
  });

  testWidgets('manage doctors adds a doctor with ID-4 fields + PIN', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final roster = _FakeRosterRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rosterRepositoryProvider.overrideWithValue(roster),
        // ManageDoctorsScreen syncs the session roster via the controller,
        // which depends on the auth repo — stub it.
        clinicAuthRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ManageDoctorsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No doctors yet'), findsOneWidget);
    await tester.tap(find.text('Add doctor'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Doctor name'), 'Dr Meera Nair');
    await tester.enterText(
        find.widgetWithText(TextField, 'Medical council registration number'), 'MC-99');
    await tester.enterText(
        find.widgetWithText(TextField, 'Council name (e.g. NMC)'), 'NMC');
    await tester.enterText(find.widgetWithText(TextField, 'Specialty'), 'Pediatrics');
    await tester.enterText(
        find.widgetWithText(TextField, 'Doctor PIN (4–6 digits)'), '7788');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(roster.roster.single.name, 'Dr Meera Nair');
    expect(find.textContaining('Could not add doctor'), findsNothing);
    expect(find.text('Dr Meera Nair'), findsOneWidget);
    // Subtitle now also hints at the avatar photo upload (branding).
    expect(find.textContaining('Pediatrics'), findsOneWidget);
  });

  testWidgets('admin can edit a doctor and deactivate (soft delete) then restore',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final roster = _FakeRosterRepo()
      ..roster.add(const DoctorSummary(
          id: 'doc-1', name: 'Dr Meera Nair', specialty: 'Pediatrics',
          councilRegNumber: 'MC-99', councilName: 'NMC'));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        rosterRepositoryProvider.overrideWithValue(roster),
        clinicAuthRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ManageDoctorsScreen()),
    ));
    await tester.pumpAndSettle();

    // --- Edit: change the specialty ---
    await tester.tap(find.byTooltip('Doctor options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Specialty'), 'Cardiology');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(roster.roster.single.specialty, 'Cardiology');
    expect(find.textContaining('Cardiology'), findsOneWidget);

    // --- Deactivate (confirmed) — soft delete, doctor stays in the list muted ---
    await tester.tap(find.byTooltip('Doctor options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(roster.roster.single.isActive, isFalse);
    expect(find.text('Deactivated'), findsOneWidget);

    // --- Restore ---
    await tester.tap(find.byTooltip('Doctor options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore doctor'));
    await tester.pumpAndSettle();
    expect(roster.roster.single.isActive, isTrue);
    expect(find.text('Deactivated'), findsNothing);
  });
}
