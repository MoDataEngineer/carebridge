import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'paid_tools_repository.dart';

/// Follow-up tracker (Section 5.2, paid, doctor-scoped): own patients with an
/// open follow-up due within a week or overdue; one-tap reminder + mark done.
/// The DB enforces tier, ownership, and AC-9 on every action.
class FollowUpsScreen extends ConsumerStatefulWidget {
  const FollowUpsScreen({super.key});

  @override
  ConsumerState<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends ConsumerState<FollowUpsScreen> {
  List<FollowUpItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(paidToolsRepositoryProvider).followUps();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _remind(FollowUpItem f) async {
    try {
      await ref.read(paidToolsRepositoryProvider).sendFollowUpReminder(f.visitId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reminder sent to ${f.patientName}')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not send reminder: $e')));
      }
    }
  }

  Future<void> _done(FollowUpItem f) async {
    try {
      await ref.read(paidToolsRepositoryProvider).markFollowUpDone(f.visitId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Follow-ups')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load follow-ups: $_error'),
                ),
              ])
            : _items == null
                ? const Center(child: CircularProgressIndicator())
                : _items!.isEmpty
                    ? ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: Text('No follow-ups due in the next week.')),
                        ),
                      ])
                    : ListView.builder(
                        itemCount: _items!.length,
                        itemBuilder: (context, i) {
                          final f = _items![i];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(f.patientName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                    ),
                                    Chip(
                                      label: Text(f.overdue
                                          ? 'Overdue'
                                          : 'Due ${f.dueDate.toString().substring(0, 10)}'),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: f.overdue
                                          ? Theme.of(context)
                                              .colorScheme
                                              .errorContainer
                                          : null,
                                    ),
                                  ]),
                                  if (f.diagnosis != null)
                                    Text(f.diagnosis!,
                                        style:
                                            Theme.of(context).textTheme.bodySmall),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    TextButton.icon(
                                      onPressed: () => _remind(f),
                                      icon: const Icon(Icons.notifications_active,
                                          size: 18),
                                      label: const Text('Send reminder'),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () => _done(f),
                                      icon: const Icon(Icons.check, size: 18),
                                      label: const Text('Mark done'),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
