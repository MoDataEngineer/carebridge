import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'doctor_models.dart';
import 'doctor_repository.dart';

/// Flow A — redeem a patient's in-person consent code into a standing grant.
Future<void> showRedeemConsentCodeDialog(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add patient by consent code'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Consent code',
          hintText: 'Code the patient is showing you',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Redeem')),
      ],
    ),
  );
  if (ok != true || ctrl.text.trim().isEmpty) return;
  if (!context.mounted) return;
  try {
    await ref.read(doctorRepositoryProvider).redeemConsentCode(ctrl.text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access granted — search to open the patient')));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Invalid or expired code: $e')));
    }
  }
}

/// Flow B — look up a patient by phone/ABHA and send an access request.
Future<void> showRequestAccessDialog(
  BuildContext context,
  WidgetRef ref,
  DoctorScope scope,
) async {
  final ctrl = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      List<PatientSearchResult> results = const [];
      bool searching = false;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Request access'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Patient phone or ABHA (exact)',
                ),
                onSubmitted: (_) async {
                  setLocal(() => searching = true);
                  results = await ref
                      .read(doctorRepositoryProvider)
                      .lookupForRequest(ctrl.text);
                  setLocal(() => searching = false);
                },
              ),
              const SizedBox(height: 12),
              if (searching) const LinearProgressIndicator(),
              for (final p in results)
                ListTile(
                  dense: true,
                  title: Text(p.name),
                  subtitle: Text(p.phone),
                  trailing: TextButton(
                    onPressed: () async {
                      await ref.read(doctorRepositoryProvider).requestAccess(p.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Request sent — awaiting patient approval')));
                      }
                    },
                    child: const Text('Request'),
                  ),
                ),
              if (!searching && results.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Enter an exact phone/ABHA and press enter.',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    },
  );
}
