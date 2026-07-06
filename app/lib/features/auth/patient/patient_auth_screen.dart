import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'patient_auth_repository.dart';

/// Patient sign-in (D3: phone-first; ABHA linking offered inline, not
/// hard-blocking while ABDM is mocked).
///
/// PLACEHOLDER: signs the phone in WITHOUT OTP verification (demo only) — but
/// it now establishes a REAL patient GoTrue session, so the patient RLS
/// policies apply. Real ABDM/SMS OTP lands in Phase 11.
class PatientAuthScreen extends ConsumerStatefulWidget {
  const PatientAuthScreen({super.key});

  @override
  ConsumerState<PatientAuthScreen> createState() => _PatientAuthScreenState();
}

class _PatientAuthScreenState extends ConsumerState<PatientAuthScreen> {
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_phone.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter your 10-digit mobile number')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(patientAuthRepositoryProvider).login(_phone.text.trim());
      if (!mounted) return;
      context.go(Routes.patientHome);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Patient sign in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixText: '+91 ',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _signIn(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign in'),
          ),
          const SizedBox(height: 24),
          const _StubBanner(
            'Demo sign-in — the OTP step is not verified yet. Real ABDM/SMS '
            'OTP arrives in Phase 11.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {}, // Phase 11: inline create/link ABHA
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
