import 'package:carebridge/core/routing/app_router.dart';
import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/auth/diagnostic/diagnostic_auth_repository.dart';
import 'package:carebridge/features/auth/diagnostic/diagnostic_login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Audit gap 4 — real diagnostic-partner auth (flat, reg number + PIN).
/// Fake repo: success for LAB-DEMO-1/1234, wrong-PIN error otherwise.
class _FakeDiagAuth implements DiagnosticAuthRepository {
  String? loggedInReg;
  String? registeredName;

  @override
  Future<PartnerProfile> login({
    required String registrationNumber,
    required String pin,
  }) async {
    if (registrationNumber == 'LAB-DEMO-1' && pin == '1234') {
      loggedInReg = registrationNumber;
      return const PartnerProfile(
          partnerId: 'dp1', name: 'City Diagnostics', type: 'both', verified: true);
    }
    throw StateError('Wrong PIN.');
  }

  @override
  Future<PartnerProfile> register({
    required String name,
    required String registrationNumber,
    required String phone,
    required String pin,
    String type = 'both',
    String? hfrId,
    bool nablAccredited = false,
  }) async {
    registeredName = name;
    return PartnerProfile(partnerId: 'dp2', name: name, type: type);
  }
}

Widget _app(_FakeDiagAuth repo) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const DiagnosticLoginScreen()),
    GoRoute(
        path: Routes.diagnosticPortal,
        builder: (_, __) => const Scaffold(body: Text('PORTAL'))),
  ]);
  return ProviderScope(
    overrides: [diagnosticAuthRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('partner signs in with registration number + PIN', (tester) async {
    _size(tester);
    final repo = _FakeDiagAuth();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Lab / diagnostic registration number'),
        'LAB-DEMO-1');
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '1234');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(repo.loggedInReg, 'LAB-DEMO-1');
    expect(find.text('PORTAL'), findsOneWidget);
  });

  testWidgets('wrong PIN shows the error and stays on the sign-in screen',
      (tester) async {
    _size(tester);
    await tester.pumpWidget(_app(_FakeDiagAuth()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Lab / diagnostic registration number'),
        'LAB-DEMO-1');
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '9999');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Wrong PIN.'), findsOneWidget);
    expect(find.text('PORTAL'), findsNothing);
  });

  testWidgets('registration collects ID-5 fields and lands in the portal',
      (tester) async {
    _size(tester);
    final repo = _FakeDiagAuth();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New lab / imaging centre? Register here'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Centre name'), 'Metro Scans');
    await tester.enterText(
        find.widgetWithText(TextField, 'Registration / license number'),
        'LAB-777');
    await tester.enterText(
        find.widgetWithText(TextField, 'Mobile number'), '9888877777');
    await tester.enterText(
        find.widgetWithText(TextField, 'Choose a PIN (4–8 digits)'), '4321');
    await tester.tap(find.text('Register & sign in'));
    await tester.pumpAndSettle();

    expect(repo.registeredName, 'Metro Scans');
    expect(find.text('PORTAL'), findsOneWidget);
  });
}
