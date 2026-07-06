import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';

/// Phase 11: real OTP via Firebase Phone Auth (founder decision 2026-07-06 —
/// Indian numbers, Indian telecom operators; ~USD 0.01/SMS on Blaze, free
/// console "test phone numbers" for development).
///
/// Thin seam so widget tests fake it and the app degrades gracefully: when
/// the Firebase client config is absent, [enabled] is false and the login
/// screens keep the demo (no-OTP) path, clearly labelled.
abstract class PhoneOtp {
  bool get enabled;

  /// Send an SMS code to an E.164 phone (+91…). Must be called before
  /// [confirm]. On web this triggers Firebase's invisible reCAPTCHA.
  Future<void> sendCode(String phoneE164);

  /// Verify the 6-digit code; returns a Firebase ID token whose
  /// `phone_number` claim the server verifies (mint-scope-token).
  Future<String> confirm(String smsCode);
}

class DisabledPhoneOtp implements PhoneOtp {
  @override
  bool get enabled => false;
  @override
  Future<void> sendCode(String phoneE164) =>
      throw StateError('OTP is not configured');
  @override
  Future<String> confirm(String smsCode) =>
      throw StateError('OTP is not configured');
}

class FirebasePhoneOtp implements PhoneOtp {
  ConfirmationResult? _webConfirmation; // web flow
  String? _verificationId; // mobile flow

  @override
  bool get enabled => true;

  @override
  Future<void> sendCode(String phoneE164) async {
    final auth = FirebaseAuth.instance;
    if (kIsWeb) {
      _webConfirmation = await auth.signInWithPhoneNumber(phoneE164);
      return;
    }
    final sent = Completer<void>();
    await auth.verifyPhoneNumber(
      phoneNumber: phoneE164,
      verificationCompleted: (_) {}, // Android auto-retrieval; code entry still shown
      verificationFailed: (e) {
        if (!sent.isCompleted) sent.completeError(e);
      },
      codeSent: (verificationId, _) {
        _verificationId = verificationId;
        if (!sent.isCompleted) sent.complete();
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
    );
    await sent.future;
  }

  @override
  Future<String> confirm(String smsCode) async {
    final UserCredential cred;
    if (kIsWeb) {
      final c = _webConfirmation;
      if (c == null) throw StateError('Send the code first.');
      cred = await c.confirm(smsCode);
    } else {
      final vid = _verificationId;
      if (vid == null) throw StateError('Send the code first.');
      cred = await FirebaseAuth.instance.signInWithCredential(
        PhoneAuthProvider.credential(verificationId: vid, smsCode: smsCode),
      );
    }
    final token = await cred.user?.getIdToken();
    if (token == null) throw StateError('No ID token after OTP.');
    return token;
  }
}

final phoneOtpProvider = Provider<PhoneOtp>((_) {
  return Env.hasFirebase ? FirebasePhoneOtp() : DisabledPhoneOtp();
});
