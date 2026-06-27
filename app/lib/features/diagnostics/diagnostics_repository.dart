import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import 'diagnostics_models.dart';

/// Backend for diagnostics (Section 5.3, Flow C). Abstracted so the UI can be
/// widget-tested with a fake (no network).
///
/// Every method rides the active scoped session and the Phase 6 RLS / SECURITY
/// DEFINER functions (migration 0011):
///   - doctor ordering goes through carebridge_order_test (AC-9);
///   - partner reads/writes go through carebridge_claim_order / _partner_orders /
///     _update_order_status / _upload_report — function-only, so a partner can
///     never widen past "name + the one ordered test".
abstract class DiagnosticsRepository {
  // ---- Doctor side ----
  /// Order a test for a patient. [partnerId] null = open order (any partner may
  /// claim by code). Returns the generated order code (to show as a QR/code).
  Future<String> orderTest({
    required String patientId,
    required String testType,
    required String testName,
    String? partnerId,
  });

  // ---- Patient / doctor viewing ----
  /// All test orders for a patient (+ any uploaded reports), most recent first.
  /// [patientId] null = "my own orders" (the patient tab); RLS scopes the rows.
  Future<List<TestOrderView>> ordersForPatient(String? patientId);

  // ---- Diagnostic partner side ----
  /// Claim an order by its code → the narrow, privacy-safe order detail.
  Future<ClaimedOrder> claimOrder(String code);

  /// The partner's current work queue (orders it holds an active grant for).
  Future<List<PartnerQueueItem>> partnerQueue();

  /// Update progress: 'sample_collected' or 'in_progress'.
  Future<void> updateStatus(String orderId, String status);

  /// Upload a result; auto-closes the order-scoped grant.
  Future<void> uploadReport({
    required String orderId,
    required String reportType, // pdf | image | structured
    String? fileUrl,
    Map<String, dynamic>? structuredValues,
  });
}

class SupabaseDiagnosticsRepository implements DiagnosticsRepository {
  SupabaseDiagnosticsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<String> orderTest({
    required String patientId,
    required String testType,
    required String testName,
    String? partnerId,
  }) async {
    final res = await _client.rpc('carebridge_order_test', params: {
      'p_patient': patientId,
      'p_test_type': testType,
      'p_test_name': testName,
      'p_partner': partnerId,
    });
    // RETURNS TABLE(id, order_code) → a one-row list.
    final row = (res as List).first as Map<String, dynamic>;
    return row['order_code'] as String;
  }

  @override
  Future<List<TestOrderView>> ordersForPatient(String? patientId) async {
    var query = _client
        .from('test_orders')
        .select('id, test_type, test_name, status, order_code, created_at, '
            'test_reports(report_type, file_url, structured_values, uploaded_at)');
    if (patientId != null) {
      query = query.eq('patient_id', patientId);
    }
    final rows = await query.order('created_at', ascending: false);
    return (rows as List)
        .map((m) => TestOrderView.fromMap((m as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<ClaimedOrder> claimOrder(String code) async {
    final res = await _client.rpc('carebridge_claim_order', params: {'p_code': code.trim()});
    final row = (res as List).first as Map<String, dynamic>;
    return ClaimedOrder.fromMap(row);
  }

  @override
  Future<List<PartnerQueueItem>> partnerQueue() async {
    final res = await _client.rpc('carebridge_partner_orders');
    return [
      for (final m in (res as List))
        PartnerQueueItem.fromMap((m as Map).cast<String, dynamic>())
    ];
  }

  @override
  Future<void> updateStatus(String orderId, String status) => _client.rpc(
        'carebridge_update_order_status',
        params: {'p_order': orderId, 'p_status': status},
      );

  @override
  Future<void> uploadReport({
    required String orderId,
    required String reportType,
    String? fileUrl,
    Map<String, dynamic>? structuredValues,
  }) =>
      _client.rpc('carebridge_upload_report', params: {
        'p_order': orderId,
        'p_report_type': reportType,
        'p_file_url': fileUrl,
        'p_structured_values': structuredValues,
      });
}

final diagnosticsRepositoryProvider = Provider<DiagnosticsRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a DiagnosticsRepository override.');
  }
  return SupabaseDiagnosticsRepository(SupabaseService.client);
});
