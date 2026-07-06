import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_client.dart';

/// Patient sign-in backend. PLACEHOLDER (Phase 11): the Edge Function signs a
/// phone in WITHOUT verifying an OTP — demo posture only, real ABDM/SMS OTP
/// replaces it. What matters now: the client gets a REAL GoTrue session for
/// the patient's own auth user, so the patient self-access RLS (0005) applies
/// instead of whatever session happened to be lying around in the browser.
abstract class PatientAuthRepository {
  /// Sign in (or first-time bootstrap, D3 phone-first) by mobile number.
  /// [otpCode] is the SMS code (D12) — verified server-side against the
  /// stored single-use code for this phone. Null = demo path (only accepted
  /// while REQUIRE_OTP is off server-side).
  Future<void> login(String phone, {String? otpCode});
}

class SupabasePatientAuthRepository implements PatientAuthRepository {
  SupabasePatientAuthRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<void> login(String phone, {String? otpCode}) async {
    final res = await _client.functions.invoke('mint-scope-token', body: {
      'action': 'patient_login',
      'phone': phone,
      if (otpCode != null) 'otp_code': otpCode,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) {
      throw StateError(data['error'] as String);
    }
    // Replace ANY existing session (e.g. a leftover clinic login) with the
    // patient's own — the RLS scoping bug this fixes came from that leak.
    await _client.auth.setSession(data['refresh_token'] as String);
  }
}

final patientAuthRepositoryProvider = Provider<PatientAuthRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a PatientAuthRepository override.');
  }
  return SupabasePatientAuthRepository(SupabaseService.client);
});
