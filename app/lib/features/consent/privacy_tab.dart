import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'consent_models.dart';
import 'consent_repository.dart';

/// Patient "Privacy & Access" tab (Section 7): share an in-person consent code
/// (Flow A), approve/deny remote requests (Flow B), see & one-tap revoke active
/// grants ("Doctors with access"), and read the access log ("Who viewed my
/// records"). All actions go through the consent RPCs; RLS keeps it to self.
class PrivacyTab extends ConsumerStatefulWidget {
  const PrivacyTab({super.key});

  @override
  ConsumerState<PrivacyTab> createState() => _PrivacyTabState();
}

class _PrivacyTabState extends ConsumerState<PrivacyTab> {
  late Future<_PrivacyData> _data;
  ConsentCode? _code;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repo = ref.read(consentRepositoryProvider);
    _data = () async {
      final grants = await repo.doctorsWithAccess();
      final requests = await repo.pendingRequests();
      final logs = await repo.whoViewed();
      return _PrivacyData(grants: grants, requests: requests, logs: logs);
    }();
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _shareCode() async {
    try {
      final code = await ref.read(consentRepositoryProvider).createConsentCode();
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PrivacyData>(
      future: _data,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load: ${snap.error}'));
        }
        final d = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section(context, 'Share access in person'),
            const Text('Generate a one-time code to show a doctor at your visit. '
                'It expires in 10 minutes.'),
            const SizedBox(height: 8),
            if (_code != null)
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: SelectableText(_code!.code,
                      style: const TextStyle(fontSize: 22, letterSpacing: 2)),
                  subtitle: Text('Expires ${_code!.expiresAt.toString().substring(0, 16)}'),
                ),
              ),
            FilledButton.icon(
              onPressed: _shareCode,
              icon: const Icon(Icons.add_moderator),
              label: const Text('Generate consent code'),
            ),

            _section(context, 'Pending requests'),
            if (d.requests.isEmpty)
              const Text('No pending access requests.')
            else
              for (final r in d.requests)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.doctorName} · ${r.clinicName}',
                            style: Theme.of(context).textTheme.titleSmall),
                        const Text('wants access to your records'),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _run(
                                  () => ref.read(consentRepositoryProvider)
                                      .respondRequest(r.grantId, false),
                                  'Request denied'),
                              child: const Text('Deny'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _run(
                                  () => ref.read(consentRepositoryProvider)
                                      .respondRequest(r.grantId, true),
                                  'Access approved'),
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

            _section(context, 'Doctors with access'),
            if (d.grants.isEmpty)
              const Text('No doctor currently has access.')
            else
              for (final g in d.grants)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.medical_services),
                    title: Text('${g.doctorName} · ${g.clinicName}'),
                    subtitle: Text(g.grantedAt == null
                        ? g.type
                        : '${g.type} · since ${g.grantedAt!.toString().substring(0, 10)}'),
                    trailing: TextButton(
                      onPressed: () => _run(
                          () => ref.read(consentRepositoryProvider).revokeGrant(g.grantId),
                          'Access revoked'),
                      child: const Text('Revoke'),
                    ),
                  ),
                ),

            _section(context, 'Who viewed my records'),
            if (d.logs.isEmpty)
              const Text('No access recorded yet.')
            else
              for (final l in d.logs)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.visibility_outlined, size: 18),
                  title: Text(l.plainLabel),
                  subtitle: Text(
                      '${l.viewedAt.toString().substring(0, 16)}${l.whatViewed != null ? ' · ${l.whatViewed}' : ''}'),
                ),
          ],
        );
      },
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _PrivacyData {
  const _PrivacyData({required this.grants, required this.requests, required this.logs});
  final List<GrantView> grants;
  final List<AccessRequestView> requests;
  final List<AccessLogView> logs;
}
