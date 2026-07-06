import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_client.dart';
import '../../../shared/models/enums.dart';
import 'clinic_models.dart';

/// Abstraction over the clinic auth / scope-minting backend so the session logic
/// (and the solo-vs-picker decision) can be unit/widget-tested without a network.
abstract class ClinicAuthRepository {
  /// Clinic login: returns the roster + a base token. Phase 11 (D12):
  /// [otpCode] is the SMS code for the REGISTERED phone; without it the
  /// server falls back to the H1-interim registered-phone check (until
  /// REQUIRE_OTP is switched on server-side).
  Future<ClinicLoginResult> login({
    required String registrationNumber,
    required String phone,
    String? otpCode,
  });

  /// Register a NEW hospital (founder decision 2026-07-04): hospital name +
  /// registration/license number + mobile + admin PIN. Returns a logged-in
  /// result with an empty roster; doctors are added under it afterwards.
  /// Same path for solo doctors.
  Future<ClinicLoginResult> register({
    required String name,
    required String registrationNumber,
    required String phone,
    required String adminPin,
    String? address,
  });

  /// Verify the identity's PIN (D1) and mint the short-lived scoped token (D2).
  /// Throws [PinRejected] if the PIN is wrong or the identity is locked out.
  Future<ScopedSession> mintScope({
    required String clinicId,
    required ActiveRole role,
    String? doctorId,
    required String pin,
  });
}

class PinRejected implements Exception {
  PinRejected(this.reason, {this.lockedUntil});
  final String reason; // 'bad_pin' | 'locked' | 'no_pin_set'
  final DateTime? lockedUntil;
}

/// Real implementation backed by the `mint-scope-token` Edge Function
/// (Phase 4.5 Option A contract — no self-minted JWTs):
///   login -> function returns a REAL GoTrue session; we adopt it via
///            setSession(refresh_token), so every later call rides it.
///   scope -> function verifies the PIN and writes scope_sessions; we then
///            refreshSession() so the NEW token carries the hook-injected
///            clinic_id / active_role / active_doctor_id claims RLS reads.
class SupabaseClinicAuthRepository implements ClinicAuthRepository {
  SupabaseClinicAuthRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<ClinicLoginResult> login({
    required String registrationNumber,
    required String phone,
    String? otpCode,
  }) async {
    final res = await _client.functions.invoke('mint-scope-token', body: {
      'action': 'login',
      'registration_number': registrationNumber,
      'phone': phone,
      if (otpCode != null) 'otp_code': otpCode,
    });
    final data = res.data as Map<String, dynamic>;
    // Adopt the clinic's GoTrue session client-side. From here on, PostgREST
    // and function calls carry this (still unscoped) token automatically.
    await _client.auth.setSession(data['refresh_token'] as String);
    return ClinicLoginResult(
      clinicId: data['clinic_id'] as String,
      clinicName: (data['clinic_name'] ?? '') as String,
      baseToken: (data['access_token'] ?? '') as String,
      paid: data['subscription_status'] == 'paid',
      verified: data['verified'] == true,
      doctors: ((data['doctors'] ?? []) as List)
          .map((e) => DoctorSummary.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<ClinicLoginResult> register({
    required String name,
    required String registrationNumber,
    required String phone,
    required String adminPin,
    String? address,
  }) async {
    final res = await _client.functions.invoke('mint-scope-token', body: {
      'action': 'register',
      'name': name,
      'registration_number': registrationNumber,
      'phone': phone,
      'admin_pin': adminPin,
      'address': address,
    });
    final data = res.data as Map<String, dynamic>;
    await _client.auth.setSession(data['refresh_token'] as String);
    return ClinicLoginResult(
      clinicId: data['clinic_id'] as String,
      clinicName: (data['clinic_name'] ?? '') as String,
      baseToken: (data['access_token'] ?? '') as String,
      paid: data['subscription_status'] == 'paid',
      verified: data['verified'] == true,
      doctors: ((data['doctors'] ?? []) as List)
          .map((e) => DoctorSummary.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<ScopedSession> mintScope({
    required String clinicId,
    required ActiveRole role,
    String? doctorId,
    required String pin,
  }) async {
    final current = _client.auth.currentSession;
    if (current == null) {
      throw StateError('No clinic session — log in first.');
    }
    Map<String, dynamic> data;
    try {
      final res = await _client.functions.invoke('mint-scope-token', body: {
        'action': 'scope',
        'target_role': role == ActiveRole.admin ? 'admin' : 'doctor',
        'target_doctor_id': doctorId,
        'pin': pin,
        'access_token': current.accessToken,
      });
      data = res.data as Map<String, dynamic>;
    } on FunctionException catch (e) {
      // Non-2xx (e.g. 401 pin_rejected) surfaces as an exception; unwrap it.
      final details = e.details;
      data = details is Map<String, dynamic> ? details : {'error': 'scope_failed'};
    }
    if (data['error'] != null) {
      throw PinRejected(
        (data['reason'] ?? data['error']) as String,
        lockedUntil: data['locked_until'] != null
            ? DateTime.tryParse(data['locked_until'] as String)
            : null,
      );
    }
    // Scope row written server-side; refresh so the new access token carries
    // the claims (custom_access_token_hook injects them on issue).
    final refreshed = await _client.auth.refreshSession();
    final session = refreshed.session;
    if (session == null) {
      throw StateError('Session refresh failed after scoping.');
    }
    return ScopedSession(
      clinicId: clinicId,
      role: role,
      doctorId: role == ActiveRole.doctor ? doctorId : null,
      accessToken: session.accessToken,
      expiresIn: session.expiresIn ?? 0,
    );
  }
}

/// Provider — overridden with a fake in tests. Throws if used before Supabase is
/// initialized (placeholder builds without creds).
final clinicAuthRepositoryProvider = Provider<ClinicAuthRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a ClinicAuthRepository override.');
  }
  return SupabaseClinicAuthRepository(SupabaseService.client);
});
