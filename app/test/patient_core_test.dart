import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/patient/patient_home_screen.dart';
import 'package:carebridge/shared/widgets/brand_avatar.dart';
import 'package:carebridge/features/patient/patient_models.dart';
import 'package:carebridge/features/patient/patient_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3 patient-core tests with a fake repository (no network). Covers:
///  - profile loads structured fields and saves edits;
///  - history is read-only (shows clinical records, offers no edit control);
///  - booking creates an appointment that then appears in the list.
class _FakePatientRepo implements PatientRepository {
  _FakePatientRepo();

  PatientProfile? savedProfile;
  final List<AppointmentRecord> _appts = [];

  @override
  Future<PatientProfile> loadProfile() async => const PatientProfile(
        id: 'p1',
        name: 'Asha',
        phone: '+910000000001',
        allergies: ['Penicillin'],
        chronicConditions: ['Asthma'],
        currentMedications: [],
      );

  @override
  Future<PatientProfile> saveProfile(PatientProfile profile) async {
    savedProfile = profile;
    return profile;
  }

  @override
  Future<List<VisitRecord>> visitHistory() async => [
        VisitRecord(
          id: 'v1',
          visitDate: DateTime(2026, 1, 10),
          diagnosis: 'Seasonal allergic rhinitis',
          notes: 'Advised antihistamine',
          prescriptions: const [
            PrescriptionRecord(
              drugName: 'Cetirizine',
              dosage: '10mg',
              schedule: {'morning': false, 'afternoon': false, 'night': true},
              durationDays: 7,
            ),
          ],
        ),
      ];

  @override
  Future<List<AppointmentRecord>> appointments() async => List.of(_appts);

  @override
  Future<List<BookableDoctor>> bookableDoctors() async => const [
        BookableDoctor(
          doctorId: 'd1',
          clinicId: 'c1',
          doctorName: 'Dr Rao',
          clinicName: 'City Clinic',
        ),
      ];

  @override
  Future<List<AvailableSession>> availableSessions(
          String doctorId, DateTime date) async =>
      const [
        AvailableSession(
            sessionId: 's1',
            label: 'Morning',
            startTime: '09:00:00',
            endTime: '12:00:00',
            capacity: 20,
            booked: 0),
      ];

  @override
  Future<BookingResult> requestAppointment(String sessionId, DateTime date) async {
    _appts.add(AppointmentRecord(
      id: 'a${_appts.length + 1}',
      scheduledTime: date,
      status: 'scheduled',
    ));
    return const BookingResult(status: 'scheduled', booked: 1, capacity: 20);
  }

  @override
  Stream<void> appointmentChanges() => const Stream.empty();

  @override
  Future<NowServing?> nowServing(String doctorId) async => null;
}

Widget _harness(_FakePatientRepo repo) => ProviderScope(
      overrides: [patientRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const PatientHomeScreen(),
      ),
    );

void main() {
  testWidgets('profile loads structured fields and saves edits', (tester) async {
    // Tall surface so the whole scrolling form (incl. the Save button at the
    // bottom) is built and laid out.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakePatientRepo();
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    // Profile now lives behind the Home header avatar (not a bottom tab).
    await tester.tap(find.byType(BrandAvatar));
    await tester.pumpAndSettle();

    // Existing structured data is shown as chips.
    expect(find.widgetWithText(Chip, 'Penicillin'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Asthma'), findsOneWidget);

    // Add a current medication and save.
    await tester.enterText(
        find.widgetWithText(TextField, 'Add current medications…'), 'Salbutamol');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();

    expect(repo.savedProfile, isNotNull);
    expect(repo.savedProfile!.currentMedications, contains('Salbutamol'));
  });

  testWidgets('history tab is read-only and shows clinical records', (tester) async {
    await tester.pumpWidget(_harness(_FakePatientRepo()));
    await tester.pumpAndSettle();

    // 'History' now appears both as a Home quick-tile and the nav label —
    // tap the bottom-nav destination by its (unselected) icon to disambiguate.
    await tester.tap(find.byIcon(Icons.history_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('Seasonal allergic rhinitis'), findsOneWidget);
    expect(find.textContaining('Cetirizine'), findsOneWidget);
    // Read-only: no save/edit affordance on this tab.
    expect(find.text('Save profile'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('booking an appointment adds it to the list', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness(_FakePatientRepo()));
    await tester.pumpAndSettle();

    // Custom pill nav shows a label only on the active tab — switch to Book by
    // its (unselected) icon.
    await tester.tap(find.byIcon(Icons.event_outlined));
    await tester.pumpAndSettle();
    expect(find.text('No appointments yet.'), findsOneWidget);

    // Clinic-first flow (2026-07-06): pick the hospital, then the doctor.
    await tester.tap(find.text('Hospital / clinic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('City Clinic').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<BookableDoctor>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr Rao').last);
    await tester.pumpAndSettle();

    // Sessions load on doctor selection — pick one, then request.
    await tester.tap(find.textContaining('Morning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request appointment'));
    await tester.pumpAndSettle();

    expect(find.text('No appointments yet.'), findsNothing);
    expect(find.textContaining('Status: scheduled'), findsOneWidget);
  });
}
