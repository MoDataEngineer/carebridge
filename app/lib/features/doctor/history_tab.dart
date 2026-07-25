import 'package:flutter/material.dart';
import '../../shared/widgets/pills_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/visit_history_card.dart';
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
          return const Center(child: PillsLoader());
        }
        final visits = snap.data ?? const [];
        if (visits.isEmpty) {
          return const Center(child: Text('No visits recorded yet.'));
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
