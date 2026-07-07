import '../../../shared/models/enums.dart';

/// One doctor as shown in the "Who are you?" picker.
class DoctorSummary {
  const DoctorSummary({required this.id, required this.name, required this.specialty});
  final String id;
  final String name;
  final String specialty;

  factory DoctorSummary.fromMap(Map<String, dynamic> m) => DoctorSummary(
        id: m['id'] as String,
        name: m['name'] as String,
        specialty: (m['specialty'] ?? '') as String,
      );
}

/// Result of clinic login: the roster + a base (unscoped) token carrying only
/// `clinic_id`, used to fetch the roster before an identity is chosen.
class ClinicLoginResult {
  const ClinicLoginResult({
    required this.clinicId,
    required this.clinicName,
    required this.doctors,
    required this.baseToken,
    this.paid = false,
    this.verified = true,
    this.preselectedDoctorId,
    this.preselectedDoctorName,
  });

  final String clinicId;
  final String clinicName;
  final List<DoctorSummary> doctors;
  final String baseToken;

  /// Section 9: clinic subscription tier at login (server-derived).
  final bool paid;

  /// Audit H2: self-registered hospitals start unverified; the founder flips
  /// the flag after checking the registration number. Badge-only in the UI.
  final bool verified;

  /// D13: set only when the login was resolved by a DOCTOR's own mobile — the
  /// "Who are you?" picker is skipped and the session pre-scopes to this doctor
  /// (they still enter their PIN). Null for a hospital/admin login.
  final String? preselectedDoctorId;
  final String? preselectedDoctorName;

  /// True when the entry point already fixes the doctor identity — either a
  /// solo clinic (one doctor) or a doctor-phone login. Both skip the picker.
  bool get isSolo => doctors.length == 1;
  bool get isDoctorLogin => preselectedDoctorId != null;
  bool get skipsPicker => isSolo || isDoctorLogin;
}

/// The identity a session is being scoped to, chosen before PIN entry.
class ScopeTarget {
  const ScopeTarget({required this.role, this.doctorId, this.label});
  final ActiveRole role;       // doctor | admin
  final String? doctorId;      // required when role == doctor (AC-9)
  final String? label;         // display name for the PIN screen
}

/// A live, PIN-unlocked scoped session — wraps the short-lived D2 JWT whose
/// claims RLS reads.
class ScopedSession {
  const ScopedSession({
    required this.clinicId,
    required this.role,
    required this.doctorId,
    required this.accessToken,
    required this.expiresIn,
    this.paid = false,
  });

  final String clinicId;
  final ActiveRole role;
  final String? doctorId;
  final String accessToken;
  final int expiresIn;

  /// Section 9 paid tier, carried from the login result.
  final bool paid;

  ScopedSession withPaid(bool value) => ScopedSession(
        clinicId: clinicId,
        role: role,
        doctorId: doctorId,
        accessToken: accessToken,
        expiresIn: expiresIn,
        paid: value,
      );
}
