import 'enums.dart';

/// Lightweight immutable data classes mirroring the core tables
/// (supabase/migrations/0001_init.sql). Phase 1 ships only the entities the
/// scaffold references conceptually; more fields/models are added per phase as
/// real data flows are built. JSON wiring (fromMap/toMap) lands when a screen
/// actually reads/writes the table.

class Patient {
  const Patient({
    required this.id,
    this.abhaId, // D3: nullable for the pilot
    required this.name,
    required this.phone,
    this.dob,
    this.allergies = const [],
    this.chronicConditions = const [],
    this.currentMedications = const [],
  });

  final String id;
  final String? abhaId;
  final String name;
  final String phone;
  final DateTime? dob;
  final List<String> allergies;
  final List<String> chronicConditions;
  final List<String> currentMedications;
}

class Clinic {
  const Clinic({
    required this.id,
    required this.name,
    required this.registrationNumber,
    this.hfrId,
    this.subscriptionStatus = SubscriptionStatus.free,
  });

  final String id;
  final String name;
  final String registrationNumber;
  final String? hfrId;
  final SubscriptionStatus subscriptionStatus;
}

class Doctor {
  const Doctor({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.councilRegNumber,
    required this.councilName,
    required this.specialty,
    this.hprId,
    this.hprVerified = false,
    this.isActive = true,
  });

  final String id;
  final String clinicId; // every doctor belongs to a clinic (solo = clinic of one)
  final String name;
  final String councilRegNumber;
  final String councilName;
  final String specialty;
  final String? hprId;
  final bool hprVerified;
  final bool isActive;
}

/// Carried in the D2 scoped JWT; never trusted from client state for access.
class ScopeClaims {
  const ScopeClaims({
    required this.clinicId,
    required this.activeRole,
    this.activeDoctorId,
  });

  final String clinicId;
  final ActiveRole activeRole;
  final String? activeDoctorId; // null for a pure-admin session
}
