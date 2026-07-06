import 'package:carebridge/core/config/phone_otp.dart';
import 'package:carebridge/core/routing/app_router.dart';
import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/auth/patient/patient_auth_repository.dart';
import 'package:carebridge/features/auth/patient/patient_auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Phase 11 (D12) — patient sign-in with the Supabase-hosted OTP (faked):
///   - SMS provider configured: phone -> code sent -> code entry -> Verify ->
///     login is called WITH the code -> home.
///   - not configured: sendCode reports false -> single-step demo sign-in
///     (no code) -> home.
class _FakeOtp implements PhoneOtp {
  _FakeOtp(this.configured);
  final bool configured;
  String? sentTo;

  @override
  Future<bool> sendCode(String phone) async {
    if (!configured) return false;
    sentTo = phone;
    return true;
  }
}

class _FakeAuth implements PatientAuthRepository {
  String? phone;
  String? code;

  @override
  Future<void> login(String p, {String? otpCode}) async {
    phone = p;
    code = otpCode;
  }
}

Widget _app({required PhoneOtp otp, required PatientAuthRepository auth}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const PatientAuthScreen()),
    GoRoute(
        path: Routes.patientHome,
        builder: (_, __) => const Scaffold(body: Text('PATIENT_HOME'))),
  ]);
  return ProviderScope(
    overrides: [
      phoneOtpProvider.overrideWithValue(otp),
      patientAuthRepositoryProvider.overrideWithValue(auth),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

void main() {
  testWidgets('OTP flow: send code, verify, login carries the code',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final otp = _FakeOtp(true);
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(otp: otp, auth: auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Mobile number'), '9000000001');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(otp.sentTo, '9000000001');

    await tester.enterText(find.widgetWithText(TextField, 'OTP code'), '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(auth.code, '123456'); // the code reaches the server-side check
    expect(find.text('PATIENT_HOME'), findsOneWidget);
  });

  testWidgets('OTP not configured: demo sign-in without a code',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = _FakeAuth();
    await tester.pumpWidget(_app(otp: _FakeOtp(false), auth: auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Mobile number'), '9000000001');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(auth.phone, '9000000001');
    expect(auth.code, isNull);
    expect(find.text('PATIENT_HOME'), findsOneWidget);
  });
}
