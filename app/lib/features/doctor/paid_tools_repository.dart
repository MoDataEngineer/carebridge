import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';

/// Paid-tier doctor tools (Section 9): follow-up tracker, prescription
/// templates, drug-name autocomplete. UI gates on DoctorScope.paid; the DB
/// re-enforces every server-side rule (0015) regardless of what the client
/// claims.

/// One due/overdue follow-up row for the tracker (doctor's own patients).
class FollowUpItem {
  const FollowUpItem({
    required this.visitId,
    required this.patientId,
    required this.patientName,
    required this.diagnosis,
    required this.dueDate,
  });

  final String visitId;
  final String patientId;
  final String patientName;
  final String? diagnosis;
  final DateTime dueDate;

  bool get overdue => dueDate.isBefore(DateTime.now());
}

/// A saved prescription template.
class RxTemplate {
  const RxTemplate({required this.id, required this.name, required this.items});
  final String id;
  final String name;
  final List<Map<String, dynamic>> items;
}

abstract class PaidToolsRepository {
  /// Own patients with an open follow-up, soonest first (RLS scopes rows).
  Future<List<FollowUpItem>> followUps();

  /// One-tap "you're due" reminder (paid; DB checks tier + ownership).
  Future<void> sendFollowUpReminder(String visitId);

  Future<void> markFollowUpDone(String visitId);

  /// Distinct drug names from this doctor's own history (autocomplete).
  Future<List<String>> myDrugNames();

  Future<List<RxTemplate>> templates();
  Future<void> saveTemplate(String name, List<Map<String, dynamic>> items);
  Future<void> deleteTemplate(String id);
}

class SupabasePaidToolsRepository implements PaidToolsRepository {
  SupabasePaidToolsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<FollowUpItem>> followUps() async {
    final rows = await _client
        .from('visits')
        .select('id, patient_id, diagnosis, follow_up_date, patients(name)')
        .not('follow_up_date', 'is', null)
        .eq('follow_up_completed', false)
        .lte('follow_up_date',
            DateTime.now().add(const Duration(days: 7)).toIso8601String())
        .order('follow_up_date', ascending: true);
    return [
      for (final m in rows as List)
        FollowUpItem(
          visitId: m['id'] as String,
          patientId: m['patient_id'] as String,
          patientName:
              ((m['patients'] ?? const {}) as Map)['name'] as String? ?? '(unknown)',
          diagnosis: m['diagnosis'] as String?,
          dueDate: DateTime.parse(m['follow_up_date'].toString()),
        )
    ];
  }

  @override
  Future<void> sendFollowUpReminder(String visitId) => _client
      .rpc('carebridge_send_followup_reminder', params: {'p_visit': visitId});

  @override
  Future<void> markFollowUpDone(String visitId) => _client
      .from('visits')
      .update({'follow_up_completed': true}).eq('id', visitId);

  @override
  Future<List<String>> myDrugNames() async {
    final res = await _client.rpc('carebridge_my_drug_names');
    return [for (final m in res as List) (m as Map)['drug_name'] as String];
  }

  @override
  Future<List<RxTemplate>> templates() async {
    final rows = await _client
        .from('prescription_templates')
        .select('id, name, items')
        .order('name');
    return [
      for (final m in rows as List)
        RxTemplate(
          id: m['id'] as String,
          name: m['name'] as String,
          items: [
            for (final it in (m['items'] ?? []) as List)
              Map<String, dynamic>.from(it as Map)
          ],
        )
    ];
  }

  @override
  Future<void> saveTemplate(String name, List<Map<String, dynamic>> items) async {
    await _client.from('prescription_templates').insert({
      'doctor_id': _doctorIdFromJwt(),
      'name': name,
      'items': items,
    });
  }

  /// Reads active_doctor_id from the scoped JWT for the insert payload. This
  /// is a convenience, not a security boundary — the RLS with-check rejects
  /// any doctor_id that doesn't match the verified claim.
  String? _doctorIdFromJwt() {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) return null;
    try {
      final payload = jsonDecode(utf8.decode(
              base64Url.decode(base64Url.normalize(token.split('.')[1]))))
          as Map<String, dynamic>;
      return payload['active_doctor_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteTemplate(String id) =>
      _client.from('prescription_templates').delete().eq('id', id);
}

final paidToolsRepositoryProvider = Provider<PaidToolsRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a PaidToolsRepository override.');
  }
  return SupabasePaidToolsRepository(SupabaseService.client);
});

/// Thin seam over the speech_to_text plugin so widget tests can fake voice
/// input without a microphone.
abstract class VoiceInput {
  Future<bool> init();
  Future<void> listen(void Function(String text, bool isFinal) onResult);
  Future<void> stop();
}

class SpeechToTextVoiceInput implements VoiceInput {
  final _stt = stt.SpeechToText();

  @override
  Future<bool> init() => _stt.initialize();

  @override
  Future<void> listen(void Function(String text, bool isFinal) onResult) =>
      _stt.listen(onResult: (r) => onResult(r.recognizedWords, r.finalResult));

  @override
  Future<void> stop() => _stt.stop();
}

final voiceInputProvider = Provider<VoiceInput>((_) => SpeechToTextVoiceInput());
