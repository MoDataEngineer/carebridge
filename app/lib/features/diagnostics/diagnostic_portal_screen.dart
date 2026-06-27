import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import 'diagnostics_models.dart';
import 'diagnostics_repository.dart';

/// Diagnostic partner portal (Section 5.3): claim an order by its code, see the
/// work queue, update progress, and upload a result. The partner sees ONLY the
/// patient's name + the one ordered test (enforced at the DB by the order-scoped
/// grant) — never any broader history.
///
/// NOTE: partner sign-in is still placeholder (Phase 11 real lab-registry/HFR
/// auth). This portal assumes an authenticated partner session whose
/// current_partner_id() resolves server-side.
class DiagnosticPortalScreen extends ConsumerStatefulWidget {
  const DiagnosticPortalScreen({super.key});

  @override
  ConsumerState<DiagnosticPortalScreen> createState() => _DiagnosticPortalScreenState();
}

class _DiagnosticPortalScreenState extends ConsumerState<DiagnosticPortalScreen> {
  Future<List<PartnerQueueItem>>? _queue;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _queue = ref.read(diagnosticsRepositoryProvider).partnerQueue();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic portal'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.go(Routes.entry),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _claimDialog,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Claim order'),
      ),
      body: FutureBuilder<List<PartnerQueueItem>>(
        future: _queue,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load queue: ${snap.error}'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(
              child: Text('No orders yet. Claim an order code to begin.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, i) => _QueueCard(
              item: items[i],
              onStatus: (s) => _setStatus(items[i].orderId, s),
              onUpload: () => _uploadDialog(items[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _claimDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Claim an order'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Order code',
            hintText: 'Code the patient is showing you',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Claim')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      final order = await ref.read(diagnosticsRepositoryProvider).claimOrder(ctrl.text);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Claimed: ${order.testName} for ${order.patientName}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not claim: $e')));
      }
    }
  }

  Future<void> _setStatus(String orderId, String status) async {
    try {
      await ref.read(diagnosticsRepositoryProvider).updateStatus(orderId, status);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  Future<void> _uploadDialog(PartnerQueueItem item) async {
    var reportType = 'structured';
    final fileUrlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final valCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Upload result · ${item.testName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'structured', label: Text('Values')),
                  ButtonSegment(value: 'pdf', label: Text('PDF')),
                  ButtonSegment(value: 'image', label: Text('Image')),
                ],
                selected: {reportType},
                onSelectionChanged: (s) => setLocal(() => reportType = s.first),
              ),
              const SizedBox(height: 12),
              if (reportType == 'structured') ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: keyCtrl,
                        decoration: const InputDecoration(labelText: 'Measure (e.g. Hb)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: valCtrl,
                        decoration: const InputDecoration(labelText: 'Value'),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'MVP: one structured value. Full panels + Storage file upload '
                    'land in a later pass.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ] else
                TextField(
                  controller: fileUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'File URL',
                    hintText: 'Storage path / URL of the uploaded file',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(diagnosticsRepositoryProvider).uploadReport(
            orderId: item.orderId,
            reportType: reportType,
            fileUrl: reportType == 'structured' ? null : fileUrlCtrl.text.trim(),
            structuredValues: reportType == 'structured' && keyCtrl.text.trim().isNotEmpty
                ? {keyCtrl.text.trim(): valCtrl.text.trim()}
                : null,
          );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report uploaded — access to this order is now closed')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not upload: $e')));
      }
    }
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.item, required this.onStatus, required this.onUpload});
  final PartnerQueueItem item;
  final ValueChanged<String> onStatus;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final done = item.hasReport || item.status == 'report_ready';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.testName} · ${item.testType}',
                style: Theme.of(context).textTheme.titleSmall),
            Text(item.patientName, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            if (done)
              const Text('Report uploaded — order closed.')
            else
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => onStatus('sample_collected'),
                    child: const Text('Sample collected'),
                  ),
                  OutlinedButton(
                    onPressed: () => onStatus('in_progress'),
                    child: const Text('In progress'),
                  ),
                  FilledButton(onPressed: onUpload, child: const Text('Upload result')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
