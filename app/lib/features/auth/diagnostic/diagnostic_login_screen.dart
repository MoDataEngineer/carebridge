import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../shared/widgets/responsive_scaffold.dart';

/// Placeholder diagnostic partner login (Phase 1).
/// Section 2.3 + ID-5: FLAT login — no nested staff identification. One login
/// per lab/imaging center (registration/license number; optional HFR ID + NABL).
/// This asymmetry with the clinic structure is intentional.
///
/// STUB: no real auth. Needs lab-registry / HFR verification to make real.
class DiagnosticLoginScreen extends StatelessWidget {
  const DiagnosticLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Diagnostic partner sign in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const TextField(
            decoration: InputDecoration(
              labelText: 'Lab / diagnostic registration number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(
              labelText: 'HFR ID (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            // Placeholder auth (Phase 11 makes it real); enters the portal.
            onPressed: () => context.go(Routes.diagnosticPortal),
            child: const Text('Continue'),
          ),
          const SizedBox(height: 24),
          Text(
            'Placeholder auth — flat login, no nested staff (Section 2.3). '
            'Order-scoped access (Flow C) and report upload land in Phase 6.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
