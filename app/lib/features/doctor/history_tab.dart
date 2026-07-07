import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'doctor_models.dart';
import 'doctor_repository.dart';

/// Visit history tab (doctor + admin scope). Loads once into state rather than
/// refetching on every parent rebuild; hold a `GlobalKey<HistoryTabState>` and
/// call [HistoryTabState.reload] after a new visit is saved so it appears.
class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<HistoryTab> createState() => HistoryTabState();
}

class HistoryTabState extends ConsumerState<HistoryTab> {
  late Future<List<VisitRecord>> _visits;

  @override
  void initState() {
    super.initState();
    _visits = _load();
  }

  Future<List<VisitRecord>> _load() =>
      ref.read(doctorRepositoryProvider).patientHistory(widget.patientId);

  void reload() => setState(() => _visits = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VisitRecord>>(
      future: _visits,
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
}
