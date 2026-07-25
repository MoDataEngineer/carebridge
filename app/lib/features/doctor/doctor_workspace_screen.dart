import 'package:flutter/material.dart';
import '../../shared/widgets/pills_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/enums.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import '../auth/clinic/clinic_sign_out_button.dart';
import '../diagnostics/test_orders_view.dart';
import '../summary/summary_tab.dart';
import 'access_flow_dialogs.dart';
import 'add_visit_form.dart';
import 'doctor_dashboard.dart';
import 'doctor_models.dart';
import 'doctor_repository.dart';
import 'history_tab.dart';
import 'upgrade_screen.dart';

/// Doctor-core workspace (Section 5.2): scoped patient search, a tabbed patient
/// view, and (doctor-scoped only) add-visit. The list of patients returned by a
/// search is decided by RLS from the active scope — this screen never filters by
/// scope itself. The only scope-driven UI decision is whether to offer writing
/// (AC-9): admin sessions can view but not author clinical notes.
class DoctorWorkspaceScreen extends ConsumerStatefulWidget {
  const DoctorWorkspaceScreen({super.key, required this.scope});

  final DoctorScope scope;

  @override
  ConsumerState<DoctorWorkspaceScreen> createState() => _DoctorWorkspaceScreenState();
}

class _DoctorWorkspaceScreenState extends ConsumerState<DoctorWorkspaceScreen> {
  final _query = TextEditingController();
  final _historyKey = GlobalKey<HistoryTabState>();
  Future<List<PatientSearchResult>>? _results;
  PatientSearchResult? _selected;

  void _search() {
    setState(() {
      _selected = null;
      _results = ref.read(doctorRepositoryProvider).searchPatients(_query.text);
    });
  }

  /// Return to the Today dashboard from anywhere in this tab (clears both the
  /// open record and the search results).
  void _backToToday() {
    _query.clear();
    setState(() {
      _selected = null;
      _results = null;
    });
  }

  /// From the dashboard's next-patient/queue cards: the queue RPC gives us a
  /// name, not an id — so prefill the search box and run a scoped search rather
  /// than deep-linking. If it resolves to exactly one patient, open them.
  Future<void> _openByName(String name) async {
    _query.text = name;
    final future = ref.read(doctorRepositoryProvider).searchPatients(name);
    setState(() {
      _selected = null;
      _results = future;
    });
    final matches = await future;
    if (!mounted) return;
    if (matches.length == 1) {
      setState(() => _selected = matches.first);
      ref
          .read(doctorRepositoryProvider)
          .logView(matches.first.id, 'patient record opened (queue)')
          .catchError((_) {});
    }
  }

  /// After a consent code is redeemed we already know the patient id — open
  /// their record directly instead of making the doctor search by name (which,
  /// in person, they often don't know exactly).
  Future<void> _openPatientById(String id) async {
    final p = await ref.read(doctorRepositoryProvider).patientById(id);
    if (!mounted) return;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Access granted, but the record could not be opened — '
              'try searching for the patient.')));
      return;
    }
    setState(() {
      _results = null;
      _selected = p;
    });
    // Section 10 auditability: opening the record is logged (best-effort).
    ref
        .read(doctorRepositoryProvider)
        .logView(p.id, 'patient record opened (consent code)')
        .catchError((_) {});
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final scopeLabel = scope.role == ActiveRole.admin
        ? 'Admin · all clinic patients'
        : 'Doctor · your patients';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        // Embedded in ClinicShell — no route to pop back to.
        automaticallyImplyLeading: false,
        actions: [
          // Flow A/B initiation needs a specific doctor identity (AC-9); hide for admin.
          if (scope.canWrite) ...[
            IconButton(
              tooltip: 'Add by consent code',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final patientId =
                    await showRedeemConsentCodeDialog(context, ref);
                if (patientId != null && mounted) {
                  await _openPatientById(patientId);
                }
              },
            ),
            IconButton(
              tooltip: 'Request access',
              icon: const Icon(Icons.person_add_alt),
              onPressed: () => showRequestAccessDialog(context, ref, scope),
            ),
          ],
          const ThemeToggleButton(),
          const ClinicSignOutButton(),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _selected == null ? _searchView(scopeLabel) : _detailView(scope),
      ),
    );
  }

  Widget _searchView(String scopeLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(scopeLabel, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: 'Search by name, phone, or ABHA',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            // Clearing the search is the way back to the Today dashboard.
            suffixIcon: _results == null
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: _backToToday,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _search, child: const Text('Search')),
        const SizedBox(height: 16),
        // Results replace the dashboard, so offer an explicit way back to it.
        if (_results != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _backToToday,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to Today'),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Expanded(
          child: _results == null
              ? DoctorDashboard(scope: widget.scope, onOpenByName: _openByName)
              : FutureBuilder<List<PatientSearchResult>>(
                  future: _results,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: PillsLoader());
                    }
                    final list = snap.data ?? const [];
                    if (list.isEmpty) {
                      return const Center(child: Text('No patients match your search.'));
                    }
                    return ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = list[i];
                        return ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(p.name),
                          subtitle: Text(p.abhaId == null
                              ? p.phone
                              : '${p.phone} · ${p.abhaId}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            setState(() => _selected = p);
                            // Section 10 auditability (M2): opening a record is
                            // logged for "Who viewed my records". Best-effort —
                            // a log hiccup must not block care.
                            ref
                                .read(doctorRepositoryProvider)
                                .logView(p.id, 'patient record opened')
                                .catchError((_) {});
                          },
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _detailView(DoctorScope scope) {
    final p = _selected!;
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                // Back to the results that led here, or straight to Today when
                // the record was opened from the dashboard/consent code.
                tooltip: _results == null ? 'Back to Today' : 'Back to results',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selected = null),
              ),
              Expanded(
                child: Text(p.name, style: Theme.of(context).textTheme.titleMedium),
              ),
              if (_results != null)
                TextButton(
                  onPressed: _backToToday,
                  child: const Text('Today'),
                ),
            ],
          ),
          const TabBar(tabs: [
            Tab(text: 'Summary'),
            Tab(text: 'History'),
            Tab(text: 'Tests'),
            Tab(text: 'Add visit'),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                // One-touch AI summary (Section 8) — doctor AND admin scopes,
                // subject to the grant check (server-side). Paid tier only
                // (Section 9); free tier sees the upgrade prompt.
                scope.paid
                    ? PatientSummaryTab(patientId: p.id)
                    : _upgradePrompt('AI summary is a Pro feature.'),
                HistoryTab(key: _historyKey, patientId: p.id),
                // Tests tab: view orders + (doctor-scoped) order a new test.
                TestOrdersView(patientId: p.id, canOrder: scope.canWrite),
                scope.canWrite
                    ? SingleChildScrollView(
                        child: AddVisitForm(
                          scope: scope,
                          patient: p,
                          onSaved: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Visit saved')));
                            // Bounce back to History so the new visit shows.
                            _historyKey.currentState?.reload();
                            DefaultTabController.of(context).animateTo(1);
                          },
                        ),
                      )
                    : _adminCannotWrite(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _upgradePrompt(String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.workspace_premium, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UpgradeScreen())),
            child: const Text('See Ayulekha Pro'),
          ),
        ],
      ),
    );
  }

  Widget _adminCannotWrite() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 40),
          const SizedBox(height: 12),
          Text(
            'Writing a visit requires a specific doctor identity (AC-9).\n'
            'Sign in as a doctor from the "Who are you?" screen to add clinical notes.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
