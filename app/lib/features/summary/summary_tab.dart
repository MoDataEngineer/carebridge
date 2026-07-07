import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/fade_slide_in.dart';
import 'summary_models.dart';
import 'summary_repository.dart';

/// One-touch AI summary tab (Section 8), shown in the doctor/admin patient view.
///
/// Layer 1 — the safety banner (allergies / chronic conditions / medications)
/// renders IMMEDIATELY from structured fields and is never AI-generated.
/// Layer 2 — the narrative appears only after the one-touch generate call,
/// always under the mandatory "AI-generated summary — verify against full
/// record." label, with per-sentence tap-to-source.
class PatientSummaryTab extends ConsumerStatefulWidget {
  const PatientSummaryTab({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<PatientSummaryTab> createState() => _PatientSummaryTabState();
}

class _PatientSummaryTabState extends ConsumerState<PatientSummaryTab> {
  late final Future<SafetyBanner> _banner;
  Future<AiSummaryResult>? _summary;

  @override
  void initState() {
    super.initState();
    _banner = ref.read(summaryRepositoryProvider).banner(widget.patientId);
  }

  void _generate() {
    setState(() {
      _summary = ref.read(summaryRepositoryProvider).generate(widget.patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ---- Layer 1: deterministic safety banner (always visible) ----
        FutureBuilder<SafetyBanner>(
          future: _banner,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              );
            }
            final b = snap.data ?? const SafetyBanner();
            return Card(
              color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .35),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _chipRow(context, 'Allergies', b.allergies, Icons.warning_amber),
                    _chipRow(context, 'Chronic conditions', b.chronicConditions,
                        Icons.monitor_heart_outlined),
                    _chipRow(context, 'Current medications', b.currentMedications,
                        Icons.medication_outlined),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // ---- Layer 2: one-touch AI narrative ----
        if (_summary == null)
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate AI summary'),
          )
        else
          FutureBuilder<AiSummaryResult>(
            future: _summary,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const _GeneratingCard();
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Could not generate summary: ${snap.error}'),
                );
              }
              return FadeSlideIn(child: _narrative(context, snap.data!));
            },
          ),
      ],
    );
  }

  Widget _chipRow(BuildContext context, String label, List<String> items, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$label:', style: Theme.of(context).textTheme.labelMedium),
                if (items.isEmpty)
                  Text('none recorded',
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  for (final it in items)
                    Chip(
                      label: Text(it),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _narrative(BuildContext context, AiSummaryResult r) {
    if (r.summary == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(r.detail ?? 'No structured visit or test data to summarize yet.'),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mandatory label (Section 8) — never soften or remove.
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'AI-generated summary — verify against full record.',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
                if (r.cached)
                  Text('cached', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const Divider(),
            Text(r.summary!, style: Theme.of(context).textTheme.bodyMedium),
            if (r.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Tap a sentence to see its source:',
                  style: Theme.of(context).textTheme.labelSmall),
              for (final s in r.sources)
                InkWell(
                  onTap: () => _showSource(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          s.visitId != null ? Icons.event_note : Icons.science,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(s.sentence,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Regenerate'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSource(SentenceSource s) {
    final what = s.visitId != null
        ? 'Source: visit ${s.visitId} — see the History tab.'
        : 'Source: test order ${s.testOrderId} — see the Tests tab.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(what)));
  }
}

/// Reassuring "generating" state for the one-touch summary (UI brief §4 — this
/// is a wait the doctor will notice). A labelled card with a progress bar beats
/// a bare spinner and sets the expectation of what's happening.
class _GeneratingCard extends StatelessWidget {
  const _GeneratingCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Summarizing the record…',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Reading structured visits and test results — a few seconds.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
