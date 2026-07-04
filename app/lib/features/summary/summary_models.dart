// Phase 7 — one-touch AI summary models (Section 8).
//
// Layer 1 (SafetyBanner) is deterministic: structured patient fields rendered
// as chips, NEVER AI-generated. Layer 2 (AiSummaryResult.summary) is the
// server-generated narrative with per-sentence sources for tap-to-source.

class SafetyBanner {
  const SafetyBanner({
    this.allergies = const [],
    this.chronicConditions = const [],
    this.currentMedications = const [],
  });

  final List<String> allergies;
  final List<String> chronicConditions;
  final List<String> currentMedications;

  factory SafetyBanner.fromMap(Map<String, dynamic> m) => SafetyBanner(
        allergies: _list(m['allergies']),
        chronicConditions: _list(m['chronic_conditions']),
        currentMedications: _list(m['current_medications']),
      );

  static List<String> _list(dynamic v) =>
      v == null ? const [] : List<String>.from(v as List);
}

/// One summary sentence mapped to the visit or test order it came from.
/// The Edge Function has already dropped any id not present in the real input.
class SentenceSource {
  const SentenceSource({required this.sentence, this.visitId, this.testOrderId});

  final String sentence;
  final String? visitId;
  final String? testOrderId;

  factory SentenceSource.fromMap(Map<String, dynamic> m) => SentenceSource(
        sentence: (m['sentence'] ?? '') as String,
        visitId: m['visit_id'] as String?,
        testOrderId: m['test_order_id'] as String?,
      );
}

class AiSummaryResult {
  const AiSummaryResult({
    required this.banner,
    this.summary,
    this.sources = const [],
    this.cached = false,
    this.detail,
  });

  final SafetyBanner banner;

  /// Layer 2 narrative; null when there is no structured data to summarize yet.
  final String? summary;
  final List<SentenceSource> sources;
  final bool cached;

  /// Server explanation when [summary] is null (e.g. "no structured visits").
  final String? detail;

  factory AiSummaryResult.fromMap(Map<String, dynamic> m) => AiSummaryResult(
        banner: SafetyBanner.fromMap((m['banner'] ?? {}) as Map<String, dynamic>),
        summary: m['summary'] as String?,
        sources: [
          for (final s in (m['sentence_sources'] ?? []) as List)
            SentenceSource.fromMap(s as Map<String, dynamic>)
        ],
        cached: m['cached'] == true,
        detail: m['detail'] as String?,
      );
}
