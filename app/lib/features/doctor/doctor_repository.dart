import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import 'doctor_models.dart';

/// Backend for the doctor core (Section 5.2). Abstracted so the UI can be
/// widget-tested with a fake (no network).
///
/// IMPORTANT: this repository does NOT decide visibility. Every read/write rides
/// the active D2 scoped JWT, and the Phase 2 RLS policies (migration 0003) decide
/// what rows come back and whether a write is allowed:
///   - doctor-scoped  -> only the doctor's own granted patients;
///   - admin-scoped   -> all clinic patients with any active grant (AC-8);
///   - writes (addVisit) require a specific doctor identity (AC-9) — the DB
///     rejects an insert from a bare admin scope even if this method is called.
abstract class DoctorRepository {
  /// Scoped search by name / phone / ABHA (Section 5.2). RLS pre-filters rows.
  Future<List<PatientSearchResult>> searchPatients(String query);

  /// Read-only visit history for one patient, most recent first.
  Future<List<VisitRecord>> patientHistory(String patientId);

  /// Author a visit + its prescriptions under the calling doctor's identity.
  /// [doctorId]/[clinicId] come from the active scoped session; the DB re-checks
  /// them against the JWT claims (AC-9), so a forged caller cannot write.
  Future<void> addVisit({
    required String patientId,
    required String doctorId,
    required String clinicId,
    required NewVisit visit,
  });

  /// Flow A: redeem a patient's in-person consent code → standing grant.
  /// Returns the now-accessible patient id.
  Future<String> redeemConsentCode(String code);

  /// Flow B: look up a patient by exact phone/ABHA to request access.
  Future<List<PatientSearchResult>> lookupForRequest(String query);

  /// Flow B: send an access request to a patient (creates a pending grant).
  Future<void> requestAccess(String patientId);
}

class SupabaseDoctorRepository implements DoctorRepository {
  SupabaseDoctorRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<PatientSearchResult>> searchPatients(String query) async {
    final q = query.trim();
    var builder = _client.from('patients').select('id, name, phone, abha_id');
    if (q.isNotEmpty) {
      // ilike across the three lookup keys; RLS still scopes the visible set.
      builder = builder.or('name.ilike.%$q%,phone.ilike.%$q%,abha_id.ilike.%$q%');
    }
    final rows = await builder.order('name', ascending: true).limit(50);
    return (rows as List)
        .map((m) => PatientSearchResult.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<VisitRecord>> patientHistory(String patientId) async {
    final rows = await _client
        .from('visits')
        .select('id, visit_date, diagnosis, notes, follow_up_date, '
            'prescriptions(drug_name, dosage, schedule, relation_to_food, duration_days, instructions)')
        .eq('patient_id', patientId)
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
  Future<void> addVisit({
    required String patientId,
    required String doctorId,
    required String clinicId,
    required NewVisit visit,
  }) async {
    final inserted = await _client
        .from('visits')
        .insert({
          'patient_id': patientId,
          'doctor_id': doctorId,
          'clinic_id': clinicId,
          'diagnosis': visit.diagnosis,
          'notes': visit.notes,
          'follow_up_date': visit.followUpDate?.toIso8601String(),
        })
        .select('id')
        .single();
    final visitId = inserted['id'] as String;

    if (visit.prescriptions.isNotEmpty) {
      await _client.from('prescriptions').insert([
        for (final p in visit.prescriptions) {'visit_id': visitId, ...p.toInsert()},
      ]);
    }
  }

  @override
  Future<String> redeemConsentCode(String code) async {
    final res = await _client
        .rpc('carebridge_redeem_consent_code', params: {'p_code': code.trim()});
    return res as String; // patient_id
  }

  @override
  Future<List<PatientSearchResult>> lookupForRequest(String query) async {
    final res = await _client.rpc(
      'carebridge_lookup_patient_for_request',
      params: {'p_query': query.trim()},
    );
    return [
      for (final m in (res as List))
        PatientSearchResult.fromMap(m as Map<String, dynamic>)
    ];
  }

  @override
  Future<void> requestAccess(String patientId) =>
      _client.rpc('carebridge_request_access', params: {'p_patient': patientId});
}

final doctorRepositoryProvider = Provider<DoctorRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a DoctorRepository override.');
  }
  return SupabaseDoctorRepository(SupabaseService.client);
});
