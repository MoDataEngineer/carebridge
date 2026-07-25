import 'package:flutter/material.dart';
import '../../shared/widgets/pills_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import '../auth/clinic/clinic_sign_out_button.dart';
import 'paid_tools_repository.dart';

/// Follow-up tracker (Section 5.2, paid, doctor-scoped): own patients with an
/// open follow-up due within a week or overdue; one-tap reminder + mark done.
/// The DB enforces tier, ownership, and AC-9 on every action.
class FollowUpsScreen extends ConsumerStatefulWidget {
  const FollowUpsScreen({super.key, this.onOpenPatient});

  /// Tapping a row opens that patient's record in the Patients tab (shell-wired,
  /// same as the live queue). FollowUpItem carries the name we hand back.
  final void Function(String patientName)? onOpenPatient;

  @override
  ConsumerState<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends ConsumerState<FollowUpsScreen> {
  List<FollowUpItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(paidToolsRepositoryProvider).followUps();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _remind(FollowUpItem f) async {
    try {
      await ref.read(paidToolsRepositoryProvider).sendFollowUpReminder(f.visitId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reminder sent to ${f.patientName}')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not send reminder: $e')));
      }
    }
  }

  Future<void> _done(FollowUpItem f) async {
    try {
      await ref.read(paidToolsRepositoryProvider).markFollowUpDone(f.visitId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow-ups'),
        automaticallyImplyLeading: false,
        actions: const [ThemeToggleButton(), ClinicSignOutButton()],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load follow-ups: $_error'),
                ),
              ])
            : _items == null
                ? const Center(child: PillsLoader())
                : _items!.isEmpty
                    ? ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: Text('No follow-ups due in the next week.')),
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: _items!.length,
                        itemBuilder: (context, i) => _followUpCard(_items![i]),
                      ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _fmt(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  Widget _followUpCard(FollowUpItem f) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadii.rCard,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: widget.onOpenPatient == null
            ? null
            : () => widget.onOpenPatient!(f.patientName),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(f.patientName,
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  _duePill(f),
                ],
              ),
              if (f.diagnosis != null && f.diagnosis!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(f.diagnosis!,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _remind(f),
                    icon: const Icon(Icons.notifications_active, size: 18),
                    label: const Text('Send reminder'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 40)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _done(f),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Mark done'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(44, 40)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Overdue" (red tint) or "Due <date>" (mint tint) — colour + text, no glyph.
  Widget _duePill(FollowUpItem f) {
    final scheme = Theme.of(context).colorScheme;
    final (String label, Color bg, Color fg) = f.overdue
        ? ('Overdue', scheme.errorContainer, scheme.onErrorContainer)
        : ('Due ${_fmt(f.dueDate)}', AppColors.tintMint, AppColors.brand700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
