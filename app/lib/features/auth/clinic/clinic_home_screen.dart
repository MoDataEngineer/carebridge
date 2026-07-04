import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../shared/models/enums.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import '../../doctor/doctor_models.dart';
import '../../doctor/doctor_workspace_screen.dart';
import 'manage_doctors_screen.dart';
import 'session_controller.dart';

/// Placeholder landing after a session is scoped. Confirms the active scope
/// (Phase 2 boundary); the doctor/admin feature screens come in Phase 4+.
class ClinicHomeScreen extends ConsumerWidget {
  const ClinicHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clinicSessionControllerProvider);
    final s = state.active;
    final roleLabel = s == null
        ? 'no active scope'
        : (s.role == ActiveRole.admin ? 'Admin-scoped (View All)' : 'Doctor-scoped');

    return ResponsiveScaffold(
      title: 'Clinic session',
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user, size: 48),
          const SizedBox(height: 12),
          Text('Session scope: $roleLabel',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          if (s?.doctorId != null) ...[
            const SizedBox(height: 8),
            Text('Doctor identity: ${s!.doctorId}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 24),
          if (s != null)
            FilledButton.icon(
              onPressed: () {
                final scope = DoctorScope(
                  role: s.role,
                  clinicId: s.clinicId,
                  doctorId: s.doctorId,
                );
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DoctorWorkspaceScreen(scope: scope),
                ));
              },
              icon: const Icon(Icons.people),
              label: const Text('Open patients'),
            ),
          // Roster management is admin-scoped (Section 5.2).
          if (s != null && s.role == ActiveRole.admin) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ManageDoctorsScreen(),
              )),
              icon: const Icon(Icons.badge),
              label: const Text('Manage doctors'),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(clinicSessionControllerProvider.notifier).signOut();
              context.go(Routes.entry);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
