import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../shared/widgets/responsive_scaffold.dart';

/// Placeholder "Who are you?" picker (Phase 1 skeleton).
/// Section 2.2 + D1:
///   - Solo clinic (exactly one doctor) => this screen is SKIPPED; session is
///     auto-scoped as doctor + admin. (Wired in Phase 2.)
///   - Multi-doctor clinic => list each doctor + a "Clinic Admin / View All"
///     option; selecting any identity then requires that identity's PIN (D1).
///
/// Phase 1 shows mock identities so the navigation path exists. The auto-skip
/// rule and PIN gating become real in Phase 2.
class WhoAreYouScreen extends StatelessWidget {
  const WhoAreYouScreen({super.key});

  // Mock roster — replaced by real clinic doctors in Phase 2.
  static const _mockDoctors = ['Dr. Asha Rao', 'Dr. Vivek Menon'];

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Who are you?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Select your identity to continue.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          for (final name in _mockDoctors)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(name),
                subtitle: const Text('Doctor-scoped session'),
                trailing: const Icon(Icons.lock_outline),
                onTap: () => context.push(Routes.pinEntry), // D1: PIN next
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
              onTap: () => context.push(Routes.pinEntry), // D1: admin PIN next
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Phase 1 skeleton — real roster, solo auto-skip, and PIN gating land in Phase 2.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
