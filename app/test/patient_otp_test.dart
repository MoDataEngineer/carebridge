import 'package:carebridge/core/config/phone_otp.dart';
import 'package:carebridge/core/routing/app_router.dart';
import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/auth/patient/patient_auth_repository.dart';
import 'package:carebridge/features/auth/patient/patient_auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Phase 11 — patient sign-in with Firebase Phone OTP (faked):
///   - OTP configured: phone -> Send OTP -> code entry -> Verify -> login is
///     called WITH the verified Firebase ID token -> home.
///   - OTP not configured: single-step demo sign-in (no token), banner shown.
class _FakeOtp implements PhoneOtp {
  String? sentTo;
  String? confirmedCode;

  @override
  bool get enabled => true;

  @override
  Future<void> sendCode(String phoneE164) async => sentTo = phoneE164;

  @override
  Future<String> confirm(String smsCode) async {
    confirmedCode = smsCode;
    return 'fake-firebase-token';
  }
}

class _FakeAuth implements PatientAuthRepository {
  String? phone;
  String? token;

  @override
  Future<void> login(String p, {String? firebaseIdToken}) async {
    phone = p;
    token = firebaseIdToken;
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
  testWidgets('OTP flow: send code, verify, login carries the token',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final otp = _FakeOtp();
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(otp: otp, auth: auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Mobile number'), '9000000001');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(otp.sentTo, '+919000000001');

    await tester.enterText(find.widgetWithText(TextField, 'OTP code'), '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(otp.confirmedCode, '123456');
    expect(auth.token, 'fake-firebase-token'); // verified proof reaches login
    expect(find.text('PATIENT_HOME'), findsOneWidget);
  });

  testWidgets('OTP not configured: demo sign-in without token, banner shown',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = _FakeAuth();
    await tester.pumpWidget(_app(otp: DisabledPhoneOtp(), auth: auth));
    await tester.pumpAndSettle();

    expect(find.textContaining('Demo sign-in'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Mobile number'), '9000000001');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(auth.phone, '9000000001');
    expect(auth.token, isNull);
    expect(find.text('PATIENT_HOME'), findsOneWidget);
  });
}
