import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import 'consent_models.dart';

/// Patient-facing consent backend (Section 7). All visibility is enforced by the
/// Phase 5 RLS + SECURITY DEFINER functions in migration 0009 — the patient only
/// ever touches their own grants/logs, and grant mutations go through the
/// carebridge_* RPCs (never direct DML).
abstract class ConsentRepository {
  Future<List<GrantView>> doctorsWithAccess();
  Future<void> revokeGrant(String grantId);
  Future<List<AccessRequestView>> pendingRequests();
  Future<void> respondRequest(String grantId, bool approve);
  Future<List<AccessLogView>> whoViewed();
  Future<ConsentCode> createConsentCode();
}

class SupabaseConsentRepository implements ConsentRepository {
  SupabaseConsentRepository(this._client);
  final SupabaseClient _client;

  // access_grants.granted_to_id is a generic uuid (no FK), so resolve doctor +
  // clinic names with a follow-up query rather than a PostgREST embed.
  Future<Map<String, ({String doctor, String clinic})>> _doctorNames(
      List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from('doctors')
        .select('id, name, clinics(name)')
        .inFilter('id', ids);
    return {
      for (final m in rows as List)
        m['id'] as String: (
          doctor: (m['name'] ?? '') as String,
          clinic: ((m['clinics']?['name']) ?? '') as String,
        )
    };
  }

  @override
  Future<List<GrantView>> doctorsWithAccess() async {
    final rows = await _client
        .from('access_grants')
        .select('id, granted_to_id, type, granted_at')
        .eq('granted_to_type', 'doctor')
        .eq('status', 'active')
        .order('granted_at', ascending: false);
    final list = rows as List;
    final names = await _doctorNames(
        [for (final m in list) m['granted_to_id'] as String]);
    return [
      for (final m in list)
        GrantView(
          grantId: m['id'] as String,
          doctorName: names[m['granted_to_id']]?.doctor ?? 'Unknown doctor',
          clinicName: names[m['granted_to_id']]?.clinic ?? '',
          type: (m['type'] ?? 'standing') as String,
          grantedAt: m['granted_at'] != null
              ? DateTime.tryParse(m['granted_at'].toString())
              : null,
        )
    ];
  }

  @override
  Future<void> revokeGrant(String grantId) =>
      _client.rpc('carebridge_revoke_grant', params: {'p_grant': grantId});

  @override
  Future<List<AccessRequestView>> pendingRequests() async {
    final rows = await _client
        .from('access_grants')
        .select('id, granted_to_id, granted_at')
        .eq('granted_to_type', 'doctor')
        .eq('status', 'pending')
        .order('granted_at', ascending: false);
    final list = rows as List;
    final names = await _doctorNames(
        [for (final m in list) m['granted_to_id'] as String]);
    return [
      for (final m in list)
        AccessRequestView(
          grantId: m['id'] as String,
          doctorName: names[m['granted_to_id']]?.doctor ?? 'Unknown doctor',
          clinicName: names[m['granted_to_id']]?.clinic ?? '',
          requestedAt: m['granted_at'] != null
              ? DateTime.tryParse(m['granted_at'].toString())
              : null,
        )
    ];
  }

  @override
  Future<void> respondRequest(String grantId, bool approve) => _client.rpc(
        'carebridge_respond_access',
        params: {'p_grant': grantId, 'p_approve': approve},
      );

  @override
  Future<List<AccessLogView>> whoViewed() async {
    final rows = await _client
        .from('access_logs')
        .select('accessed_by_type, accessed_by_id, viewed_at, what_viewed')
        .order('viewed_at', ascending: false)
        .limit(100);
    return [
      for (final m in rows as List)
        AccessLogView(
          accessorType: (m['accessed_by_type'] ?? '') as String,
          accessorLabel: (m['accessed_by_id'] ?? '') as String,
          viewedAt: DateTime.parse(m['viewed_at'].toString()),
          whatViewed: m['what_viewed'] as String?,
        )
    ];
  }

  @override
  Future<ConsentCode> createConsentCode() async {
    final res = await _client.rpc('carebridge_create_consent_code');
    // Returns a single-row table {code, expires_at}.
    final row = (res as List).first as Map<String, dynamic>;
    return ConsentCode(
      code: row['code'] as String,
      expiresAt: DateTime.parse(row['expires_at'].toString()),
    );
  }
}

final consentRepositoryProvider = Provider<ConsentRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a ConsentRepository override.');
  }
  return SupabaseConsentRepository(SupabaseService.client);
});
