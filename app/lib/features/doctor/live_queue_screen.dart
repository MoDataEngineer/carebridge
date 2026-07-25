import 'dart:async';

import 'package:flutter/material.dart';
import '../../shared/widgets/pills_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../shared/models/enums.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import '../auth/clinic/clinic_sign_out_button.dart';
import 'doctor_models.dart';
import 'queue_repository.dart';

/// Live appointment/token tracker (Phase 10, paid tier — Section 9).
/// Doctor-scoped: own queue with check-in + "Call next". Admin-scoped:
/// clinic-wide tracker grouped by doctor (check-in = front desk; calling the
/// next patient stays doctor-only, enforced in the DB too).
/// Updates arrive via Supabase Realtime — each change signal refetches the
/// queue (Section 10: seconds, not polling).
class LiveQueueScreen extends ConsumerStatefulWidget {
  const LiveQueueScreen({super.key, required this.scope});
  final DoctorScope scope;

  @override
  ConsumerState<LiveQueueScreen> createState() => _LiveQueueScreenState();
}

class _LiveQueueScreenState extends ConsumerState<LiveQueueScreen> {
  List<QueueEntry>? _entries;
  StreamSubscription<void>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = ref
        .read(queueRepositoryProvider)
        .changes()
        .listen((_) => _reload());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final rows = await ref.read(queueRepositoryProvider).liveQueue();
      if (mounted) setState(() => _entries = rows);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Queue load failed: $e')));
      }
    }
  }

  Future<void> _checkIn(QueueEntry e) async {
    setState(() => _busy = true);
    try {
      final token = await ref.read(queueRepositoryProvider).checkIn(e.appointmentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.patientName} checked in — token $token')));
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Check-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _callNext() async {
    setState(() => _busy = true);
    try {
      final called = await ref.read(queueRepositoryProvider).callNext();
      if (!mounted) return;
      if (called == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No one is waiting.')));
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Call next failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.scope.role == ActiveRole.admin;
    final entries = _entries;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Clinic queue — all doctors' : 'Live queue'),
        automaticallyImplyLeading: false,
        actions: const [ThemeToggleButton(), ClinicSignOutButton()],
      ),
      // "Call next" is the doctor's action (AC-9-adjacent: who enters the
      // room is the doctor's call, not the front desk's).
      floatingActionButton: widget.scope.canWrite
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _callNext,
              icon: const Icon(Icons.campaign),
              label: const Text('Call next'),
            )
          : null,
      body: entries == null
          ? const Center(child: PillsLoader())
          : entries.isEmpty
              ? const Center(child: Text('No appointments today.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    for (final e in entries) _entryTile(e, isAdmin),
                  ],
                ),
    );
  }

  Widget _entryTile(QueueEntry e, bool isAdmin) {
    final scheme = Theme.of(context).colorScheme;
    final s = AppStatusColors.of(context);
    // Status → label + colour. Rendered as a text chip with a colour dot (no
    // icon), so it never depends on a glyph that might not be in the subset.
    final (String label, Color color) = switch (e.status) {
      'in_consultation' => ('In consultation', scheme.primary),
      'waiting' => ('Waiting', s.info),
      'completed' => ('Done', s.success),
      _ => ('Scheduled', s.warning),
    };
    final time = TimeOfDay.fromDateTime(e.scheduledTime.toLocal()).format(context);
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadii.rCard,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          // Token badge (mint circle) once checked in; a clock circle while
          // still only scheduled.
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.tintMint,
              shape: BoxShape.circle,
            ),
            child: e.queuePosition != null
                ? Text('${e.queuePosition}',
                    style: text.titleMedium?.copyWith(
                        color: AppColors.brand700, fontWeight: FontWeight.w800))
                : const Icon(Icons.schedule, size: 20, color: AppColors.brand700),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.patientName,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _statusChip(label, color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$time${isAdmin ? ' · ${e.doctorName}' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (e.status == 'scheduled')
            FilledButton.tonal(
              onPressed: _busy ? null : () => _checkIn(e),
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Check in'),
            ),
        ],
      ),
    );
  }

  /// A colour-dot + label chip — status conveyed by colour AND text (§5), never
  /// colour alone, and with no glyph dependency.
  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
