import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import 'abdm_models.dart';

/// Client for the ABDM M1 ABHA flows. Every call is a thin relay to the
/// `abdm-gateway` Edge Function — the ABDM keys, RSA encryption and raw
/// Aadhaar/OTP handling all live server-side (ID-6). Abstracted so the UI can
/// be widget-tested with a fake (no network, no ABDM).
///
/// The Edge Function answers `{ status, body }` where `status` is ABDM's own
/// HTTP status; on an ABDM error it returns HTTP 502 (invoke throws). We surface
/// a readable message either way.
abstract class AbdmRepository {
  /// Create-ABHA step 1: Aadhaar → OTP to the Aadhaar-linked mobile.
  Future<AbhaOtpChallenge> createRequestOtp(String aadhaar);

  /// Create-ABHA step 2: txnId + OTP + communication mobile → new ABHA.
  Future<AbhaProfile> createVerify({
    required String txnId,
    required String otp,
    required String mobile,
  });

  /// Verify-ABHA step 1: existing ABHA number → OTP (Aadhaar-linked mobile).
  Future<AbhaOtpChallenge> loginRequestOtp(String abhaNumber);

  /// Verify-ABHA step 2: txnId + OTP → the verified ABHA profile.
  Future<AbhaProfile> loginVerify({required String txnId, required String otp});
}

class SupabaseAbdmRepository implements AbdmRepository {
  SupabaseAbdmRepository(this._client);
  final SupabaseClient _client;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('abdm-gateway', body: body);
      final data = (res.data ?? {}) as Map<String, dynamic>;
      return _unwrap(data);
    } on FunctionException catch (e) {
      // Non-2xx from the function (e.g. ABDM 400/502) — details carries the
      // `{status, body}` envelope we throw a readable message from.
      final details = e.details;
      if (details is Map) throw StateError(_message(Map<String, dynamic>.from(details)));
      throw StateError('ABHA service error: ${e.reasonPhrase ?? e.status}');
    }
  }

  /// Pull the ABDM `body` out of the `{status, body}` envelope, raising a
  /// readable error if ABDM reported a field/validation problem.
  Map<String, dynamic> _unwrap(Map<String, dynamic> data) {
    if (data['error'] != null) throw StateError('${data['error']}');
    final body = data['body'];
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    throw StateError('Unexpected ABHA response');
  }

  /// Best-effort human message from an ABDM error body (its shape varies:
  /// `{field: "reason"}`, `{message}`, or `{error:{message}}`).
  String _message(Map<String, dynamic> data) {
    final body = data['body'];
    if (body is Map) {
      if (body['message'] != null) return '${body['message']}';
      final err = body['error'];
      if (err is Map && err['message'] != null) return '${err['message']}';
      if (body.isNotEmpty) return body.values.first.toString();
    }
    return 'ABHA request failed (status ${data['status'] ?? '??'})';
  }

  @override
  Future<AbhaOtpChallenge> createRequestOtp(String aadhaar) async {
    final body = await _call({
      'action': 'abha_create_request_otp',
      'aadhaar': aadhaar,
    });
    return AbhaOtpChallenge.fromBody(body);
  }

  @override
  Future<AbhaProfile> createVerify({
    required String txnId,
    required String otp,
    required String mobile,
  }) async {
    final body = await _call({
      'action': 'abha_create_verify',
      'txnId': txnId,
      'otp': otp,
      'mobile': mobile,
    });
    final profile = body['ABHAProfile'];
    if (profile is Map) {
      return AbhaProfile.fromEnrol(Map<String, dynamic>.from(profile));
    }
    throw StateError('ABHA created but no profile returned');
  }

  @override
  Future<AbhaOtpChallenge> loginRequestOtp(String abhaNumber) async {
    final body = await _call({
      'action': 'abha_login_request_otp',
      'id': abhaNumber,
      'loginHint': 'abha-number',
      'otpSystem': 'aadhaar',
    });
    return AbhaOtpChallenge.fromBody(body);
  }

  @override
  Future<AbhaProfile> loginVerify({
    required String txnId,
    required String otp,
  }) async {
    final body = await _call({
      'action': 'abha_login_verify',
      'txnId': txnId,
      'otp': otp,
      'otpSystem': 'aadhaar',
    });
    final accounts = body['accounts'];
    if (accounts is List && accounts.isNotEmpty) {
      return AbhaProfile.fromEnrol(Map<String, dynamic>.from(accounts.first as Map));
    }
    throw StateError('Verified, but no ABHA account was returned');
  }
}

final abdmRepositoryProvider = Provider<AbdmRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide an AbdmRepository override.');
  }
  return SupabaseAbdmRepository(SupabaseService.client);
});
