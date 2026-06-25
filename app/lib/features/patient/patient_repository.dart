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
        .select('id, scheduled_time, status')
        .order('scheduled_time', ascending: true);
    return (rows as List)
        .map((m) => AppointmentRecord(
              id: m['id'] as String,
              scheduledTime: DateTime.parse(m['scheduled_time'].toString()),
              status: (m['status'] ?? 'scheduled') as String,
            ))
        .toList();
  }

  @override
  Future<List<BookableDoctor>> bookableDoctors() async {
    // Phase 3 placeholder: a real searchable directory comes later. Returns
    // active doctors the patient can request an appointment with.
    final rows = await _client
        .from('doctors')
        .select('id, name, clinic_id, clinics(name)')
        .eq('is_active', true);
    return (rows as List)
        .map((m) => BookableDoctor(
              doctorId: m['id'] as String,
              clinicId: m['clinic_id'] as String,
              doctorName: (m['name'] ?? '') as String,
              clinicName: ((m['clinics']?['name']) ?? '') as String,
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
