import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';

/// One entry in the patient's notification feed (Section 5.1). Rows are
/// written server-side only (triggers / dispatcher); RLS scopes reads to the
/// signed-in patient.
class PatientNotification {
  const PatientNotification({
    required this.id,
    required this.type,
    this.payload = const {},
    this.scheduledFor,
    this.sentAt,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime? scheduledFor;
  final DateTime? sentAt;

  factory PatientNotification.fromMap(Map<String, dynamic> m) =>
      PatientNotification(
        id: m['id'] as String,
        type: (m['type'] ?? '') as String,
        payload: Map<String, dynamic>.from((m['payload'] ?? {}) as Map),
        scheduledFor: m['scheduled_for'] != null
            ? DateTime.tryParse(m['scheduled_for'].toString())
            : null,
        sentAt: m['sent_at'] != null
            ? DateTime.tryParse(m['sent_at'].toString())
            : null,
      );

  /// Plain-language line for the feed.
  String get message => switch (type) {
        'appointment_reminder' => 'Appointment reminder — you have a visit coming up.',
        'no_show' => 'You missed a scheduled appointment — tap to rebook.',
        'follow_up' => 'Follow-up due — your doctor advised a follow-up visit.',
        'report_ready' =>
          'Your ${payload['test_name'] ?? 'test'} report is ready to view.',
        'medication_reminder' =>
          'Medication reminder (${payload['slot'] ?? ''}): '
              '${(payload['drugs'] as List?)?.join(', ') ?? 'your medication'}.',
        'checked_in' =>
          'You\'re checked in — your token is #${payload['token'] ?? '?'}.',
        'your_turn' =>
          'It\'s your turn — token #${payload['token'] ?? '?'}. Please go in.',
        'appointment_approved' =>
          'Your appointment request was approved by the doctor.',
        'appointment_rejected' =>
          'Your appointment was cancelled by the clinic'
              '${(payload['reason'] != null && '${payload['reason']}'.isNotEmpty) ? ' — ${payload['reason']}' : ''}.',
        _ => 'You have a new notification.',
      };
}

abstract class NotificationsRepository {
  /// The signed-in patient's feed, newest first (RLS scopes rows).
  Future<List<PatientNotification>> feed();

  /// LIVE feed (Supabase Realtime, RLS-scoped to self), newest first. Each
  /// event is the full current list — powers the unread badge and the arrival
  /// sound without polling.
  Stream<List<PatientNotification>> watchFeed();

  /// Register this device's FCM token. STUB until Firebase is configured
  /// (Phase 8 flag): safe to call — becomes real with firebase_messaging.
  Future<void> registerDeviceToken(String token, String platform);
}

class SupabaseNotificationsRepository implements NotificationsRepository {
  SupabaseNotificationsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<PatientNotification>> feed() async {
    final rows = await _client
        .from('notifications')
        .select('id, type, payload, scheduled_for, sent_at')
        .order('scheduled_for', ascending: false)
        .limit(100);
    return [
      for (final m in rows as List)
        PatientNotification.fromMap(m as Map<String, dynamic>)
    ];
  }

  @override
  Stream<List<PatientNotification>> watchFeed() => _client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .order('scheduled_for', ascending: false)
          .limit(100)
          .map((rows) => [
                for (final m in rows)
                  PatientNotification.fromMap(Map<String, dynamic>.from(m))
              ]);

  @override
  Future<void> registerDeviceToken(String token, String platform) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client.from('device_tokens').upsert(
      {'auth_user_id': uid, 'fcm_token': token, 'platform': platform},
      onConflict: 'fcm_token',
    );
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a NotificationsRepository override.');
  }
  return SupabaseNotificationsRepository(SupabaseService.client);
});
