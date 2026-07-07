import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_client.dart';
import 'clinic_models.dart';

/// Roster management backend (admin-scoped, Section 5.2). Abstracted so the
/// UI can be widget-tested with a fake. Authorization lives in the DB:
/// carebridge_add_doctor requires the caller to BE the clinic's auth user AND
/// hold an admin-scoped session; the roster list rides RLS
/// (doctors_select_own_clinic).
abstract class RosterRepository {
  Future<List<DoctorSummary>> listDoctors();

  /// Add a doctor under the admin's own hospital (ID-4 fields + a PIN the
  /// doctor will use to unlock their sessions). Returns the created summary.
  Future<DoctorSummary> addDoctor({
    required String name,
    required String councilRegNumber,
    required String councilName,
    required String specialty,
    String? hprId,
    required String pin,
    String? phone,
  });
}

class SupabaseRosterRepository implements RosterRepository {
  SupabaseRosterRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<DoctorSummary>> listDoctors() async {
    final rows = await _client
        .from('doctors')
        .select('id, name, specialty')
        .eq('is_active', true)
        .order('name');
    return [
      for (final m in rows as List) DoctorSummary.fromMap(m as Map<String, dynamic>)
    ];
  }

  @override
  Future<DoctorSummary> addDoctor({
    required String name,
    required String councilRegNumber,
    required String councilName,
    required String specialty,
    String? hprId,
    required String pin,
    String? phone,
  }) async {
    final res = await _client.rpc('carebridge_add_doctor', params: {
      'p_name': name,
      'p_council_reg': councilRegNumber,
      'p_council_name': councilName,
      'p_specialty': specialty,
      'p_hpr': hprId,
      'p_pin': pin,
      'p_phone': phone,
    });
    return DoctorSummary.fromMap(((res as List).first) as Map<String, dynamic>);
  }
}

final rosterRepositoryProvider = Provider<RosterRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a RosterRepository override.');
  }
  return SupabaseRosterRepository(SupabaseService.client);
});
