import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/enums.dart';
import '../diagnostics/test_orders_view.dart';
import '../summary/summary_tab.dart';
import 'add_visit_form.dart';
import 'doctor_models.dart';
import 'doctor_repository.dart';
import 'follow_ups_screen.dart';
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
  Future<List<PatientSearchResult>>? _results;
  PatientSearchResult? _selected;

  void _search() {
    setState(() {
      _selected = null;
      _results = ref.read(doctorRepositoryProvider).searchPatients(_query.text);
    });
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
        actions: [
          // Follow-up tracker (paid, doctor-scoped). Free tier sees the
          // Upgrade stub instead (Section 9).
          if (scope.canWrite)
            IconButton(
              tooltip: 'Follow-ups',
              icon: const Icon(Icons.event_repeat),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    scope.paid ? const FollowUpsScreen() : const UpgradeScreen(),
              )),
            ),
          // Flow A/B initiation needs a specific doctor identity (AC-9); hide for admin.
          if (scope.canWrite) ...[
            IconButton(
              tooltip: 'Add by consent code',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _redeemCodeDialog,
            ),
            IconButton(
              tooltip: 'Request access',
              icon: const Icon(Icons.person_add_alt),
              onPressed: () => _requestAccessDialog(scope),
            ),
          ],
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _selected == null ? _searchView(scopeLabel) : _detailView(scope),
      ),
    );
  }

  /// Flow A — redeem a patient's in-person consent code into a standing grant.
  Future<void> _redeemCodeDialog() async {
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
    try {
      await ref.read(doctorRepositoryProvider).redeemConsentCode(ctrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access granted — search to open the patient')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Invalid or expired code: $e')));
      }
    }
  }

  /// Flow B — look up a patient by phone/ABHA and send an access request.
  Future<void> _requestAccessDialog(DoctorScope scope) async {
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
                        if (mounted) {
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
          decoration: const InputDecoration(
            labelText: 'Search by name, phone, or ABHA',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _search, child: const Text('Search')),
        const SizedBox(height: 16),
        Expanded(
          child: _results == null
              ? const Center(child: Text('Search for a patient to begin.'))
              : FutureBuilder<List<PatientSearchResult>>(
                  future: _results,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
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
                          onTap: () => setState(() => _selected = p),
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
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selected = null),
              ),
              Expanded(
                child: Text(p.name, style: Theme.of(context).textTheme.titleMedium),
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
                _historyTab(p),
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
                            setState(() {});
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

  Widget _historyTab(PatientSearchResult p) {
    return FutureBuilder<List<VisitRecord>>(
      // Re-read each build so a just-saved visit appears.
      future: ref.read(doctorRepositoryProvider).patientHistory(p.id),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final visits = snap.data ?? const [];
        if (visits.isEmpty) {
          return const Center(child: Text('No visits recorded yet.'));
        }
        return ListView.builder(
          itemCount: visits.length,
          itemBuilder: (context, i) {
            final v = visits[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.visitDate.toString().substring(0, 10),
                        style: Theme.of(context).textTheme.labelSmall),
                    Text(v.diagnosis ?? '(no diagnosis)',
                        style: Theme.of(context).textTheme.titleSmall),
                    if (v.notes != null && v.notes!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(v.notes!),
                    ],
                    for (final rx in v.prescriptions)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• ${rx.drugName}'
                          '${rx.dosage != null ? ' ${rx.dosage}' : ''}'
                          ' · ${rx.scheduleLabel}'
                          '${rx.durationDays != null ? ' · ${rx.durationDays}d' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (v.followUpDate != null) ...[
                      const SizedBox(height: 4),
                      Text('Follow-up: ${v.followUpDate!.toString().substring(0, 10)}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
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
            child: const Text('See CareBridge Pro'),
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
