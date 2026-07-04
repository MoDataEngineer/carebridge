import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/breakpoints.dart';
import '../../shared/widgets/role_button.dart';

/// THE entry screen (Section 2): three buttons, nothing else.
/// Founder decision 2026-07-04: the clinic entry is labelled "Hospital"
/// (was "Doctor" in the original spec). Hospitals self-register and add
/// doctor profiles under themselves — solo doctors included.
/// Diagnostic Partner stays flat.
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = !Breakpoints.isMobile(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.health_and_safety,
                    size: wide ? 72 : 56,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('CareBridge',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text('Your health record, with your consent.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 48),
                RoleButton(
                  label: 'Patient',
                  icon: Icons.person,
                  onTap: () => context.push(Routes.patientAuth),
                ),
                const SizedBox(height: 16),
                RoleButton(
                  label: 'Hospital',
                  icon: Icons.local_hospital,
                  onTap: () => context.push(Routes.clinicLogin),
                ),
                const SizedBox(height: 16),
                RoleButton(
                  label: 'Diagnostic Partner',
                  icon: Icons.biotech,
                  onTap: () => context.push(Routes.diagnosticLogin),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
