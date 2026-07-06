import 'dart:async';

import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/doctor/doctor_models.dart';
import 'package:carebridge/features/doctor/live_queue_screen.dart';
import 'package:carebridge/features/doctor/queue_repository.dart';
import 'package:carebridge/shared/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 10 — live queue widget tests with a fake repository:
/// entries render with tokens; check-in assigns the next token; "Call next"
/// promotes the lowest waiting token; a Realtime change signal refetches;
/// admin scope shows the clinic-wide view without "Call next".
class _FakeQueue implements QueueRepository {
  _FakeQueue(this.entries);
  final List<QueueEntry> entries;
  final changesController = StreamController<void>.broadcast();
  int _nextToken = 1;

  QueueEntry _copy(QueueEntry e, {String? status, int? queuePosition}) =>
      QueueEntry(
        appointmentId: e.appointmentId,
        patientName: e.patientName,
        scheduledTime: e.scheduledTime,
        status: status ?? e.status,
        queuePosition: queuePosition ?? e.queuePosition,
        doctorId: e.doctorId,
        doctorName: e.doctorName,
      );

  @override
  Future<List<QueueEntry>> liveQueue() async => List.of(entries);

  @override
  Future<int> checkIn(String appointmentId) async {
    final i = entries.indexWhere((e) => e.appointmentId == appointmentId);
    final token = _nextToken++;
    entries[i] = _copy(entries[i], status: 'waiting', queuePosition: token);
    return token;
  }

  @override
  Future<String?> callNext() async {
    final current = entries.indexWhere((e) => e.status == 'in_consultation');
    if (current >= 0) entries[current] = _copy(entries[current], status: 'completed');
    final waiting = entries.where((e) => e.status == 'waiting').toList()
      ..sort((a, b) => (a.queuePosition ?? 0).compareTo(b.queuePosition ?? 0));
    if (waiting.isEmpty) return null;
    final i = entries.indexWhere((e) => e.appointmentId == waiting.first.appointmentId);
    entries[i] = _copy(entries[i], status: 'in_consultation');
    return entries[i].appointmentId;
  }

  @override
  Stream<void> changes() => changesController.stream;
}

QueueEntry _entry(String id, String name,
        {String status = 'scheduled', int? token, String doctor = 'Dr One'}) =>
    QueueEntry(
      appointmentId: id,
      patientName: name,
      scheduledTime: DateTime.now(),
      status: status,
      queuePosition: token,
      doctorId: 'd1',
      doctorName: doctor,
    );

Widget _app(QueueRepository repo, DoctorScope scope) => ProviderScope(
      overrides: [queueRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light, home: LiveQueueScreen(scope: scope)),
    );

void main() {
  const doctorScope =
      DoctorScope(role: ActiveRole.doctor, clinicId: 'c1', doctorId: 'd1', paid: true);
  const adminScope = DoctorScope(role: ActiveRole.admin, clinicId: 'c1', paid: true);

  testWidgets('doctor queue: check-in assigns token, call next promotes lowest',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeQueue([
      _entry('a1', 'Asha Rao'),
      _entry('a2', 'Bilal Khan'),
    ]);
    await tester.pumpWidget(_app(repo, doctorScope));
    await tester.pumpAndSettle();

    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('Check in'), findsNWidgets(2));

    // Check both in — sequential tokens.
    await tester.tap(find.text('Check in').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('token 1'), findsOneWidget);
    await tester.tap(find.text('Check in').first);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget); // token avatars
    expect(find.text('2'), findsOneWidget);

    // Call next: token 1 goes in.
    await tester.tap(find.text('Call next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('In consultation'), findsOneWidget);

    // Again: token 1 done, token 2 in.
    await tester.tap(find.text('Call next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Done'), findsOneWidget);
  });

  testWidgets('a Realtime change signal refetches the queue', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeQueue([_entry('a1', 'Asha Rao')]);
    await tester.pumpWidget(_app(repo, doctorScope));
    await tester.pumpAndSettle();
    expect(find.text('Chitra Nair'), findsNothing);

    // A new booking lands (as if another session inserted it) + change event.
    repo.entries.add(_entry('a9', 'Chitra Nair'));
    repo.changesController.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Chitra Nair'), findsOneWidget);
  });

  testWidgets('admin scope: clinic-wide view, doctor names shown, no Call next',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeQueue([
      _entry('a1', 'Asha Rao', doctor: 'Dr One'),
      _entry('a3', 'Deepak Iyer', doctor: 'Dr Two'),
    ]);
    await tester.pumpWidget(_app(repo, adminScope));
    await tester.pumpAndSettle();

    expect(find.text('Clinic queue — all doctors'), findsOneWidget);
    expect(find.textContaining('Dr One'), findsOneWidget);
    expect(find.textContaining('Dr Two'), findsOneWidget);
    // Front desk can check in, but never calls the next patient.
    expect(find.text('Check in'), findsNWidgets(2));
    expect(find.text('Call next'), findsNothing);
  });
}
