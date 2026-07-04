import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import 'summary_models.dart';

/// Backend for the one-touch AI summary (Section 8). Abstracted so the UI can
/// be widget-tested with a fake (no network).
///
/// The Claude call happens SERVER-SIDE ONLY, inside the ai-summary Edge
/// Function; this repository only invokes it with the caller's scoped JWT.
/// The DB decides access (grant check incl. AC-8) and logs the view.
abstract class SummaryRepository {
  /// Layer 1 — deterministic safety banner straight from the patients row.
  /// Rendered immediately, independent of (and never produced by) the AI.
  Future<SafetyBanner> banner(String patientId);

  /// One-touch: generate (or fetch cached) layer-2 narrative for the patient.
  Future<AiSummaryResult> generate(String patientId);
}

class SupabaseSummaryRepository implements SummaryRepository {
  SupabaseSummaryRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<SafetyBanner> banner(String patientId) async {
    final row = await _client
        .from('patients')
        .select('allergies, chronic_conditions, current_medications')
        .eq('id', patientId)
        .single();
    return SafetyBanner.fromMap(row);
  }

  @override
  Future<AiSummaryResult> generate(String patientId) async {
    final res = await _client.functions.invoke(
      'ai-summary',
      body: {'patient_id': patientId},
    );
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) {
      throw StateError('${data['error']}: ${data['detail'] ?? ''}');
    }
    return AiSummaryResult.fromMap(data);
  }
}

final summaryRepositoryProvider = Provider<SummaryRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a SummaryRepository override.');
  }
  return SupabaseSummaryRepository(SupabaseService.client);
});
