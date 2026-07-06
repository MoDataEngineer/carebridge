import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Phase 11 (D12): custom OTP, Supabase-hosted. The mint-scope-token function
/// generates/stores/verifies the codes; only the SMS send is provider-specific
/// (MSG91 first — founder decision 2026-07-06, Firebase SMS too costly).
///
/// Thin seam so widget tests fake it. [sendCode] returns false when the
/// server has no SMS provider configured yet — the login screens then fall
/// back to the demo (no-OTP) path, which the server accepts only while
/// REQUIRE_OTP is off.
abstract class PhoneOtp {
  /// Ask the server to SMS a code. True = code sent, show the code field.
  /// False = OTP not configured server-side (demo fallback).
  Future<bool> sendCode(String phone);
}

class SupabasePhoneOtp implements PhoneOtp {
  SupabasePhoneOtp(this._client);
  final SupabaseClient _client;

  @override
  Future<bool> sendCode(String phone) async {
    try {
      final res = await _client.functions.invoke('mint-scope-token', body: {
        'action': 'send_otp',
        'phone': phone,
      });
      final data = res.data as Map<String, dynamic>;
      return data['sent'] == true;
    } on FunctionException catch (e) {
      final details = e.details;
      final err = details is Map<String, dynamic> ? details['error'] : null;
      if (err == 'otp_not_configured') return false; // demo fallback
      rethrow;
    }
  }
}

final phoneOtpProvider = Provider<PhoneOtp>((_) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a PhoneOtp override.');
  }
  return SupabasePhoneOtp(SupabaseService.client);
});
