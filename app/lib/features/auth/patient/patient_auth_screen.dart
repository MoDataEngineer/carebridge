import 'package:flutter/material.dart';

import '../../../core/config/env.dart';
import '../../../shared/widgets/responsive_scaffold.dart';

/// Placeholder patient auth (Phase 1).
/// D3: phone + OTP first; ABHA linking offered inline, NOT hard-blocking while
/// ABDM is mocked. `REQUIRE_ABHA` (default false) flips behavior in Phase 11.
///
/// STUB: no real OTP/SMS or ABDM calls yet. Needs ABDM sandbox keys to make real.
class PatientAuthScreen extends StatelessWidget {
  const PatientAuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Patient sign in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const TextField(
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Mobile number',
              prefixText: '+91 ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {}, // Phase 3: send OTP
            child: const Text('Send OTP'),
          ),
          const SizedBox(height: 24),
          const _StubBanner(
            'Placeholder auth — OTP/SMS not wired. Needs ABDM sandbox keys.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {}, // Phase 3: inline create/link ABHA
            icon: const Icon(Icons.link),
            label: Text(
              Env.requireAbha
                  ? 'Link ABHA (required)'
                  : 'Link ABHA (optional — recommended)',
            ),
          ),
        ],
      ),
    );
  }
}

class _StubBanner extends StatelessWidget {
  const _StubBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
