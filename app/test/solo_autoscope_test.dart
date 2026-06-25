import 'package:carebridge/core/routing/app_router.dart';
import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/auth/clinic/clinic_auth_repository.dart';
import 'package:carebridge/features/auth/clinic/clinic_models.dart';
import 'package:carebridge/shared/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Section 12 trust test (a): a solo doctor (clinic with exactly one doctor) is
/// auto-scoped on login and NEVER sees the "Who are you?" picker; a multi-doctor
/// clinic does. Uses a fake repository so the decision logic is tested without a
/// network or backend.
class _FakeRepo implements ClinicAuthRepository {
  _FakeRepo(this.doctorCount);
  final int doctorCount;

  @override
  Future<ClinicLoginResult> login({
    required String registrationNumber,
    required String phone,
  }) async {
    return ClinicLoginResult(
      clinicId: 'clinic-1',
      clinicName: 'Test Clinic',
      baseToken: 'base',
      doctors: List.generate(
        doctorCount,
        (i) => DoctorSummary(id: 'doc-$i', name: 'Dr ${i + 1}', specialty: 'GP'),
      ),
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

Widget _harness(int doctorCount) => ProviderScope(
      overrides: [
        clinicAuthRepositoryProvider.overrideWithValue(_FakeRepo(doctorCount)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: createAppRouter(),
      ),
    );

Future<void> _loginAsClinic(WidgetTester tester) async {
  await tester.tap(find.text('Doctor'));
  await tester.pumpAndSettle();
  expect(find.text('Clinic sign in'), findsOneWidget);
  await tester.enterText(
      find.widgetWithText(TextField, 'Clinic registration / license number'), 'REG-1');
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('(a) solo clinic auto-scopes and NEVER shows "Who are you?"',
      (tester) async {
    await tester.pumpWidget(_harness(1));
    await tester.pumpAndSettle();

    await _loginAsClinic(tester);

    // Auto-scoped: lands directly on PIN entry, picker never appears.
    expect(find.text('Who are you?'), findsNothing);
    expect(find.text('Enter PIN'), findsOneWidget);
    // And the pending identity was auto-set to the sole doctor.
    expect(find.textContaining('Dr 1'), findsOneWidget);
  });

  testWidgets('multi-doctor clinic DOES show "Who are you?"', (tester) async {
    await tester.pumpWidget(_harness(2));
    await tester.pumpAndSettle();

    await _loginAsClinic(tester);

    // Control case: the picker is shown, PIN is not reached yet.
    expect(find.text('Who are you?'), findsOneWidget);
    expect(find.text('Enter PIN'), findsNothing);
    expect(find.text('Clinic Admin / View All'), findsOneWidget);
  });
}
