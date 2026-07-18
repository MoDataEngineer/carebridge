import 'dart:async';

import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/notifications/notifications_controller.dart';
import 'package:carebridge/features/notifications/notifications_repository.dart';
import 'package:carebridge/features/patient/patient_home_screen.dart';
import 'package:carebridge/features/patient/patient_models.dart';
import 'package:carebridge/features/patient/patient_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gap B — the bell shows a live unread badge and opening the feed clears it.
/// The feed comes from a controllable stream standing in for Supabase Realtime.
class _MinimalPatientRepo implements PatientRepository {
  @override
  Future<PatientProfile> loadProfile() async =>
      const PatientProfile(id: 'p1', name: 'Asha', phone: '+91');
  @override
  Future<PatientProfile> saveProfile(PatientProfile p) async => p;
  @override
  Future<List<VisitRecord>> visitHistory() async => const [];
  @override
  Future<List<AppointmentRecord>> appointments() async => const [];
  @override
  Future<List<BookableDoctor>> bookableDoctors() async => const [];
  @override
  Future<List<AvailableSession>> availableSessions(String d, DateTime t) async =>
      const [];
  @override
  Future<BookingResult> requestAppointment(String s, DateTime d) async =>
      const BookingResult(status: 'scheduled', booked: 1, capacity: 20);
  @override
  Stream<void> appointmentChanges() => const Stream.empty();
  @override
  Future<NowServing?> nowServing(String d) async => null;
}

PatientNotification _notif(String id, String type, DateTime at) =>
    PatientNotification(id: id, type: type, payload: const {}, sentAt: at);

void main() {
  testWidgets('bell badges new notifications and clears when the feed opens',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final feed = StreamController<List<PatientNotification>>.broadcast();
    addTearDown(feed.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        patientRepositoryProvider.overrideWithValue(_MinimalPatientRepo()),
        notificationsFeedProvider.overrideWith((ref) => feed.stream),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const PatientHomeScreen()),
    ));
    feed.add(const []); // initial snapshot: nothing yet
    await tester.pumpAndSettle();

    // No unread → no badge label.
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsNothing);

    // A check-in notification arrives (Realtime event) → badge shows 1.
    final t1 = DateTime.now();
    feed.add([_notif('n1', 'checked_in', t1)]);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsOneWidget);

    // Opening the feed marks it seen; the screen lists the message live.
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.textContaining('checked in'), findsOneWidget);

    // Back home: badge cleared.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsNothing);

    // A second arrival AFTER marking seen badges again — the "your turn" case.
    // n1 keeps its ORIGINAL (pre-seen) timestamp, so only n2 is unread.
    feed.add([
      _notif('n2', 'your_turn', DateTime.now().add(const Duration(seconds: 1))),
      _notif('n1', 'checked_in', t1),
    ]);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsOneWidget);
  });
}
