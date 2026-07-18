import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_controller.dart';
import 'notifications_repository.dart';

/// Gap B (founder 2026-07-18): the notification rows were being written but the
/// patient got no visible/audible signal. This wires the live feed into an
/// unread badge on the bell plus an arrival chime. "Read" state is a local
/// last-seen timestamp (shared_preferences) — no migration, per-device, which
/// matches how a feed badge is expected to behave.

/// The live notification feed. Falls back to an empty stream when the
/// repository is unavailable (widget tests without an override, placeholder
/// mode) so screens still render.
final notificationsFeedProvider =
    StreamProvider<List<PatientNotification>>((ref) {
  try {
    return ref.watch(notificationsRepositoryProvider).watchFeed();
  } catch (_) {
    return Stream.value(const []);
  }
});

/// When the patient last opened the notifications screen (persisted).
class NotificationsSeenController extends StateNotifier<DateTime?> {
  NotificationsSeenController(this._ref) : super(null) {
    final ms = _ref.read(sharedPreferencesProvider)?.getInt(_key);
    if (ms != null) state = DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static const _key = 'notifications_last_seen';
  final Ref _ref;

  /// Opening the feed marks everything currently in it as seen.
  void markSeen() {
    final now = DateTime.now();
    state = now;
    _ref
        .read(sharedPreferencesProvider)
        ?.setInt(_key, now.millisecondsSinceEpoch);
  }
}

final notificationsSeenProvider =
    StateNotifierProvider<NotificationsSeenController, DateTime?>(
        NotificationsSeenController.new);

DateTime? _when(PatientNotification n) => n.sentAt ?? n.scheduledFor;

/// How many notifications arrived after the patient last opened the feed.
/// Drives the badge on the bell.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsFeedProvider).valueOrNull;
  if (items == null || items.isEmpty) return 0;
  final seen = ref.watch(notificationsSeenProvider);
  if (seen == null) return items.length;
  return items.where((n) {
    final t = _when(n);
    return t != null && t.isAfter(seen);
  }).length;
});
