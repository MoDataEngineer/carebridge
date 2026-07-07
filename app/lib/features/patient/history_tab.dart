import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import 'patient_models.dart';
import 'patient_repository.dart';

/// Read-only visit history (Section 5.1): diagnosis, doctor notes, prescriptions.
/// Patients can view but never edit clinical records — enforced by RLS (0005
/// grants the patient SELECT only on visits/prescriptions).
class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key});

  @override
  ConsumerState<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<HistoryTab> {
  late Future<List<VisitRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(patientRepositoryProvider).visitHistory();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VisitRecord>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SkeletonLoader();
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load history: ${snap.error}'));
        }
        final visits = snap.data ?? const [];
        if (visits.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            title: 'No visits yet',
            message:
                'Diagnoses, prescriptions and your doctor\'s notes from clinic '
                'visits will appear here — always yours to see.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: visits.length,
          itemBuilder: (context, i) => _VisitCard(visit: visits[i]),
        );
      },
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit});
  final VisitRecord visit;

  @override
  Widget build(BuildContext context) {
    final d = visit.visitDate;
    final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note, size: 18),
                const SizedBox(width: 6),
                Text(dateStr, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            Text('Diagnosis: ${visit.diagnosis ?? '—'}'),
            if (visit.notes != null && visit.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Notes: ${visit.notes}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (visit.prescriptions.isNotEmpty) ...[
              const Divider(height: 18),
              Text('Prescriptions', style: Theme.of(context).textTheme.labelLarge),
              for (final p in visit.prescriptions)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• ${p.drugName}'
                    '${p.dosage != null ? ' ${p.dosage}' : ''} '
                    '— ${p.scheduleLabel}'
                    '${p.durationDays != null ? ' · ${p.durationDays}d' : ''}',
                  ),
                ),
            ],
            if (visit.followUpDate != null) ...[
              const SizedBox(height: 6),
              Text('Follow-up advised: ${visit.followUpDate!.toIso8601String().split('T').first}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
