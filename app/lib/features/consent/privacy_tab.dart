import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/code_qr.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/glass_panel.dart';
import '../../shared/widgets/pills_loader.dart';
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
      if (!mounted) return;
      setState(() => _code = code);
      _showCodeOverlay(code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  /// Present the consent code as a frosted-glass overlay (UI brief §2 — the
  /// "Share your record" overlay is exactly where glassmorphism belongs). The
  /// code lives ONLY here, so a patient shows it full-screen and it never
  /// clutters the scrolling list.
  void _showCodeOverlay(ConsentCode code) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (ctx) => Center(
        child: FadeSlideIn(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: GlassPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Show this code to your doctor',
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  // Real scannable QR (the doctor can also type the code).
                  CodeQr(code: code.code),
                  const SizedBox(height: 12),
                  SelectableText(
                    code.code,
                    style: const TextStyle(
                        fontSize: 28, letterSpacing: 4, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text('Expires ${code.expiresAt.toString().substring(0, 16)}',
                      style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PrivacyData>(
      future: _data,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: PillsLoader());
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
            FilledButton.icon(
              onPressed: _shareCode,
              icon: const Icon(Icons.add_moderator),
              label: const Text('Generate consent code'),
            ),
            if (_code != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _showCodeOverlay(_code!),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('Show my code again'),
                ),
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
