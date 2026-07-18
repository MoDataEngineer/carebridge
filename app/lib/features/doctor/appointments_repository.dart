import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';

/// One upcoming appointment in the clinic dashboard (today + future). Narrow
/// columns — patient name only, per the queue privacy note (migration 0026).
class UpcomingAppointment {
  const UpcomingAppointment({
    required this.appointmentId,
    required this.patientName,
    this.patientPhone,
    required this.doctorId,
    required this.doctorName,
    required this.scheduledTime,
    this.sessionLabel,
    required this.status,
  });

  final String appointmentId;
  final String patientName;
  final String? patientPhone; // founder 2026-07-18: clinic can reach the patient
  final String doctorId;
  final String doctorName;
  final DateTime scheduledTime;
  final String? sessionLabel;
  final String status; // requested | scheduled | waiting | in_consultation | completed

  bool get isPending => status == 'requested';

  factory UpcomingAppointment.fromMap(Map<String, dynamic> m) => UpcomingAppointment(
        appointmentId: m['appointment_id'] as String,
        patientName: (m['patient_name'] ?? '') as String,
        patientPhone: m['patient_phone'] as String?,
        doctorId: m['doctor_id'] as String,
        doctorName: (m['doctor_name'] ?? '') as String,
        scheduledTime: DateTime.parse(m['scheduled_time'].toString()),
        sessionLabel: m['session_label'] as String?,
        status: (m['status'] ?? 'scheduled') as String,
      );
}

abstract class AppointmentsRepository {
  /// Today + future appointments for the active scope (doctor own / admin all).
  Future<List<UpcomingAppointment>> upcoming();

  /// Approve a pending request (requested -> scheduled).
  Future<void> approve(String appointmentId);

  /// Reject / cancel any upcoming appointment (emergency), notifying the patient.
  Future<void> reject(String appointmentId, {String? reason});

  /// Realtime signal — appointment rows changed; refetch [upcoming].
  Stream<void> changes();
}

class SupabaseAppointmentsRepository implements AppointmentsRepository {
  SupabaseAppointmentsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<UpcomingAppointment>> upcoming() async {
    final res = await _client.rpc('carebridge_upcoming_appointments');
    return [
      for (final m in (res ?? []) as List)
        UpcomingAppointment.fromMap(m as Map<String, dynamic>)
    ];
  }

  @override
  Future<void> approve(String appointmentId) async {
    await _client.rpc('carebridge_approve_appointment',
        params: {'p_appointment': appointmentId});
  }

  @override
  Future<void> reject(String appointmentId, {String? reason}) async {
    await _client.rpc('carebridge_reject_appointment',
        params: {'p_appointment': appointmentId, 'p_reason': reason});
  }

  @override
  Stream<void> changes() =>
      _client.from('appointments').stream(primaryKey: ['id']).map((_) {});
}

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide an AppointmentsRepository override.');
  }
  return SupabaseAppointmentsRepository(SupabaseService.client);
});

/// Live count of pending ('requested') appointments for the active scope — used
/// to badge the Appointments nav tab so the doctor sees new requests arrive
/// without a push notification. Refetches whenever appointment rows change.
final pendingRequestCountProvider = StreamProvider.autoDispose<int>((ref) async* {
  final repo = ref.watch(appointmentsRepositoryProvider);
  Future<int> count() async {
    final list = await repo.upcoming();
    return list.where((a) => a.isPending).length;
  }

  yield await count();
  await for (final _ in repo.changes()) {
    yield await count();
  }
});
