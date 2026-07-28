// Phase 5 consent / access-grant view models (Section 7, patient-facing).

/// An active grant shown in "Doctors with access" — one-tap revocable.
class GrantView {
  const GrantView({
    required this.grantId,
    required this.doctorId,
    required this.doctorName,
    required this.clinicName,
    required this.type,
    required this.grantedAt,
  });

  final String grantId;
  final String doctorId;
  final String doctorName;
  final String clinicName;
  final String type; // standing | one_time | order_scoped
  final DateTime? grantedAt;
}

/// A pending Flow B request awaiting the patient's approve/deny.
class AccessRequestView {
  const AccessRequestView({
    required this.grantId,
    required this.doctorName,
    required this.clinicName,
    this.requestedAt,
  });

  final String grantId;
  final String doctorName;
  final String clinicName;
  final DateTime? requestedAt;
}

/// One plain-language row in "Who viewed my records" (Section 7).
class AccessLogView {
  const AccessLogView({
    required this.accessorType, // doctor | clinic_admin | diagnostic_partner
    required this.accessorLabel,
    required this.viewedAt,
    this.whatViewed,
  });

  final String accessorType;
  final String accessorLabel;
  final DateTime viewedAt;
  final String? whatViewed;

  /// "Dr Rao (doctor)" style label distinguishing accessor kind.
  String get plainLabel {
    final kind = switch (accessorType) {
      'doctor' => 'doctor',
      'clinic_admin' => 'clinic admin',
      'diagnostic_partner' => 'diagnostic partner',
      _ => accessorType,
    };
    return '$accessorLabel ($kind)';
  }
}

/// A freshly minted Flow A consent code for the patient to show in person.
class ConsentCode {
  const ConsentCode({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;
}
