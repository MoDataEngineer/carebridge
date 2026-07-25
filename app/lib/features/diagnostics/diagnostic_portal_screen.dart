import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/scan_code_screen.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/status_pill.dart';
import '../../shared/widgets/theme_toggle_button.dart';
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
          const ThemeToggleButton(),
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
            return const SkeletonLoader();
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load queue: ${snap.error}'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.qr_code_scanner,
              title: 'No orders in your queue',
              message:
                  'Claim an order with the code the patient shows you, then '
                  'update its status and upload the result here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Order code',
                hintText: 'Code the patient is showing you',
              ),
            ),
            if (qrScanningSupported) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR code'),
                onPressed: () async {
                  final code = await scanCode(ctx, title: 'Scan order code');
                  if (code != null) ctrl.text = code;
                },
              ),
            ],
          ],
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
    Uint8List? fileBytes;
    String? fileName;
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
                    'MVP: one structured value. Full panels land in a later pass.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ] else ...[
                // Audit fix H3: real file into the PRIVATE 'reports' bucket —
                // the storage policies allow it only under this order's path
                // while the order-scoped grant is active.
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file),
                  label: Text(fileName ?? 'Choose ${reportType == 'pdf' ? 'PDF' : 'image'} file'),
                  onPressed: () async {
                    final picked = await FilePicker.pickFiles(
                      withData: true,
                      type: FileType.custom,
                      allowedExtensions: reportType == 'pdf'
                          ? ['pdf']
                          : ['png', 'jpg', 'jpeg', 'webp'],
                    );
                    final f = picked?.files.firstOrNull;
                    if (f?.bytes != null) {
                      setLocal(() {
                        fileBytes = f!.bytes;
                        fileName = f.name;
                      });
                    }
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (reportType != 'structured' && fileBytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choose a file first')));
      return;
    }
    try {
      final repo = ref.read(diagnosticsRepositoryProvider);
      String? path;
      if (reportType != 'structured') {
        // Upload the file FIRST (needs the still-open grant), then record the
        // report row — which closes the grant.
        path = await repo.uploadReportFile(
          orderId: item.orderId,
          filename: fileName!,
          bytes: fileBytes!,
        );
      }
      await repo.uploadReport(
            orderId: item.orderId,
            reportType: reportType,
            fileUrl: path,
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
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final done = item.hasReport || item.status == 'report_ready';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadii.rCard,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.testName,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              StatusPill(done ? 'report_ready' : item.status),
            ],
          ),
          if (item.testType.isNotEmpty)
            Text(item.testType,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.sm),
          // The partner sees only the patient's name (order-scoped grant §5.3).
          Row(
            children: [
              Icon(Icons.person, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(item.patientName, style: text.bodyMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (done)
            Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Report uploaded — order closed.',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => onStatus('sample_collected'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(44, 40)),
                  child: const Text('Sample collected'),
                ),
                OutlinedButton(
                  onPressed: () => onStatus('in_progress'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(44, 40)),
                  child: const Text('In progress'),
                ),
                FilledButton(
                  onPressed: onUpload,
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 40)),
                  child: const Text('Upload result'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
