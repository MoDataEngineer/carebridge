import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/breakpoints.dart';
import '../../../shared/models/enums.dart';
import '../../../shared/widgets/pill_nav_bar.dart';
import '../../doctor/appointments_repository.dart';
import '../../doctor/appointments_screen.dart';
import '../../doctor/doctor_models.dart';
import '../../doctor/doctor_workspace_screen.dart';
import '../../doctor/follow_ups_screen.dart';
import '../../doctor/live_queue_screen.dart';
import '../../doctor/upgrade_screen.dart';
import 'manage_doctors_screen.dart';
import 'session_controller.dart';

/// The doctor/clinic app shell (UI brief §3). ONE nav skeleton for both scopes:
/// a bottom bar on phones, a persistent side rail on tablet/web. The set of
/// destinations adapts to the active scope — a doctor gets Follow-ups, an admin
/// gets the doctor roster — but the shape stays the same, and the underlying
/// session/permission logic is untouched (§7). Each destination is its existing
/// full screen (kept intact so it still works standalone in tests).
class ClinicShell extends ConsumerStatefulWidget {
  const ClinicShell({super.key});

  @override
  ConsumerState<ClinicShell> createState() => _ClinicShellState();
}

class _ClinicShellState extends ConsumerState<ClinicShell> {
  int _index = 0;
  // Destinations are built on first visit, then kept alive — so a tab's data
  // (queue realtime, roster, follow-ups) isn't loaded until it's opened.
  final _visited = <int>{0};

  // Lets other tabs (the live queue) drive the Patients tab: switch to it and
  // open a patient record, mirroring the dashboard's "Open record".
  final _workspaceKey = GlobalKey<DoctorWorkspaceScreenState>();

  void _openPatientInWorkspace(String name) {
    setState(() {
      _index = 0;
      _visited.add(0);
    });
    // The workspace may be first-building this frame — open after it mounts.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _workspaceKey.currentState?.openByName(name));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clinicSessionControllerProvider);
    final s = state.active;
    if (s == null) {
      // No active scope (e.g. after sign-out mid-transition). Nothing to show.
      return const Scaffold(
        body: Center(child: Text('No active clinic session.')),
      );
    }

    final scope = DoctorScope(
      role: s.role,
      clinicId: s.clinicId,
      doctorId: s.doctorId,
      paid: s.paid,
    );
    final unverified = state.login?.verified == false;
    // Live badge on the Appointments tab: how many requests are pending.
    final pending = ref.watch(pendingRequestCountProvider).valueOrNull ?? 0;

    final destinations = <_ShellDestination>[
      _ShellDestination(
        label: 'Patients',
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        body: DoctorWorkspaceScreen(key: _workspaceKey, scope: scope),
      ),
      const _ShellDestination(
        label: 'Appointments',
        icon: Icons.event_note_outlined,
        selectedIcon: Icons.event_note,
        body: AppointmentsScreen(),
      ),
      _ShellDestination(
        label: 'Queue',
        icon: Icons.confirmation_number_outlined,
        selectedIcon: Icons.confirmation_number,
        body: scope.paid
            ? LiveQueueScreen(scope: scope, onOpenPatient: _openPatientInWorkspace)
            : const UpgradeScreen(),
      ),
      // Fourth slot is role-specific — same bar, scope-appropriate destination.
      if (scope.canWrite)
        _ShellDestination(
          label: 'Follow-ups',
          icon: Icons.event_repeat_outlined,
          selectedIcon: Icons.event_repeat,
          body: scope.paid ? const FollowUpsScreen() : const UpgradeScreen(),
        ),
      if (scope.role == ActiveRole.admin)
        const _ShellDestination(
          label: 'Doctors',
          icon: Icons.badge_outlined,
          selectedIcon: Icons.badge,
          body: ManageDoctorsScreen(),
        ),
    ];

    final index = _index.clamp(0, destinations.length - 1);
    _visited.add(index);

    final content = Column(
      children: [
        if (unverified) const _UnverifiedBanner(),
        Expanded(
          child: IndexedStack(
            index: index,
            children: [
              for (var i = 0; i < destinations.length; i++)
                _visited.contains(i)
                    ? destinations[i].body
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );

    void select(int i) => setState(() {
          _index = i;
          _visited.add(i);
        });

    // Side rail on tablet/web width; bottom bar on phones (§3, responsive).
    if (!Breakpoints.isMobile(context)) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: select,
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Icon(Icons.health_and_safety, size: 28),
                ),
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: _destIcon(d, d.icon, pending),
                      selectedIcon: _destIcon(d, d.selectedIcon, pending),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: content,
      // Same custom pill nav as the patient shell: every destination keeps its
      // icon AND label (Material's NavigationBar hid labels and intermittently
      // dropped the first destination inside the rounded clip).
      bottomNavigationBar: PillNavBar(
        currentIndex: index,
        onTap: select,
        items: [
          for (final d in destinations)
            PillNavItem(
              icon: d.icon,
              label: d.label,
              badgeCount: d.label == 'Appointments' ? pending : 0,
            ),
        ],
      ),
    );
  }

  /// Badges the Appointments tab with the pending-request count (a live
  /// "you have N requests" signal in place of a push notification).
  Widget _destIcon(_ShellDestination d, IconData icon, int pending) {
    final ic = Icon(icon);
    if (d.label == 'Appointments' && pending > 0) {
      return Badge(label: Text('$pending'), child: ic);
    }
    return ic;
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.body,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;
}

/// Audit H2: self-registered hospitals show as unverified until the founder
/// confirms the registration number. Slim, always-visible banner (not dismissible).
class _UnverifiedBanner extends StatelessWidget {
  const _UnverifiedBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Registration pending verification — Ayulekha will confirm your '
                'hospital registration number shortly.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
