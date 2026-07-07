import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import 'session_controller.dart';

/// App-bar action that signs the clinic session out and returns to the entry
/// screen. Shared across the doctor/clinic destinations so every screen exposes
/// the same sign-out affordance. The provider is only read on tap (never at
/// build) so screens used standalone in tests don't touch the auth backend.
class ClinicSignOutButton extends ConsumerWidget {
  const ClinicSignOutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout),
      onPressed: () {
        ref.read(clinicSessionControllerProvider.notifier).signOut();
        context.go(Routes.entry);
      },
    );
  }
}
