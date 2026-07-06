import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/config/phone_otp.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'patient_auth_repository.dart';

/// Patient sign-in (D3: phone-first; ABHA optional in pilot).
///
/// Phase 11 (D12): phone → SMS code → verified sign-in, with the OTP
/// generated/verified by our own backend (MSG91 sends the SMS). While the
/// SMS provider is not configured server-side, sendCode reports "not
/// configured" and the screen falls back to the demo (no-OTP) path.
class PatientAuthScreen extends ConsumerStatefulWidget {
  const PatientAuthScreen({super.key});

  @override
  ConsumerState<PatientAuthScreen> createState() => _PatientAuthScreenState();
}

class _PatientAuthScreenState extends ConsumerState<PatientAuthScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() step) async {
    setState(() => _busy = true);
    try {
      await step();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter your 10-digit mobile number')));
      return;
    }
    await _run(() async {
      final sent = await ref.read(phoneOtpProvider).sendCode(_phone.text.trim());
      if (sent) {
        if (mounted) setState(() => _codeSent = true);
      } else {
        // OTP not configured server-side — demo path (refused once
        // REQUIRE_OTP is flipped on).
        await ref.read(patientAuthRepositoryProvider).login(_phone.text.trim());
        if (mounted) context.go(Routes.patientHome);
      }
    });
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the 6-digit code from the SMS')));
      return;
    }
    await _run(() async {
      await ref
          .read(patientAuthRepositoryProvider)
          .login(_phone.text.trim(), otpCode: _code.text.trim());
      if (mounted) context.go(Routes.patientHome);
    });
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
            enabled: !_codeSent,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixText: '+91 ',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _codeSent ? null : _start(),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP code',
                hintText: '6-digit code from the SMS',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _verify(),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : (_codeSent ? _verify : _start),
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_codeSent ? 'Verify code' : 'Sign in'),
          ),
          if (_codeSent)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _codeSent = false;
                        _code.clear();
                      }),
              child: const Text('Change number'),
            ),
          const SizedBox(height: 24),
          const _StubBanner(
            'You\'ll get an SMS code when OTP is set up (MSG91). Until then '
            'this signs in directly — demo mode.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {}, // ABHA verification needs ABDM sandbox keys (Phase 11b)
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
