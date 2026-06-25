import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../shared/models/enums.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'clinic_models.dart';
import 'session_controller.dart';

/// "Who are you?" picker (Section 2.2). Shown ONLY for multi-doctor clinics —
/// a solo clinic is auto-scoped before this screen and never reaches it.
/// Each choice records a [ScopeTarget] and proceeds to PIN entry (D1); the PIN
/// is what actually scopes the session.
class WhoAreYouScreen extends ConsumerWidget {
  const WhoAreYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clinicSessionControllerProvider.notifier);
    final login = ref.watch(clinicSessionControllerProvider).login;
    final doctors = login?.doctors ?? const <DoctorSummary>[];

    void pick(ScopeTarget target) {
      controller.chooseIdentity(target);
      context.push(Routes.pinEntry);
    }

    return ResponsiveScaffold(
      title: 'Who are you?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Select your identity to continue.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          for (final d in doctors)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(d.name),
                subtitle: Text('${d.specialty} · Doctor-scoped session'),
                trailing: const Icon(Icons.lock_outline),
                onTap: () => pick(ScopeTarget(
                  role: ActiveRole.doctor,
                  doctorId: d.id,
                  label: d.name,
                )),
              ),
            ),
          const Divider(height: 32),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Clinic Admin / View All'),
              subtitle: const Text('Admin-scoped — view all, cannot write clinical notes'),
              trailing: const Icon(Icons.lock_outline),
              onTap: () => pick(const ScopeTarget(
                role: ActiveRole.admin,
                label: 'Clinic Admin',
              )),
            ),
          ),
        ],
      ),
    );
  }
}
