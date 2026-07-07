import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_client.dart';
import 'availability_models.dart';

/// Reads/writes a doctor's weekly consultation sessions (migration 0025).
/// Reads ride the clinic RLS on doctor_sessions; the write goes through the
/// admin/doctor-guarded carebridge_set_doctor_sessions RPC.
abstract class AvailabilityRepository {
  Future<List<DoctorSession>> sessionsFor(String doctorId);
  Future<void> setSessions(String doctorId, List<DoctorSession> sessions);
}

class SupabaseAvailabilityRepository implements AvailabilityRepository {
  SupabaseAvailabilityRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<DoctorSession>> sessionsFor(String doctorId) async {
    final rows = await _client
        .from('doctor_sessions')
        .select('id, day_of_week, label, start_time, end_time, capacity')
        .eq('doctor_id', doctorId)
        .order('day_of_week')
        .order('start_time');
    return [
      for (final m in rows as List) DoctorSession.fromMap(m as Map<String, dynamic>)
    ];
  }

  @override
  Future<void> setSessions(String doctorId, List<DoctorSession> sessions) async {
    await _client.rpc('carebridge_set_doctor_sessions', params: {
      'p_doctor': doctorId,
      'p_sessions': [for (final s in sessions) s.toJson()],
    });
  }
}

final availabilityRepositoryProvider = Provider<AvailabilityRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide an AvailabilityRepository override.');
  }
  return SupabaseAvailabilityRepository(SupabaseService.client);
});
