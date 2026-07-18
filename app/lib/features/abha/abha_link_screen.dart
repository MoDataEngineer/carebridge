import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'abdm_models.dart';
import 'abdm_repository.dart';

/// Which ABHA flow this screen runs.
enum AbhaLinkMode {
  /// Create a brand-new ABHA from an Aadhaar (ID-2 inline create).
  create,

  /// Verify/link an existing ABHA number (ID-1).
  verify,
}

/// Consent language shown before an Aadhaar-based create (CRT_ABHA_102). Kept
/// verbatim-simple; the founder should replace it with ABDM's approved wording
/// before real launch (flagged, not silently final).
const _consentText =
    'I voluntarily consent to share my Aadhaar details for the purpose of '
    'creating my ABHA (Ayushman Bharat Health Account). I understand my Aadhaar '
    'number is used only to verify my identity with ABDM and is never stored by '
    'Ayulekha.';

/// The in-app ABHA linking flow (ID-1 / ID-2). A two-step stepper — enter the
/// identifier, then the OTP — ending on a success card. On success it pops with
/// the resulting [AbhaProfile]; the caller persists `abhaNumber` to the profile.
///
/// All ABDM work happens server-side via [AbdmRepository]; this widget only ever
/// holds the Aadhaar/OTP long enough to pass them to the repository call.
class AbhaLinkScreen extends ConsumerStatefulWidget {
  const AbhaLinkScreen({super.key, required this.mode});
  final AbhaLinkMode mode;

  @override
  ConsumerState<AbhaLinkScreen> createState() => _AbhaLinkScreenState();
}

class _AbhaLinkScreenState extends ConsumerState<AbhaLinkScreen> {
  final _id = TextEditingController(); // Aadhaar (create) or ABHA no. (verify)
  final _otp = TextEditingController();
  final _mobile = TextEditingController(); // create only

  bool get _isCreate => widget.mode == AbhaLinkMode.create;

  bool _consent = false;
  bool _busy = false;
  String? _error;
  AbhaOtpChallenge? _challenge; // set once OTP is sent → step 2
  AbhaProfile? _result; // set on success → success card

  @override
  void dispose() {
    _id.dispose();
    _otp.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Strip the StateError("…") wrapper for a clean on-screen message.
  String _clean(Object e) =>
      e.toString().replaceFirst(RegExp(r'^(Bad state: |Exception: )'), '');

  Future<void> _sendOtp() async {
    final id = _id.text.replaceAll(RegExp(r'[\s-]'), '');
    if (_isCreate && !RegExp(r'^\d{12}$').hasMatch(id)) {
      setState(() => _error = 'Enter your 12-digit Aadhaar number.');
      return;
    }
    if (!_isCreate && !RegExp(r'^\d{14}$').hasMatch(id)) {
      setState(() => _error = 'Enter your 14-digit ABHA number.');
      return;
    }
    if (_isCreate && !_consent) {
      setState(() => _error = 'Please agree to the consent to continue.');
      return;
    }
    await _run(() async {
      final repo = ref.read(abdmRepositoryProvider);
      final ch = _isCreate
          ? await repo.createRequestOtp(id)
          : await repo.loginRequestOtp(id);
      if (mounted) {
        setState(() {
          _challenge = ch;
          _otp.clear();
        });
      }
    });
  }

  Future<void> _verifyOtp() async {
    final ch = _challenge;
    if (ch == null) return;
    if (_otp.text.trim().length < 6) {
      setState(() => _error = 'Enter the 6-digit OTP.');
      return;
    }
    if (_isCreate && _mobile.text.replaceAll(RegExp(r'\D'), '').length != 10) {
      setState(() => _error = 'Enter your 10-digit mobile number.');
      return;
    }
    await _run(() async {
      final repo = ref.read(abdmRepositoryProvider);
      final profile = _isCreate
          ? await repo.createVerify(
              txnId: ch.txnId,
              otp: _otp.text.trim(),
              mobile: _mobile.text.replaceAll(RegExp(r'\D'), ''),
            )
          : await repo.loginVerify(txnId: ch.txnId, otp: _otp.text.trim());
      if (mounted) setState(() => _result = profile);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? 'Create ABHA' : 'Verify ABHA'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_result != null)
              _SuccessCard(profile: _result!, onDone: () => Navigator.of(context).pop(_result))
            else ...[
              _StepHeader(
                step: _challenge == null ? 1 : 2,
                label: _challenge == null
                    ? (_isCreate ? 'Enter your Aadhaar number' : 'Enter your ABHA number')
                    : 'Enter the OTP',
              ),
              const SizedBox(height: 16),
              if (_challenge == null) ..._identifierStep() else ..._otpStep(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _ErrorText(_error!),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _identifierStep() => [
        TextField(
          controller: _id,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_isCreate ? 12 : 14),
          ],
          decoration: InputDecoration(
            labelText: _isCreate ? 'Aadhaar number' : 'ABHA number',
            hintText: _isCreate ? '12-digit Aadhaar' : '14-digit ABHA',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _busy ? null : _sendOtp(),
        ),
        if (_isCreate) ...[
          const SizedBox(height: 12),
          _ConsentTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _sendOtp,
          child: _busy ? const _Spinner() : const Text('Send OTP'),
        ),
        const SizedBox(height: 12),
        Text(
          _isCreate
              ? 'An OTP will be sent to the mobile number linked with your Aadhaar. '
                  'Your Aadhaar is used only to verify identity with ABDM — never stored.'
              : 'An OTP will be sent to the mobile number linked with your Aadhaar '
                  'for this ABHA.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];

  List<Widget> _otpStep() => [
        Text(_challenge!.message, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _otp,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(
            labelText: 'OTP',
            hintText: '6-digit code',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _busy ? null : _verifyOtp(),
        ),
        if (_isCreate) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _mobile,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixText: '+91 ',
              hintText: 'Your contact mobile for this ABHA',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _verifyOtp,
          child: _busy
              ? const _Spinner()
              : Text(_isCreate ? 'Create ABHA' : 'Verify'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _challenge = null),
          child: Text(_isCreate ? 'Change Aadhaar number' : 'Change ABHA number'),
        ),
      ];
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.label});
  final int step;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: scheme.primary,
          child: Text('$step',
              style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        Text('Step $step of 2', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('I agree', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_consentText, style: Theme.of(context).textTheme.bodySmall),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.profile, required this.onDone});
  final AbhaProfile profile;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.verified_user, color: scheme.primary, size: 48),
        const SizedBox(height: 12),
        Text('ABHA linked', textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (profile.photoBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(profile.photoBytes!,
                        width: 56, height: 56, fit: BoxFit.cover),
                  )
                else
                  CircleAvatar(radius: 28, child: Text(_initial)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      _kv(context, 'ABHA number', profile.abhaNumber),
                      if (profile.abhaAddress.isNotEmpty)
                        _kv(context, 'ABHA address', profile.abhaAddress),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }

  String get _initial =>
      profile.name.trim().isEmpty ? '?' : profile.name.trim()[0].toUpperCase();

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$k: ',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          TextSpan(
              text: v,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ])),
      );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: scheme.error)),
        ),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2));
}
