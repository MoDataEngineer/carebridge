import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';

/// Live appointment/token tracker (Phase 10, Sections 5.2 + 10). The rows a
/// session gets are decided at the database (carebridge_live_queue: doctor
/// scope = own queue, admin scope = clinic-wide); the token functions are
/// PAID-gated in the DB regardless of what the UI claims.

/// One row in today's queue (narrow columns — name only, no history).
class QueueEntry {
  const QueueEntry({
    required this.appointmentId,
    required this.patientName,
    required this.scheduledTime,
    required this.status,
    this.queuePosition,
    required this.doctorId,
    required this.doctorName,
  });

  final String appointmentId;
  final String patientName;
  final DateTime scheduledTime;
  final String status; // scheduled | waiting | in_consultation | completed
  final int? queuePosition;
  final String doctorId;
  final String doctorName;

  factory QueueEntry.fromMap(Map<String, dynamic> m) => QueueEntry(
        appointmentId: m['appointment_id'] as String,
        patientName: (m['patient_name'] ?? '') as String,
        scheduledTime: DateTime.parse(m['scheduled_time'].toString()),
        status: (m['status'] ?? 'scheduled') as String,
        queuePosition: m['queue_position'] as int?,
        doctorId: m['doctor_id'] as String,
        doctorName: (m['doctor_name'] ?? '') as String,
      );
}

abstract class QueueRepository {
  /// Today's queue for the active scope (RLS/definer decides the rows).
  Future<List<QueueEntry>> liveQueue();

  /// Check a scheduled appointment in; returns the assigned token (paid).
  Future<int> checkIn(String appointmentId);

  /// Complete the current consultation and call the lowest waiting token
  /// (doctor-scoped only, paid). Returns the called appointment id, if any.
  Future<String?> callNext();

  /// Fires whenever an appointment row changes (Supabase Realtime; RLS scopes
  /// which changes a session receives). Consumers refetch [liveQueue] on each
  /// event — the stream is a SIGNAL, not the data.
  Stream<void> changes();
}

class SupabaseQueueRepository implements QueueRepository {
  SupabaseQueueRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<QueueEntry>> liveQueue() async {
    final res = await _client.rpc('carebridge_live_queue');
    return [
      for (final m in (res ?? []) as List)
        QueueEntry.fromMap(m as Map<String, dynamic>)
    ];
  }

  @override
  Future<int> checkIn(String appointmentId) async {
    final res = await _client
        .rpc('carebridge_checkin_appointment', params: {'p_appointment': appointmentId});
    return res as int;
  }

  @override
  Future<String?> callNext() async {
    final res = await _client.rpc('carebridge_call_next');
    return res as String?;
  }

  @override
  Stream<void> changes() => _client
      .from('appointments')
      .stream(primaryKey: ['id']).map((_) {});
}

final queueRepositoryProvider = Provider<QueueRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a QueueRepository override.');
  }
  return SupabaseQueueRepository(SupabaseService.client);
});
