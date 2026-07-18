import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/abha/abdm_models.dart';
import 'package:carebridge/features/abha/abdm_repository.dart';
import 'package:carebridge/features/abha/abha_link_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M1 ABHA UI — drives the create and verify flows against a fake gateway so
/// the two-step OTP stepper, the create-only consent gate, and the resulting
/// pop value are all exercised without touching ABDM.
class _FakeAbdm implements AbdmRepository {
  String? createdAadhaar;
  String? createMobile;
  String? verifiedAbha;
  String? lastOtp;

  @override
  Future<AbhaOtpChallenge> createRequestOtp(String aadhaar) async {
    createdAadhaar = aadhaar;
    return const AbhaOtpChallenge(txnId: 'txn-create', message: 'OTP sent to ******1904');
  }

  @override
  Future<AbhaProfile> createVerify({
    required String txnId,
    required String otp,
    required String mobile,
  }) async {
    lastOtp = otp;
    createMobile = mobile;
    return const AbhaProfile(
      abhaNumber: '91-5524-8250-3620',
      abhaAddress: '91552482503620@sbx',
      name: 'Mohanraj Kandhasamy',
    );
  }

  @override
  Future<AbhaOtpChallenge> loginRequestOtp(String abhaNumber) async {
    verifiedAbha = abhaNumber;
    return const AbhaOtpChallenge(txnId: 'txn-login', message: 'OTP sent to ******1904');
  }

  @override
  Future<AbhaProfile> loginVerify({required String txnId, required String otp}) async {
    lastOtp = otp;
    return const AbhaProfile(
      abhaNumber: '91-5524-8250-3620',
      abhaAddress: '91552482503620@sbx',
      name: 'Mohanraj Kandhasamy',
    );
  }
}

Widget _host(_FakeAbdm fake, AbhaLinkMode mode, {ValueChanged<AbhaProfile?>? onPop}) {
  return ProviderScope(
    overrides: [abdmRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await Navigator.of(context).push<AbhaProfile>(
                  MaterialPageRoute(builder: (_) => AbhaLinkScreen(mode: mode)),
                );
                onPop?.call(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('create: consent gates OTP, then Aadhaar→OTP→mobile creates ABHA',
      (tester) async {
    _bigScreen(tester);
    final fake = _FakeAbdm();
    AbhaProfile? popped;
    await tester.pumpWidget(_host(fake, AbhaLinkMode.create, onPop: (p) => popped = p));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Enter Aadhaar and try to send OTP WITHOUT consent → blocked, still step 1.
    await tester.enterText(find.widgetWithText(TextField, 'Aadhaar number'), '857634824866');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(fake.createdAadhaar, isNull, reason: 'consent must gate the request');
    expect(find.textContaining('agree to the consent'), findsOneWidget);

    // Agree, then send OTP → advances to step 2.
    await tester.tap(find.text('I agree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(fake.createdAadhaar, '857634824866');
    expect(find.textContaining('OTP sent to ******1904'), findsOneWidget);

    // OTP + mobile → create.
    await tester.enterText(find.widgetWithText(TextField, 'OTP'), '685163');
    await tester.enterText(find.widgetWithText(TextField, 'Mobile number'), '9629391904');
    await tester.tap(find.widgetWithText(FilledButton, 'Create ABHA'));
    await tester.pumpAndSettle();

    expect(fake.lastOtp, '685163');
    expect(fake.createMobile, '9629391904');
    expect(find.text('ABHA linked'), findsOneWidget);
    expect(find.textContaining('91-5524-8250-3620'), findsOneWidget);

    // Done pops the linked profile back to the caller.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(popped?.abhaNumber, '91-5524-8250-3620');
  });

  testWidgets('verify: existing ABHA number → OTP → linked (no consent gate)',
      (tester) async {
    _bigScreen(tester);
    final fake = _FakeAbdm();
    await tester.pumpWidget(_host(fake, AbhaLinkMode.verify));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Verify flow has no consent checkbox.
    expect(find.text('I agree'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'ABHA number'), '91552482503620');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(fake.verifiedAbha, '91552482503620');

    await tester.enterText(find.widgetWithText(TextField, 'OTP'), '838657');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(fake.lastOtp, '838657');
    expect(find.text('ABHA linked'), findsOneWidget);
  });
}
