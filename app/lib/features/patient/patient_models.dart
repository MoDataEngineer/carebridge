import '../../shared/models/enums.dart';

/// Patient profile — structured fields (Section 5.1). `abhaId` nullable (D3).
class PatientProfile {
  const PatientProfile({
    required this.id,
    required this.name,
    required this.phone,
    this.abhaId,
    this.dob,
    this.allergies = const [],
    this.chronicConditions = const [],
    this.currentMedications = const [],
  });

  final String id;
  final String name;
  final String phone;
  final String? abhaId;
  final DateTime? dob;
  final List<String> allergies;
  final List<String> chronicConditions;
  final List<String> currentMedications;

  PatientProfile copyWith({
    String? name,
    String? abhaId,
    DateTime? dob,
    List<String>? allergies,
    List<String>? chronicConditions,
    List<String>? currentMedications,
  }) =>
      PatientProfile(
        id: id,
        name: name ?? this.name,
        phone: phone,
        abhaId: abhaId ?? this.abhaId,
        dob: dob ?? this.dob,
        allergies: allergies ?? this.allergies,
        chronicConditions: chronicConditions ?? this.chronicConditions,
        currentMedications: currentMedications ?? this.currentMedications,
      );

  factory PatientProfile.fromMap(Map<String, dynamic> m) => PatientProfile(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        abhaId: m['abha_id'] as String?,
        dob: m['dob'] != null ? DateTime.tryParse(m['dob'].toString()) : null,
        allergies: _strList(m['allergies']),
        chronicConditions: _strList(m['chronic_conditions']),
        currentMedications: _strList(m['current_medications']),
      );

  static List<String> _strList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];
}

/// One read-only prescription line on a visit (D5 structured schedule).
class PrescriptionRecord {
  const PrescriptionRecord({
    required this.drugName,
    this.dosage,
    this.schedule = const {},
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

  /// Human-readable schedule, e.g. "Morning, Night".
  String get scheduleLabel {
    const order = ['morning', 'afternoon', 'night'];
    final on = order.where((k) => schedule[k] == true).map(
          (k) => k[0].toUpperCase() + k.substring(1),
        );
    return on.isEmpty ? '—' : on.join(', ');
  }
}

/// One read-only visit in the patient's history (Section 5.1).
class VisitRecord {
  const VisitRecord({
    required this.id,
    required this.visitDate,
    this.diagnosis,
    this.notes,
    this.followUpDate,
    this.prescriptions = const [],
  });

  final String id;
  final DateTime visitDate;
  final String? diagnosis;
  final String? notes;
  final DateTime? followUpDate;
  final List<PrescriptionRecord> prescriptions;
}

/// An appointment the patient has booked.
class AppointmentRecord {
  const AppointmentRecord({
    required this.id,
    required this.scheduledTime,
    required this.status,
    this.clinicName,
    this.doctorName,
  });

  final String id;
  final DateTime scheduledTime;
  final String status;
  final String? clinicName;
  final String? doctorName;
}

/// Minimal bookable slot target for Phase 3 (real availability is Phase 10).
class BookableDoctor {
  const BookableDoctor({
    required this.doctorId,
    required this.clinicId,
    required this.doctorName,
    required this.clinicName,
    this.specialty = '',
    this.councilRegNumber = '',
    this.councilName = '',
    this.hprVerified = false,
    this.city = '',
    this.state = '',
  });
  final String doctorId;
  final String clinicId;
  final String doctorName;
  final String clinicName;
  final String specialty;

  /// Trust signals shown to patients (2026-07-06): the doctor's council
  /// registration number is always visible; the badge appears only when the
  /// HPR id has been verified (founder-set until the Phase 11b HPR check).
  final String councilRegNumber;
  final String councilName;
  final bool hprVerified;

  /// Directory filters — where the hospital is.
  final String city;
  final String state;

  // Value equality by doctor id: the Book tab refetches the directory after
  // booking, and the dropdown's selected value must still match an item in
  // the freshly-built list (identity equality crashed the dropdown assert).
  @override
  bool operator ==(Object other) =>
      other is BookableDoctor && other.doctorId == doctorId;

  @override
  int get hashCode => doctorId.hashCode;
}
