import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/auth/clinic/clinic_auth_repository.dart';
import 'package:carebridge/features/auth/clinic/clinic_models.dart';
import 'package:carebridge/features/doctor/appointments_repository.dart';
import 'package:carebridge/features/doctor/appointments_screen.dart';
import 'package:carebridge/shared/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Founder 2026-07-18: an over-capacity request reportedly showed as Pending
/// with no Approve/Decline. Pins the contract: a 'requested' row renders the
/// Pending pill WITH both actions, and Approve calls through.
class _FakeApptsRepo implements AppointmentsRepository {
  _FakeApptsRepo(this.items);
  final List<UpcomingAppointment> items;
  String? approved;
  String? rejected;

  @override
  Future<List<UpcomingAppointment>> upcoming() async => items;
  @override
  Future<void> approve(String id) async => approved = id;
  @override
  Future<void> reject(String id, {String? reason}) async => rejected = id;
  @override
  Stream<void> changes() => const Stream.empty();
}

/// The screen watches the clinic session (for the "My availability" button);
/// this fake keeps the provider chain constructible in tests.
class _FakeClinicAuth implements ClinicAuthRepository {
  @override
  Future<ClinicLoginResult> login({required String phone, String? otpCode}) async =>
      const ClinicLoginResult(
          clinicId: 'c1', clinicName: 'Test', baseToken: 'b', doctors: []);
  @override
  Future<ClinicLoginResult> register({
    required String name,
    required String registrationNumber,
    required String phone,
    required String state,
    required String city,
    required String adminPin,
    String? address,
  }) async =>
      const ClinicLoginResult(
          clinicId: 'c1', clinicName: 'Test', baseToken: 'b', doctors: []);
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
          accessToken: 't',
          expiresIn: 2700);
}

UpcomingAppointment _appt(String id, String status, {int daysAhead = 1}) =>
    UpcomingAppointment(
      appointmentId: id,
      patientName: 'Asha Rao',
      doctorId: 'd1',
      doctorName: 'Dr Priya Sharma',
      scheduledTime: DateTime.now().add(Duration(days: daysAhead)),
      sessionLabel: 'Morning',
      status: status,
    );

void main() {
  testWidgets('a requested (overflow) appointment offers Approve and Decline',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeApptsRepo([
      _appt('a1', 'requested'),
      _appt('a2', 'scheduled', daysAhead: 2),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appointmentsRepositoryProvider.overrideWithValue(repo),
        clinicAuthRepositoryProvider.overrideWithValue(_FakeClinicAuth()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const AppointmentsScreen()),
    ));
    await tester.pumpAndSettle();

    // Pending pill AND its actions are all present.
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    // The confirmed row offers Cancel (not Approve).
    expect(find.text('Cancel'), findsOneWidget);

    // Approve calls through to the backend with the right id.
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(repo.approved, 'a1');
  });

  testWidgets('narrow phone width still shows Approve/Decline for a request',
      (tester) async {
    // The founder tests side-by-side windows — half a laptop screen.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeApptsRepo([_appt('a1', 'requested')]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appointmentsRepositoryProvider.overrideWithValue(repo),
        clinicAuthRepositoryProvider.overrideWithValue(_FakeClinicAuth()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const AppointmentsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(tester.takeException(), isNull); // no layout overflow
  });
}
