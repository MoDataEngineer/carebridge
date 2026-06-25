import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../shared/widgets/responsive_scaffold.dart';

/// Placeholder clinic login (Phase 1).
/// Section 2.2: "Doctor" leads to a CLINIC-level login. ONE credential per clinic
/// (registration/license number + phone/OTP). Doctors live UNDER the clinic.
///
/// The real session-scoping architecture (D1 PIN, D2 scoped JWT, solo auto-scope,
/// "Who are you?" picker) is built in PHASE 2 — Phase 1 only lands the screens +
/// navigation skeleton so Phase 2 has somewhere to attach.
///
/// STUB: no real auth. Needs ABDM/clinic-registry verification to make real.
class ClinicLoginScreen extends StatelessWidget {
  const ClinicLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Clinic sign in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const TextField(
            decoration: InputDecoration(
              labelText: 'Clinic registration / license number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const TextField(
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Registered mobile number',
              prefixText: '+91 ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            // Phase 2: after real login, branch on doctor count —
            // solo => auto-scope (skip picker); multi => "Who are you?".
            onPressed: () => context.push(Routes.whoAreYou),
            child: const Text('Continue'),
          ),
          const SizedBox(height: 24),
          Text(
            'Placeholder auth — clinic verification not wired. '
            'One login per clinic; doctors are added under it (Section 2.2). '
            'Session scoping (PIN + scoped token) is built in Phase 2.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
