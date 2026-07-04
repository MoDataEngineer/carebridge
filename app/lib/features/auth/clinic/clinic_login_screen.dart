import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'session_controller.dart';

/// Clinic login (Section 2.2): ONE credential per clinic. On success it branches
/// on the doctor count — solo clinics skip the "Who are you?" picker entirely
/// (guarantee a); multi-doctor clinics go to the picker.
///
/// OTP verification is still placeholder (real auth is Phase 11); the
/// session-scoping architecture on top of it (D1 PIN, D2 scoped token) is real.
class ClinicLoginScreen extends ConsumerStatefulWidget {
  const ClinicLoginScreen({super.key});

  @override
  ConsumerState<ClinicLoginScreen> createState() => _ClinicLoginScreenState();
}

class _ClinicLoginScreenState extends ConsumerState<ClinicLoginScreen> {
  final _reg = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reg.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = ref.read(clinicSessionControllerProvider.notifier);
      final result = await controller.login(
        registrationNumber: _reg.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      // Guarantee (a): solo clinic is auto-scoped — straight to PIN, no picker.
      if (result.isSolo) {
        context.push(Routes.pinEntry);
      } else {
        context.push(Routes.whoAreYou);
      }
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
          TextField(
            controller: _reg,
            decoration: const InputDecoration(
              labelText: 'Clinic registration / license number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Registered mobile number',
              prefixText: '+91 ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _continue,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Continue'),
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
            'solo doctors register their practice the same way. '
            'OTP is placeholder until Phase 11.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
