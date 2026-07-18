import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_client.dart';

/// The signed-in diagnostic partner's identity card (Section 2.3: flat, one
/// login per lab — no nested staff).
class PartnerProfile {
  const PartnerProfile({
    required this.partnerId,
    required this.name,
    required this.type,
    this.hfrId,
    this.nablAccredited = false,
    this.verified = false,
  });

  final String partnerId;
  final String name;
  final String type; // lab | imaging | both
  final String? hfrId;
  final bool nablAccredited;
  final bool verified;
}

/// Diagnostic-partner auth (audit gap 4, 2026-07-18). Real sessions: the Edge
/// Function verifies registration number + PIN (bcrypt, rate-limited) and
/// returns a GoTrue session bound to diagnostic_partners.auth_user_id — the
/// identity every Flow-C RLS policy (0011) keys on via current_partner_id().
abstract class DiagnosticAuthRepository {
  Future<PartnerProfile> login({
    required String registrationNumber,
    required String pin,
  });

  /// ID-5: lab name + registration/license number + phone + PIN; optional
  /// HFR ID and NABL badge. Registers unverified, then signs straight in.
  Future<PartnerProfile> register({
    required String name,
    required String registrationNumber,
    required String phone,
    required String pin,
    String type = 'both',
    String? hfrId,
    bool nablAccredited = false,
  });
}

class SupabaseDiagnosticAuthRepository implements DiagnosticAuthRepository {
  SupabaseDiagnosticAuthRepository(this._client);
  final SupabaseClient _client;

  Future<PartnerProfile> _call(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('mint-scope-token', body: body);
      final data = (res.data ?? {}) as Map<String, dynamic>;
      if (data['error'] != null) throw StateError(_message(data));
      // Replace ANY leftover session (patient/clinic) with the partner's own —
      // the portal's RLS must see THIS lab, not whoever logged in last.
      await _client.auth.setSession(data['refresh_token'] as String);
      return PartnerProfile(
        partnerId: data['partner_id'] as String,
        name: (data['partner_name'] ?? '') as String,
        type: (data['type'] ?? 'both') as String,
        hfrId: data['hfr_id'] as String?,
        nablAccredited: data['nabl_accredited'] == true,
        verified: data['verified'] == true,
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) throw StateError(_message(Map<String, dynamic>.from(details)));
      throw StateError('Sign in failed (${e.status})');
    }
  }

  String _message(Map<String, dynamic> data) {
    if (data['reason'] == 'locked') {
      return 'Too many wrong PINs — locked for a few minutes. Try again later.';
    }
    if (data['error'] == 'pin_rejected') return 'Wrong PIN.';
    return (data['detail'] ?? data['error'] ?? 'Sign in failed').toString();
  }

  @override
  Future<PartnerProfile> login({
    required String registrationNumber,
    required String pin,
  }) =>
      _call({
        'action': 'partner_login',
        'registration_number': registrationNumber,
        'pin': pin,
      });

  @override
  Future<PartnerProfile> register({
    required String name,
    required String registrationNumber,
    required String phone,
    required String pin,
    String type = 'both',
    String? hfrId,
    bool nablAccredited = false,
  }) =>
      _call({
        'action': 'partner_register',
        'name': name,
        'registration_number': registrationNumber,
        'phone': phone,
        'pin': pin,
        'type': type,
        if (hfrId != null && hfrId.isNotEmpty) 'hfr_id': hfrId,
        'nabl_accredited': nablAccredited,
      });
}

final diagnosticAuthRepositoryProvider = Provider<DiagnosticAuthRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a DiagnosticAuthRepository override.');
  }
  return SupabaseDiagnosticAuthRepository(SupabaseService.client);
});
