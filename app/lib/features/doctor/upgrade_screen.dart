import 'package:flutter/material.dart';

/// Upgrade stub (Section 9): no payment gateway in MVP — the founder flips
/// clinics.subscription_status in the Supabase dashboard. Razorpay/Stripe-style
/// integration replaces this screen later.
class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  static const _paidFeatures = [
    'One-touch AI patient summary',
    'Follow-up tracker with one-tap reminders',
    'Voice prescription input',
    'Prescription templates & autocomplete',
    'Live appointment / token tracker',
    'Automated no-show reminders',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.workspace_premium,
                    size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text('Ayulekha Pro',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                for (final f in _paidFeatures)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(f),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Payments coming soon — contact Ayulekha to upgrade.'))),
                  child: const Text('Contact us to upgrade'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
