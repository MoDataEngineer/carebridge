import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/patient/book_appointment_tab.dart';
import 'package:carebridge/features/patient/patient_models.dart';
import 'package:carebridge/features/patient/patient_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Clinic-first booking (founder enhancement 2026-07-06): the patient picks
/// the hospital/clinic FIRST, then sees only that clinic's doctors (with
/// specialty), then requests the appointment.
class _FakeRepo implements PatientRepository {
  BookableDoctor? booked;

  static const doctors = [
    BookableDoctor(
        doctorId: 'd1',
        clinicId: 'c1',
        doctorName: 'Dr Priya Sharma',
        clinicName: 'Sunrise Family Clinic',
        specialty: 'Cardiology'),
    BookableDoctor(
        doctorId: 'd2',
        clinicId: 'c1',
        doctorName: 'Dr Arjun Mehta',
        clinicName: 'Sunrise Family Clinic',
        specialty: 'Paediatrics'),
    BookableDoctor(
        doctorId: 'd3',
        clinicId: 'c2',
        doctorName: 'Dr Ravi Kumar',
        clinicName: 'QuickCare Clinic',
        specialty: 'Family Medicine'),
  ];

  @override
  Future<List<BookableDoctor>> bookableDoctors() async => doctors;

  @override
  Future<List<AppointmentRecord>> appointments() async => const [];

  @override
  Future<AppointmentRecord> bookAppointment(
      {required BookableDoctor doctor, required DateTime when}) async {
    booked = doctor;
    return AppointmentRecord(
        id: 'a1', scheduledTime: when, status: 'scheduled');
  }

  @override
  Future<PatientProfile> loadProfile() async => throw UnimplementedError();

  @override
  Future<PatientProfile> saveProfile(PatientProfile profile) async =>
      throw UnimplementedError();

  @override
  Future<List<VisitRecord>> visitHistory() async => const [];
}

void main() {
  testWidgets('clinic first, then only that clinic\'s doctors, then book',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [patientRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: BookAppointmentTab())),
    ));
    await tester.pumpAndSettle();

    // No doctors offered before a clinic is chosen.
    expect(find.text('Pick a hospital first'), findsOneWidget);
    expect(find.textContaining('Dr Priya'), findsNothing);

    // Step 1: choose the hospital.
    await tester.tap(find.text('Hospital / clinic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunrise Family Clinic').last);
    await tester.pumpAndSettle();

    // Step 2: only Sunrise doctors appear, with specialties; no QuickCare.
    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();
    expect(find.text('Dr Priya Sharma · Cardiology'), findsOneWidget);
    expect(find.text('Dr Arjun Mehta · Paediatrics'), findsOneWidget);
    expect(find.textContaining('Dr Ravi Kumar'), findsNothing);
    await tester.tap(find.text('Dr Priya Sharma · Cardiology').last);
    await tester.pumpAndSettle();

    // Step 3: request the appointment.
    await tester.tap(find.text('Request appointment'));
    await tester.pumpAndSettle();
    expect(repo.booked?.doctorId, 'd1');
    expect(find.text('Appointment requested'), findsOneWidget);
  });

  testWidgets('switching clinic clears the picked doctor', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [patientRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: BookAppointmentTab())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hospital / clinic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunrise Family Clinic').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr Priya Sharma · Cardiology').last);
    await tester.pumpAndSettle();

    // Change hospital — the doctor choice must reset, booking must not
    // silently carry the old doctor.
    await tester.tap(find.text('Sunrise Family Clinic').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('QuickCare Clinic').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request appointment'));
    await tester.pumpAndSettle();
    expect(repo.booked, isNull);
    expect(find.text('Pick a doctor first'), findsOneWidget);
  });
}
