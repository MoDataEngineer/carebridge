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
    this.queuePosition,
    this.doctorId,
    this.clinicName,
    this.doctorName,
  });

  final String id;
  final DateTime scheduledTime;
  final String status; // requested | scheduled | waiting | in_consultation | completed | cancelled
  final int? queuePosition; // token, assigned at check-in
  final String? doctorId;
  final String? clinicName;
  final String? doctorName;

  /// The live token flow happens on the visit day only.
  bool get isToday {
    final now = DateTime.now();
    return scheduledTime.year == now.year &&
        scheduledTime.month == now.month &&
        scheduledTime.day == now.day;
  }

  /// True while the patient is actively in today's queue.
  bool get isActiveToday =>
      isToday && (status == 'waiting' || status == 'in_consultation');
}

/// The doctor's live queue position, as a waiting patient may see it — the
/// current token and how many are waiting, no other patient's identity.
class NowServing {
  const NowServing({this.servingToken, this.waitingCount = 0});
  final int? servingToken;
  final int waitingCount;

  /// Patients ahead of [myToken] (null if unknown / already serving me).
  int? aheadOf(int? myToken) {
    if (myToken == null || servingToken == null) return null;
    final ahead = myToken - servingToken! - 1;
    return ahead < 0 ? 0 : ahead;
  }
}

/// One of a doctor's consultation sessions on a chosen date, with how full it
/// is (migration 0026). The patient books into one of these.
class AvailableSession {
  const AvailableSession({
    required this.sessionId,
    this.label,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.booked,
  });

  final String sessionId;
  final String? label;
  final String startTime; // 'HH:mm:ss'
  final String endTime;
  final int capacity;
  final int booked;

  int get remaining => capacity - booked;
  bool get full => remaining <= 0;

  /// 'HH:mm' window, e.g. "09:00–12:00".
  String get window => '${_hm(startTime)}–${_hm(endTime)}';
  static String _hm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

  factory AvailableSession.fromMap(Map<String, dynamic> m) => AvailableSession(
        sessionId: m['session_id'] as String,
        label: m['label'] as String?,
        startTime: (m['start_time'] ?? '').toString(),
        endTime: (m['end_time'] ?? '').toString(),
        capacity: (m['capacity'] ?? 0) as int,
        booked: (m['booked'] ?? 0) as int,
      );
}

/// Outcome of a booking request: within capacity confirms, overflow is pending.
class BookingResult {
  const BookingResult({required this.status, required this.booked, required this.capacity});
  final String status; // 'scheduled' (confirmed) | 'requested' (pending doctor)
  final int booked;
  final int capacity;
  bool get confirmed => status == 'scheduled';
}

/// Minimal bookable slot target — a doctor a patient can book with.
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
    this.photoUrl,
    this.logoUrl,
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

  /// Branding (0030): doctor photo + clinic logo, null when not uploaded —
  /// renderers fall back to initials (BrandAvatar).
  final String? photoUrl;
  final String? logoUrl;

  // Value equality by doctor id: the Book tab refetches the directory after
  // booking, and the dropdown's selected value must still match an item in
  // the freshly-built list (identity equality crashed the dropdown assert).
  @override
  bool operator ==(Object other) =>
      other is BookableDoctor && other.doctorId == doctorId;

  @override
  int get hashCode => doctorId.hashCode;
}
