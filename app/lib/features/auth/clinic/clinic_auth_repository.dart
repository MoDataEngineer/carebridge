import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_client.dart';
import '../../../shared/models/enums.dart';
import 'clinic_models.dart';

/// Abstraction over the clinic auth / scope-minting backend so the session logic
/// (and the solo-vs-picker decision) can be unit/widget-tested without a network.
abstract class ClinicAuthRepository {
  /// Clinic login: returns the roster + a base token. (OTP is placeholder until
  /// Phase 11; see the Edge Function.)
  Future<ClinicLoginResult> login({
    required String registrationNumber,
    required String phone,
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

/// Real implementation backed by the `mint-scope-token` Edge Function (D2).
/// NOTE: requires the function to be deployed and its secrets set
/// (SUPABASE_JWT_SECRET etc.) — see supabase/functions/mint-scope-token.
class SupabaseClinicAuthRepository implements ClinicAuthRepository {
  SupabaseClinicAuthRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<ClinicLoginResult> login({
    required String registrationNumber,
    required String phone,
  }) async {
    final res = await _client.functions.invoke('mint-scope-token', body: {
      'action': 'login',
      'registration_number': registrationNumber,
      'phone': phone,
    });
    final data = res.data as Map<String, dynamic>;
    return ClinicLoginResult(
      clinicId: data['clinic_id'] as String,
      clinicName: (data['clinic_name'] ?? '') as String,
      baseToken: (data['base_token'] ?? '') as String,
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
    final res = await _client.functions.invoke('mint-scope-token', body: {
      'action': 'scope',
      'clinic_id': clinicId,
      'target_role': role == ActiveRole.admin ? 'admin' : 'doctor',
      'target_doctor_id': doctorId,
      'pin': pin,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) {
      throw PinRejected(
        (data['reason'] ?? data['error']) as String,
        lockedUntil: data['locked_until'] != null
            ? DateTime.tryParse(data['locked_until'] as String)
            : null,
      );
    }
    return ScopedSession(
      clinicId: clinicId,
      role: role,
      doctorId: role == ActiveRole.doctor ? doctorId : null,
      accessToken: data['access_token'] as String,
      expiresIn: (data['expires_in'] ?? 0) as int,
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
