import 'package:go_router/go_router.dart';

import '../../features/auth/clinic/clinic_home_screen.dart';
import '../../features/auth/clinic/clinic_login_screen.dart';
import '../../features/auth/clinic/hospital_register_screen.dart';
import '../../features/auth/clinic/pin_entry_screen.dart';
import '../../features/auth/clinic/who_are_you_screen.dart';
import '../../features/auth/diagnostic/diagnostic_login_screen.dart';
import '../../features/diagnostics/diagnostic_portal_screen.dart';
import '../../features/auth/patient/patient_auth_screen.dart';
import '../../features/entry/entry_screen.dart';
import '../../features/patient/patient_home_screen.dart';

/// Route names — role-based routing from the three-button entry screen (Section 2).
class Routes {
  const Routes._();

  static const entry = '/';
  static const patientAuth = '/patient';
  static const patientHome = '/patient/home';
  static const clinicLogin = '/clinic';
  static const hospitalRegister = '/clinic/register';
  static const whoAreYou = '/clinic/who-are-you';
  static const pinEntry = '/clinic/pin';
  static const clinicHome = '/clinic/home';
  static const diagnosticLogin = '/diagnostic';
  static const diagnosticPortal = '/diagnostic/portal';
}

/// Builds a fresh router. Use the factory (not a shared global) so each widget
/// test starts with clean navigation state; `main` holds one instance via
/// [appRouter]. Phase 1 wires the entry screen + placeholder auth for all three
/// roles. Real session scoping (D1/D2) attaches in Phase 2.
GoRouter createAppRouter() => GoRouter(
  initialLocation: Routes.entry,
  routes: [
    GoRoute(
      path: Routes.entry,
      builder: (_, __) => const EntryScreen(),
    ),
    GoRoute(
      path: Routes.patientAuth,
      builder: (_, __) => const PatientAuthScreen(),
    ),
    GoRoute(
      path: Routes.patientHome,
      builder: (_, __) => const PatientHomeScreen(),
    ),
    GoRoute(
      path: Routes.clinicLogin,
      builder: (_, __) => const ClinicLoginScreen(),
    ),
    GoRoute(
      path: Routes.hospitalRegister,
      builder: (_, __) => const HospitalRegisterScreen(),
    ),
    GoRoute(
      path: Routes.whoAreYou,
      builder: (_, __) => const WhoAreYouScreen(),
    ),
    GoRoute(
      path: Routes.pinEntry,
      builder: (_, __) => const PinEntryScreen(),
    ),
    GoRoute(
      path: Routes.clinicHome,
      builder: (_, __) => const ClinicHomeScreen(),
    ),
    GoRoute(
      path: Routes.diagnosticLogin,
      builder: (_, __) => const DiagnosticLoginScreen(),
    ),
    GoRoute(
      path: Routes.diagnosticPortal,
      builder: (_, __) => const DiagnosticPortalScreen(),
    ),
  ],
);

/// Single instance used by the running app.
final appRouter = createAppRouter();
