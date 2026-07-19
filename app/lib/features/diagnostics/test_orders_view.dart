import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/code_qr.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/status_pill.dart';
import '../../shared/widgets/vital_tile.dart';
import 'diagnostics_models.dart';
import 'diagnostics_repository.dart';
import 'report_pdf_view.dart';

/// Shared "Tests" view (Section 5.1 patient + 5.2 doctor Tests tab): lists a
/// patient's test orders with status and any uploaded reports, viewed in-app.
/// Doctor-scoped sessions ([canOrder] = true) also get an "Order test" action.
///
/// [patientId] is the patient whose orders to show; null means "my own orders"
/// (the patient tab) — RLS scopes the rows either way.
class TestOrdersView extends ConsumerStatefulWidget {
  const TestOrdersView({
    super.key,
    this.patientId,
    this.canOrder = false,
  });

  final String? patientId;
  final bool canOrder;

  @override
  ConsumerState<TestOrdersView> createState() => _TestOrdersViewState();
}

class _TestOrdersViewState extends ConsumerState<TestOrdersView> {
  Future<List<TestOrderView>>? _orders;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _orders = ref.read(diagnosticsRepositoryProvider).ordersForPatient(widget.patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<TestOrderView>>(
        future: _orders,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonLoader();
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load tests: ${snap.error}'));
          }
          final orders = snap.data ?? const [];
          if (orders.isEmpty) {
            return EmptyState(
              icon: Icons.science_outlined,
              title: 'No tests yet',
              message: widget.canOrder
                  ? 'Tests you order appear here with live status. Tap "Order '
                      'test" to create one — the patient shows the code at any lab.'
                  : 'Lab and imaging tests ordered for you will appear here — '
                      'with their status and results you can view in the app.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, i) => _OrderCard(order: orders[i]),
          );
        },
      ),
      floatingActionButton: widget.canOrder
          ? FloatingActionButton.extended(
              onPressed: _orderTestDialog,
              icon: const Icon(Icons.add),
              label: const Text('Order test'),
            )
          : null,
    );
  }

  Future<void> _orderTestDialog() async {
    final typeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Order a test'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: typeCtrl,
              decoration: const InputDecoration(
                labelText: 'Test type',
                hintText: 'e.g. pathology, imaging',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Test name',
                hintText: 'e.g. CBC, Chest X-Ray',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The order is left OPEN — any diagnostic partner can fulfil it by '
              'scanning the code you share with the patient.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create order')),
        ],
      ),
    );
    if (ok != true || typeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) return;
    try {
      final code = await ref.read(diagnosticsRepositoryProvider).orderTest(
            patientId: widget.patientId!,
            testType: typeCtrl.text.trim(),
            testName: nameCtrl.text.trim(),
          );
      if (!mounted) return;
      _reload();
      await _showOrderCode(code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not order test: $e')));
      }
    }
  }

  Future<void> _showOrderCode(String code) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Order code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this code with the patient to show at the lab:'),
            const SizedBox(height: 12),
            SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 18)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final TestOrderView order;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${order.testName} · ${order.testType}',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                StatusPill(order.status),
              ],
            ),
            if (order.orderCode != null && order.status != 'report_ready') ...[
              const SizedBox(height: 8),
              // Real scannable QR for the lab (the code stays typeable too).
              Row(
                children: [
                  CodeQr(code: order.orderCode!, size: 96),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Show this at the lab / imaging centre',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        SelectableText('Order code: ${order.orderCode}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            for (final r in order.reports) ...[
              const Divider(),
              _ReportView(report: r),
            ],
          ],
        ),
      ),
    );
  }
}

/// In-app report viewer: structured values as a small table; pdf/image via a
/// SHORT-LIVED SIGNED URL from the private 'reports' bucket (audit fix H3).
/// Creating the signed URL passes the storage SELECT policies, so a viewer
/// without an active grant path can never obtain a link.
class _ReportView extends ConsumerStatefulWidget {
  const _ReportView({required this.report});
  final TestReportView report;

  @override
  ConsumerState<_ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends ConsumerState<_ReportView> {
  Future<String>? _signed;

  /// Numeric value vs "low-high" reference range -> flag when outside.
  /// Non-numeric or unparseable inputs are never flagged (no false alarms).
  static bool _outOfRange(dynamic value, String? reference) {
    if (reference == null) return false;
    final v = double.tryParse(value.toString());
    final m = RegExp(r'^\s*([\d.]+)\s*[-–]\s*([\d.]+)\s*$').firstMatch(reference);
    if (v == null || m == null) return false;
    final low = double.tryParse(m.group(1)!);
    final high = double.tryParse(m.group(2)!);
    if (low == null || high == null) return false;
    return v < low || v > high;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    if (report.reportType == 'structured' && report.structuredValues != null) {
      final values = report.structuredValues!;
      // Meta keys style their sibling measurements instead of tiling.
      final unit = values['unit']?.toString();
      final reference = values['reference_range']?.toString();
      final measurements = values.entries
          .where((e) => e.key != 'unit' && e.key != 'reference_range');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Result', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in measurements)
                VitalTile(
                  label: e.key,
                  value: '${e.value}',
                  unit: unit,
                  reference: reference,
                  flagged: _outOfRange(e.value, reference),
                ),
            ],
          ),
        ],
      );
    }
    final path = report.fileUrl;
    if (path == null) return const Text('(file missing)');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(report.reportType == 'image' ? Icons.image : Icons.picture_as_pdf),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                report.reportType == 'image' ? 'Image report' : 'PDF report',
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _signed = ref.read(diagnosticsRepositoryProvider).signedUrl(path);
              }),
              child: const Text('View'),
            ),
          ],
        ),
        if (_signed != null)
          FutureBuilder<String>(
            future: _signed,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Could not open report: ${snap.error}'),
                );
              }
              final url = snap.data!;
              if (widget.report.reportType == 'image') {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Image.network(url,
                      errorBuilder: (_, e, __) => Text('Could not load image: $e')),
                );
              }
              // PDF: render inline in-app — a native <iframe> on web, pdfx on
              // mobile (see report_pdf_view.dart). Bounded height with a border
              // so it sits naturally inside the scrolling order list.
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 480,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ReportPdfView(
                        signedUrl: url,
                        loadBytes: () => ref
                            .read(diagnosticsRepositoryProvider)
                            .reportBytes(path),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
