import 'package:flutter/material.dart';
import '../../../shared/widgets/pills_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../shared/models/enums.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'clinic_auth_repository.dart';
import 'session_controller.dart';

/// PIN entry (D1). Verifies the chosen identity's PIN and mints the short-lived
/// scoped token (D2) via the Edge Function. No client-side role flipping —
/// switching identity returns here for the target PIN.
class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(clinicSessionControllerProvider.notifier).unlockWithPin(_pin.text.trim());
      if (mounted) context.go(Routes.clinicHome);
    } on PinRejected catch (e) {
      if (mounted) {
        setState(() => _error = e.reason == 'locked'
            ? 'Too many attempts — locked until ${e.lockedUntil}'
            : 'PIN rejected');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not verify PIN: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(clinicSessionControllerProvider).pendingTarget;
    final who = target?.label ??
        (target?.role == ActiveRole.admin ? 'Clinic Admin' : 'your identity');

    return ResponsiveScaffold(
      title: 'Enter PIN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Unlocking session for: $who',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'Numeric PIN',
              border: OutlineInputBorder(),
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _unlock,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: PillsLoader(size: 20))
                : const Text('Unlock session'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          Text(
            'The PIN is verified server-side (hashed, rate-limited) and mints a '
            'short-lived scoped token (D2). RLS reads that token — app state is '
            'never trusted.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
