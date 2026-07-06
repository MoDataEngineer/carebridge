import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../shared/constants/indian_states.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'session_controller.dart';

/// New-hospital registration (founder decision 2026-07-04): hospital name,
/// registration/license number, mobile, and an ADMIN PIN. One login per
/// hospital (Section 2.2); doctor profiles are added under it afterwards —
/// the same path for a solo doctor (a hospital of one).
class HospitalRegisterScreen extends ConsumerStatefulWidget {
  const HospitalRegisterScreen({super.key});

  @override
  ConsumerState<HospitalRegisterScreen> createState() => _HospitalRegisterScreenState();
}

class _HospitalRegisterScreenState extends ConsumerState<HospitalRegisterScreen> {
  final _name = TextEditingController();
  final _reg = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _pin = TextEditingController();
  final _address = TextEditingController();
  String? _state; // 2026-07-06: patients filter the directory by state/city
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _reg.dispose();
    _phone.dispose();
    _city.dispose();
    _pin.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_name.text.trim().isEmpty || _reg.text.trim().isEmpty) {
      setState(() => _error = 'Hospital name and registration number are required.');
      return;
    }
    if (_state == null || _city.text.trim().isEmpty) {
      setState(() => _error = 'State and city are required — patients find you by place.');
      return;
    }
    if (!RegExp(r'^[0-9]{4,6}$').hasMatch(_pin.text)) {
      setState(() => _error = 'Admin PIN must be 4–6 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(clinicSessionControllerProvider.notifier).register(
            name: _name.text.trim(),
            registrationNumber: _reg.text.trim(),
            phone: _phone.text.trim(),
            state: _state!,
            city: _city.text.trim(),
            adminPin: _pin.text,
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Hospital registered — unlock as Admin to add doctors')));
      // Empty roster -> only the Admin tile shows; unlocking it opens roster
      // management where doctor profiles are created.
      context.push(Routes.whoAreYou);
    } catch (e) {
      if (mounted) setState(() => _error = 'Registration failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Register your hospital',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Hospital / clinic name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reg,
            decoration: const InputDecoration(
              labelText: 'Hospital registration / license number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixText: '+91 ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _state,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'State',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final s in kIndianStates)
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: (v) => setState(() => _state = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _city,
            decoration: const InputDecoration(
              labelText: 'City / town',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Set an Admin PIN (4–6 digits)',
              helperText: 'Used to unlock the admin session and manage doctors',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Address (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _register,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Register hospital'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Text(
            'After registering, unlock as Admin to add your doctors (name, medical '
            'council registration number, council, specialty). A solo doctor follows '
            'the same steps — register the practice, then add yourself as its doctor.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
