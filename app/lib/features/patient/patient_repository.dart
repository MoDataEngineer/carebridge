import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import 'patient_models.dart';

/// Backend for the patient core. Abstracted so the UI can be widget-tested with
/// a fake (no network). All reads/writes are gated by the patient self-access
/// RLS in migration 0005 — the patient only ever touches their own rows.
abstract class PatientRepository {
  Future<PatientProfile> loadProfile();
  Future<PatientProfile> saveProfile(PatientProfile profile);

  /// Read-only visit history (Section 5.1), most recent first.
  Future<List<VisitRecord>> visitHistory();

  Future<List<AppointmentRecord>> appointments();
  Future<List<BookableDoctor>> bookableDoctors();
  Future<AppointmentRecord> bookAppointment({
    required BookableDoctor doctor,
    required DateTime when,
  });

  /// Fires whenever one of the patient's own appointment rows changes (Supabase
  /// Realtime, RLS-scoped to self). A SIGNAL — consumers refetch on each event.
  Stream<void> appointmentChanges();

  /// The doctor's live queue position for today (current token + waiting count),
  /// visible to a patient who has an appointment with that doctor today. Null
  /// when there's nothing in progress.
  Future<NowServing?> nowServing(String doctorId);
}

class SupabasePatientRepository implements PatientRepository {
  SupabasePatientRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<PatientProfile> loadProfile() async {
    final row = await _client.from('patients').select().maybeSingle();
    if (row == null) {
      throw StateError('No patient profile for the signed-in user yet.');
    }
    return PatientProfile.fromMap(row);
  }

  @override
  Future<PatientProfile> saveProfile(PatientProfile p) async {
    final row = await _client
        .from('patients')
        .update({
          'name': p.name,
          'dob': p.dob?.toIso8601String(),
          // D3: ABHA optional in pilot; blank stays NULL (abha_id is unique).
          'abha_id': (p.abhaId?.trim().isEmpty ?? true) ? null : p.abhaId!.trim(),
          'allergies': p.allergies,
          'chronic_conditions': p.chronicConditions,
          'current_medications': p.currentMedications,
        })
        .eq('id', p.id)
        .select()
        .single();
    return PatientProfile.fromMap(row);
  }

  @override
  Future<List<VisitRecord>> visitHistory() async {
    final rows = await _client
        .from('visits')
        .select('id, visit_date, diagnosis, notes, follow_up_date, '
            'prescriptions(drug_name, dosage, schedule, relation_to_food, duration_days, instructions)')
        .order('visit_date', ascending: false);
    return (rows as List).map((m) {
      final pres = ((m['prescriptions'] ?? []) as List).map((p) {
        return PrescriptionRecord(
          drugName: (p['drug_name'] ?? '') as String,
          dosage: p['dosage'] as String?,
          schedule: ((p['schedule'] ?? {}) as Map)
              .map((k, v) => MapEntry(k.toString(), v == true)),
          durationDays: p['duration_days'] as int?,
          instructions: p['instructions'] as String?,
        );
      }).toList();
      return VisitRecord(
        id: m['id'] as String,
        visitDate: DateTime.parse(m['visit_date'].toString()),
        diagnosis: m['diagnosis'] as String?,
        notes: m['notes'] as String?,
        followUpDate: m['follow_up_date'] != null
            ? DateTime.tryParse(m['follow_up_date'].toString())
            : null,
        prescriptions: pres,
      );
    }).toList();
  }

  @override
  Future<List<AppointmentRecord>> appointments() async {
    final rows = await _client
        .from('appointments')
        .select('id, scheduled_time, status, queue_position, doctor_id')
        .order('scheduled_time', ascending: true);
    return (rows as List)
        .map((m) => AppointmentRecord(
              id: m['id'] as String,
              scheduledTime: DateTime.parse(m['scheduled_time'].toString()),
              status: (m['status'] ?? 'scheduled') as String,
              queuePosition: m['queue_position'] as int?,
              doctorId: m['doctor_id'] as String?,
            ))
        .toList();
  }

  @override
  Stream<void> appointmentChanges() =>
      _client.from('appointments').stream(primaryKey: ['id']).map((_) {});

  @override
  Future<NowServing?> nowServing(String doctorId) async {
    final res = await _client
        .rpc('carebridge_now_serving', params: {'p_doctor': doctorId});
    final list = (res ?? []) as List;
    if (list.isEmpty) return null;
    final m = list.first as Map<String, dynamic>;
    return NowServing(
      servingToken: m['serving_token'] as int?,
      waitingCount: (m['waiting_count'] ?? 0) as int,
    );
  }

  @override
  Future<List<BookableDoctor>> bookableDoctors() async {
    // Narrow directory RPC (0020): a patient session cannot (and must not)
    // select the doctors table directly — it carries pin_hash.
    final rows = await _client.rpc('carebridge_bookable_doctors');
    return ((rows ?? []) as List)
        .map((m) => BookableDoctor(
              doctorId: m['doctor_id'] as String,
              clinicId: m['clinic_id'] as String,
              doctorName: (m['doctor_name'] ?? '') as String,
              clinicName: (m['clinic_name'] ?? '') as String,
              specialty: (m['specialty'] ?? '') as String,
              councilRegNumber: (m['council_reg_number'] ?? '') as String,
              councilName: (m['council_name'] ?? '') as String,
              hprVerified: m['hpr_verified'] == true,
              city: (m['city'] ?? '') as String,
              state: (m['state'] ?? '') as String,
            ))
        .toList();
  }

  @override
  Future<AppointmentRecord> bookAppointment({
    required BookableDoctor doctor,
    required DateTime when,
  }) async {
    final me = await _client.from('patients').select('id').single();
    final row = await _client
        .from('appointments')
        .insert({
          'patient_id': me['id'],
          'doctor_id': doctor.doctorId,
          'clinic_id': doctor.clinicId,
          'scheduled_time': when.toIso8601String(),
          'status': 'scheduled',
        })
        .select()
        .single();
    return AppointmentRecord(
      id: row['id'] as String,
      scheduledTime: DateTime.parse(row['scheduled_time'].toString()),
      status: (row['status'] ?? 'scheduled') as String,
      clinicName: doctor.clinicName,
      doctorName: doctor.doctorName,
    );
  }
}

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a PatientRepository override.');
  }
  return SupabasePatientRepository(SupabaseService.client);
});
