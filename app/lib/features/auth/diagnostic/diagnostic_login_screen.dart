import 'package:flutter/material.dart';
import '../../../shared/widgets/pills_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'diagnostic_auth_repository.dart';

/// Diagnostic partner sign in — REAL auth (audit gap 4 closed 2026-07-18).
/// Section 2.3 + ID-5: FLAT login — one credential per lab/imaging centre
/// (registration/license number + PIN), no nested staff. Registration collects
/// name, type, phone, PIN, optional HFR ID and NABL badge; new labs start
/// unverified until the founder confirms the registration number (like H2).
class DiagnosticLoginScreen extends ConsumerStatefulWidget {
  const DiagnosticLoginScreen({super.key});

  @override
  ConsumerState<DiagnosticLoginScreen> createState() =>
      _DiagnosticLoginScreenState();
}

class _DiagnosticLoginScreenState extends ConsumerState<DiagnosticLoginScreen> {
  final _reg = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reg.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_reg.text.trim().isEmpty || _pin.text.isEmpty) {
      setState(() => _error = 'Enter your registration number and PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(diagnosticAuthRepositoryProvider).login(
            registrationNumber: _reg.text.trim(),
            pin: _pin.text,
          );
      if (mounted) context.go(Routes.diagnosticPortal);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e.toString().replaceFirst(RegExp(r'^(Bad state: |Exception: )'), ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRegister() async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _PartnerRegisterScreen()),
    );
    if (registered == true && mounted) context.go(Routes.diagnosticPortal);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Diagnostic partner sign in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _reg,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Lab / diagnostic registration number',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            enabled: !_busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(
              labelText: 'PIN',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: PillsLoader(size: 20))
                : const Text('Sign in'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          TextButton(
            onPressed: _busy ? null : _openRegister,
            child: const Text('New lab / imaging centre? Register here'),
          ),
          const SizedBox(height: 8),
          Text(
            'One login per centre — no staff accounts (flat by design). '
            'Orders are only visible via their order code, never patient history.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// ID-5 registration: name + registration number (mandatory) + phone + PIN,
/// optional HFR ID and NABL accreditation. Signs in on success.
class _PartnerRegisterScreen extends ConsumerStatefulWidget {
  const _PartnerRegisterScreen();

  @override
  ConsumerState<_PartnerRegisterScreen> createState() =>
      _PartnerRegisterScreenState();
}

class _PartnerRegisterScreenState
    extends ConsumerState<_PartnerRegisterScreen> {
  final _name = TextEditingController();
  final _reg = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  final _hfr = TextEditingController();
  String _type = 'both';
  bool _nabl = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _reg.dispose();
    _phone.dispose();
    _pin.dispose();
    _hfr.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final phone = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (_name.text.trim().isEmpty || _reg.text.trim().isEmpty) {
      setState(() => _error = 'Name and registration number are required.');
      return;
    }
    if (phone.length != 10) {
      setState(() => _error = 'Enter a 10-digit mobile number.');
      return;
    }
    if (_pin.text.length < 4) {
      setState(() => _error = 'Choose a PIN of at least 4 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(diagnosticAuthRepositoryProvider).register(
            name: _name.text.trim(),
            registrationNumber: _reg.text.trim(),
            phone: phone,
            pin: _pin.text,
            type: _type,
            hfrId: _hfr.text.trim().isEmpty ? null : _hfr.text.trim(),
            nablAccredited: _nabl,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e.toString().replaceFirst(RegExp(r'^(Bad state: |Exception: )'), ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Register diagnostic centre',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Centre name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reg,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Registration / license number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'lab', child: Text('Pathology lab')),
              DropdownMenuItem(value: 'imaging', child: Text('Imaging centre')),
              DropdownMenuItem(value: 'both', child: Text('Lab + imaging')),
            ],
            onChanged: _busy ? null : (v) => setState(() => _type = v ?? 'both'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixText: '+91 ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            enabled: !_busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(
              labelText: 'Choose a PIN (4–8 digits)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hfr,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'HFR ID (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            value: _nabl,
            onChanged: _busy ? null : (v) => setState(() => _nabl = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('NABL accredited'),
          ),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: _busy ? null : _register,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: PillsLoader(size: 20))
                : const Text('Register & sign in'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 8),
          Text(
            'Ayulekha will confirm your registration number shortly — you can '
            'start receiving orders meanwhile.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
