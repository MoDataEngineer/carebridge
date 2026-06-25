import '../../shared/models/enums.dart';

// Phase 4 reuses the read-only VisitRecord/PrescriptionRecord from the patient
// feature for the doctor-facing history view — same shape, one source of truth.
export '../patient/patient_models.dart' show VisitRecord, PrescriptionRecord;

/// The active scope a doctor-app screen runs under, derived from the live D2
/// session. Drives the UI's AC-9 gate: only a doctor-scoped session may author a
/// visit, so `canWrite` is false for a bare admin (the DB enforces this too).
class DoctorScope {
  const DoctorScope({required this.role, required this.clinicId, this.doctorId});
  final ActiveRole role;
  final String clinicId;
  final String? doctorId;

  /// AC-9: writing clinical data requires a specific doctor identity.
  bool get canWrite => role == ActiveRole.doctor && doctorId != null;
}

/// One row in a scoped patient search result (Section 5.2). The rows a session
/// can see are decided at the database (RLS), not here — doctor-scoped returns
/// only the doctor's own granted patients, admin-scoped returns all clinic
/// patients with any active grant (AC-8).
class PatientSearchResult {
  const PatientSearchResult({
    required this.id,
    required this.name,
    required this.phone,
    this.abhaId,
  });

  final String id;
  final String name;
  final String phone;
  final String? abhaId;

  factory PatientSearchResult.fromMap(Map<String, dynamic> m) => PatientSearchResult(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        abhaId: m['abha_id'] as String?,
      );
}

/// One prescription line being authored on a new visit (D5 structured schedule).
class NewPrescription {
  const NewPrescription({
    required this.drugName,
    this.dosage,
    this.schedule = const {'morning': false, 'afternoon': false, 'night': false},
    this.relationToFood = FoodRelation.none,
    this.durationDays,
    this.instructions,
  });

  final String drugName;
  final String? dosage;
  final Map<String, bool> schedule; // {morning, afternoon, night}
  final FoodRelation relationToFood;
  final int? durationDays;
  final String? instructions;

  Map<String, dynamic> toInsert() => {
        'drug_name': drugName,
        'dosage': dosage,
        'schedule': schedule,
        'relation_to_food': _foodRelationDb(relationToFood),
        'duration_days': durationDays,
        'instructions': instructions,
      };

  // The Dart enum name `withFood` maps to the Postgres food_relation value 'with'.
  static String _foodRelationDb(FoodRelation r) =>
      r == FoodRelation.withFood ? 'with' : r.name;
}

/// A new visit being authored by a doctor-scoped session (AC-9).
class NewVisit {
  const NewVisit({
    required this.diagnosis,
    this.notes,
    this.followUpDate,
    this.prescriptions = const [],
  });

  final String diagnosis;
  final String? notes;
  final DateTime? followUpDate;
  final List<NewPrescription> prescriptions;
}
