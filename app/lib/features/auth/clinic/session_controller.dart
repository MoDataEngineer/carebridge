import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/enums.dart';
import 'clinic_auth_repository.dart';
import 'clinic_models.dart';

/// Holds the clinic-session state across the login -> picker -> PIN flow.
class ClinicSessionState {
  const ClinicSessionState({this.login, this.pendingTarget, this.active});

  final ClinicLoginResult? login;     // result of clinic login (roster + base token)
  final ScopeTarget? pendingTarget;   // identity chosen, awaiting PIN
  final ScopedSession? active;        // PIN-unlocked scoped session

  ClinicSessionState copyWith({
    ClinicLoginResult? login,
    ScopeTarget? pendingTarget,
    ScopedSession? active,
  }) =>
      ClinicSessionState(
        login: login ?? this.login,
        pendingTarget: pendingTarget ?? this.pendingTarget,
        active: active ?? this.active,
      );
}

class ClinicSessionController extends StateNotifier<ClinicSessionState> {
  ClinicSessionController(this._repo) : super(const ClinicSessionState());
  final ClinicAuthRepository _repo;

  /// Clinic login. Returns the result so the caller can route.
  /// CRITICAL (Section 2.2 / guarantee a): a solo clinic (exactly one doctor) is
  /// auto-scoped to that doctor here and the "Who are you?" picker is skipped.
  /// Only a multi-doctor clinic gets a pending picker.
  Future<ClinicLoginResult> login({
    required String phone,
    String? otpCode,
  }) async {
    final result = await _repo.login(
      phone: phone,
      otpCode: otpCode,
    );

    ScopeTarget? pending;
    if (result.isDoctorLogin) {
      // D13: signed in with a doctor's OWN mobile — pre-scope to that doctor;
      // the picker is skipped and they only enter their PIN.
      pending = ScopeTarget(
        role: ActiveRole.doctor,
        doctorId: result.preselectedDoctorId,
        label: result.preselectedDoctorName,
      );
    } else if (result.isSolo) {
      // Solo practitioner = sole doctor + admin. Auto-scope to the one doctor;
      // no picker is ever shown.
      final only = result.doctors.first;
      pending = ScopeTarget(role: ActiveRole.doctor, doctorId: only.id, label: only.name);
    }
    state = ClinicSessionState(login: result, pendingTarget: pending);
    return result;
  }

  /// Register a NEW hospital, land logged in with an empty roster. The caller
  /// routes to "Who are you?" where only the Admin tile shows; unlocking as
  /// admin lets them add doctor profiles (roster management is admin-scoped).
  Future<ClinicLoginResult> register({
    required String name,
    required String registrationNumber,
    required String phone,
    required String state,
    required String city,
    required String adminPin,
    String? address,
  }) async {
    final result = await _repo.register(
      name: name,
      registrationNumber: registrationNumber,
      phone: phone,
      state: state,
      city: city,
      adminPin: adminPin,
      address: address,
    );
    // `state` (the String param) shadows StateNotifier.state here.
    super.state = ClinicSessionState(login: result);
    return result;
  }

  /// Add a freshly-created doctor to the in-memory roster so the picker and
  /// manage-doctors screens reflect it without a re-login.
  void doctorAdded(DoctorSummary doctor) {
    final login = state.login;
    if (login == null) return;
    state = ClinicSessionState(
      login: ClinicLoginResult(
        clinicId: login.clinicId,
        clinicName: login.clinicName,
        baseToken: login.baseToken,
        paid: login.paid,
        verified: login.verified,
        doctors: [...login.doctors, doctor],
      ),
      pendingTarget: state.pendingTarget,
      active: state.active,
    );
  }

  /// True only when an identity choice is required — i.e. a multi-doctor clinic.
  bool get needsPicker => (state.login?.doctors.length ?? 0) > 1;

  /// Record the identity chosen in the picker, before PIN entry.
  void chooseIdentity(ScopeTarget target) {
    state = state.copyWith(pendingTarget: target);
  }

  /// Verify the pending identity's PIN and mint the scoped session (D2).
  Future<ScopedSession> unlockWithPin(String pin) async {
    final login = state.login;
    final target = state.pendingTarget;
    if (login == null || target == null) {
      throw StateError('No pending identity to unlock.');
    }
    final session = (await _repo.mintScope(
      clinicId: login.clinicId,
      role: target.role,
      doctorId: target.doctorId,
      pin: pin,
    ))
        .withPaid(login.paid); // Section 9: tier known from login.
    state = state.copyWith(active: session);
    return session;
  }

  void signOut() => state = const ClinicSessionState();
}

final clinicSessionControllerProvider =
    StateNotifierProvider<ClinicSessionController, ClinicSessionState>((ref) {
  return ClinicSessionController(ref.watch(clinicAuthRepositoryProvider));
});
