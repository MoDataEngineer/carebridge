import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/phone_otp.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'session_controller.dart';

/// Clinic login (Section 2.2): ONE credential per clinic. On success it branches
/// on the doctor count — solo clinics skip the "Who are you?" picker entirely
/// (guarantee a); multi-doctor clinics go to the picker.
///
/// Phase 11 (D12): the registered mobile gets a real SMS code (closes audit
/// H1 when enforced). While the SMS provider is not configured server-side,
/// falls back to the H1-interim registered-phone check.
class ClinicLoginScreen extends ConsumerStatefulWidget {
  const ClinicLoginScreen({super.key});

  @override
  ConsumerState<ClinicLoginScreen> createState() => _ClinicLoginScreenState();
}

class _ClinicLoginScreenState extends ConsumerState<ClinicLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _login({String? otpCode}) async {
    final controller = ref.read(clinicSessionControllerProvider.notifier);
    final result = await controller.login(
      phone: _phone.text.trim(),
      otpCode: otpCode,
    );
    if (!mounted) return;
    // Guarantee (a): solo clinic is auto-scoped — straight to PIN, no picker.
    if (result.isSolo) {
      context.push(Routes.pinEntry);
    } else {
      context.push(Routes.whoAreYou);
    }
  }

  Future<void> _continue() async {
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = 'Enter the 10-digit registered mobile number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await ref.read(phoneOtpProvider).sendCode(_phone.text.trim());
      if (sent) {
        if (mounted) setState(() => _codeSent = true);
      } else {
        await _login(); // H1-interim path (registered-phone check server-side)
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _login(otpCode: _code.text.trim());
    } catch (e) {
      if (mounted) setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Hospital sign in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 2026-07-06: login is by mobile alone — the registration number is
          // collected once at registration and shown to patients as a trust
          // signal, not used as a login credential.
          TextField(
            controller: _phone,
            enabled: !_codeSent,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Registered mobile number',
              prefixText: '+91 ',
              border: OutlineInputBorder(),
            ),
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
            onPressed: _busy ? null : (_codeSent ? _verify : _continue),
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_codeSent ? 'Verify code' : 'Continue'),
          ),
          if (_codeSent)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _codeSent = false;
                        _code.clear();
                      }),
              child: const Text('Change details'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.hospitalRegister),
            icon: const Icon(Icons.add_business),
            label: const Text('New hospital? Register here'),
          ),
          const SizedBox(height: 16),
          Text(
            'One login per hospital; doctors are added under it (Section 2.2) — '
            'solo doctors register their practice the same way. An SMS code is '
            'sent to the registered mobile once OTP (MSG91) is set up.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
