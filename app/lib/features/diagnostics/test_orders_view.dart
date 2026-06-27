import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diagnostics_models.dart';
import 'diagnostics_repository.dart';

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
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load tests: ${snap.error}'));
          }
          final orders = snap.data ?? const [];
          if (orders.isEmpty) {
            return const Center(child: Text('No tests ordered yet.'));
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

/// A status chip with a friendly label per test_status value.
class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'ordered' => 'Ordered',
      'sample_collected' => 'Sample collected',
      'in_progress' => 'In progress',
      'report_ready' => 'Report ready',
      'cancelled' => 'Cancelled',
      _ => status,
    };
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: status == 'report_ready'
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
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
                _StatusChip(order.status),
              ],
            ),
            if (order.orderCode != null && order.status != 'report_ready') ...[
              const SizedBox(height: 4),
              Text('Order code: ${order.orderCode}',
                  style: Theme.of(context).textTheme.bodySmall),
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

/// In-app report viewer: structured values as a small table; pdf/image as a
/// file link. (Real signed-URL fetch from Supabase Storage is wired in a later
/// pass — for now the stored file_url is shown.)
class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});
  final TestReportView report;

  @override
  Widget build(BuildContext context) {
    if (report.reportType == 'structured' && report.structuredValues != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Result', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          for (final e in report.structuredValues!.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(e.key)),
                  Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      );
    }
    return Row(
      children: [
        Icon(report.reportType == 'image' ? Icons.image : Icons.picture_as_pdf),
        const SizedBox(width: 8),
        Expanded(child: Text(report.fileUrl ?? '(file)', overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
