import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/notifications/notifications_repository.dart';
import 'package:carebridge/features/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 8 notification feed tests with a fake repository (no network):
/// each notification type renders its plain-language line; an empty feed
/// shows the empty state.
class _FakeNotificationsRepo implements NotificationsRepository {
  _FakeNotificationsRepo(this.items);
  final List<PatientNotification> items;

  @override
  Future<List<PatientNotification>> feed() async => items;

  @override
  Future<void> registerDeviceToken(String token, String platform) async {}
}

Widget _harness(NotificationsRepository repo) => ProviderScope(
      overrides: [notificationsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light, home: const NotificationsScreen()),
    );

void main() {
  testWidgets('feed renders all four notification types in plain language',
      (tester) async {
    final repo = _FakeNotificationsRepo([
      const PatientNotification(id: 'n1', type: 'appointment_reminder'),
      const PatientNotification(id: 'n2', type: 'follow_up'),
      const PatientNotification(
          id: 'n3', type: 'report_ready', payload: {'test_name': 'HbA1c'}),
      const PatientNotification(id: 'n4', type: 'medication_reminder', payload: {
        'slot': 'morning',
        'drugs': ['Metformin']
      }),
    ]);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Appointment reminder'), findsOneWidget);
    expect(find.textContaining('Follow-up due'), findsOneWidget);
    expect(find.textContaining('HbA1c report is ready'), findsOneWidget);
    expect(find.textContaining('Medication reminder (morning): Metformin'),
        findsOneWidget);
  });

  testWidgets('empty feed shows the empty state', (tester) async {
    await tester.pumpWidget(_harness(_FakeNotificationsRepo(const [])));
    await tester.pumpAndSettle();
    expect(find.text('No notifications yet.'), findsOneWidget);
  });
}
