import 'package:flutter/material.dart';

import '../../../shared/widgets/responsive_scaffold.dart';

/// Placeholder PIN entry (Phase 1 skeleton) — D1.
/// Selecting a doctor or "Clinic Admin / View All" requires that identity's
/// personal numeric PIN before the session is scoped.
///
/// Phase 2 makes this real: PIN verified against doctors.pin_hash /
/// clinics.admin_pin_hash (hashed, rate-limited), then the mint-scope-token
/// Edge Function (D2) issues the short-lived scoped JWT. No client-side role
/// flipping — switching identity re-prompts here.
class PinEntryScreen extends StatelessWidget {
  const PinEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Enter PIN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const TextField(
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: 'Numeric PIN',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {}, // Phase 2: verify PIN -> mint scoped JWT (D2)
            child: const Text('Unlock session'),
          ),
          const SizedBox(height: 24),
          Text(
            'Phase 1 skeleton — PIN is not verified yet. In Phase 2 this verifies '
            'against the hashed PIN (rate-limited) and mints a short-lived scoped '
            'token (D2). RLS reads that token; app state is never trusted.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
