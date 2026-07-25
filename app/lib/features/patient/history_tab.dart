import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/visit_history_card.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: visits.length,
          itemBuilder: (context, i) => VisitHistoryCard(visit: visits[i]),
        );
      },
    );
  }
}
