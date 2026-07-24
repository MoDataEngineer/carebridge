import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/brand_avatar.dart';
import '../../shared/widgets/pills_loader.dart';
import 'patient_models.dart';
import 'patient_repository.dart';
import 'profile_screen.dart';

/// Patient Home dashboard (prototype redesign): a warm greeting, a hero card for
/// the next appointment, quick-access feature tiles, and a medications glance.
/// It never fetches anything the other tabs can't — it just surfaces the
/// patient's own profile + appointments up front. Feature tiles switch the
/// bottom-nav tab via [onNavigate] (1=Book, 2=History, 3=Tests, 4=Privacy).
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key, required this.onNavigate});

  final void Function(int tabIndex) onNavigate;

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  PatientProfile? _profile;
  List<AppointmentRecord> _appts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(patientRepositoryProvider);
    try {
      final results = await Future.wait([repo.loadProfile(), repo.appointments()]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as PatientProfile;
        _appts = results[1] as List<AppointmentRecord>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The soonest appointment that is still ahead of us and not cancelled/done.
  AppointmentRecord? get _nextAppt {
    final now = DateTime.now();
    for (final a in _appts) {
      final active = a.status != 'cancelled' && a.status != 'completed';
      final upcoming = a.scheduledTime.isAfter(now.subtract(const Duration(hours: 3)));
      if (active && upcoming) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PillsLoader());

    final theme = Theme.of(context);
    final firstName =
        (_profile?.name.trim().split(' ').first ?? '').isEmpty
            ? 'there'
            : _profile!.name.trim().split(' ').first;
    final meds = _profile?.currentMedications ?? const <String>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Greeting + profile avatar (Profile lives here now, not the bottom bar).
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hi, $firstName!',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text('How are you feeling today?',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ProfileScreen(),
              )),
              child: BrandAvatar(name: _profile?.name ?? 'Me'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        _HeroAppointment(next: _nextAppt, onBook: () => widget.onNavigate(1)),
        const SizedBox(height: AppSpacing.lg),

        // Quick access — the same destinations as the bottom bar, up front.
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.55,
          children: [
            _FeatureTile(
              label: 'Book visit',
              caption: 'Find a doctor',
              icon: Icons.event,
              tint: AppColors.tintMint,
              onTap: () => widget.onNavigate(1),
            ),
            _FeatureTile(
              label: 'History',
              caption: 'Past visits',
              icon: Icons.history,
              tint: AppColors.tintSky,
              onTap: () => widget.onNavigate(2),
            ),
            _FeatureTile(
              label: 'Tests',
              caption: 'Orders & reports',
              icon: Icons.science_outlined,
              tint: AppColors.tintLavender,
              onTap: () => widget.onNavigate(3),
            ),
            _FeatureTile(
              label: 'Privacy',
              caption: 'Who has access',
              icon: Icons.shield_outlined,
              tint: AppColors.tintPeach,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ProfileScreen(initialTab: 1),
              )),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        _MedsCard(meds: meds),
      ],
    );
  }
}

/// Teal-gradient hero: the next appointment, or a book-a-visit prompt.
class _HeroAppointment extends StatelessWidget {
  const _HeroAppointment({required this.next, required this.onBook});

  final AppointmentRecord? next;
  final VoidCallback onBook;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _when(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    final day = sameDay ? 'Today' : '${t.day} ${_months[t.month - 1]}';
    return '$day · $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadii.rCard,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand600, AppColors.brand800],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand700.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: next == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NO UPCOMING VISIT',
                    style: text.labelSmall?.copyWith(
                        color: Colors.white70, letterSpacing: 1)),
                const SizedBox(height: 6),
                Text('Book your next appointment',
                    style: text.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onBook,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.brand700,
                    minimumSize: const Size(140, 44),
                  ),
                  child: const Text('Book a visit'),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NEXT APPOINTMENT',
                          style: text.labelSmall?.copyWith(
                              color: Colors.white70, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      Text(_when(next!.scheduledTime),
                          style: text.titleLarge?.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _StatusChip(status: next!.status, token: next!.queuePosition),
                    ],
                  ),
                ),
                const Icon(Icons.event_available, color: Colors.white, size: 40),
              ],
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.token});
  final String status;
  final int? token;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'requested' => 'Awaiting confirmation',
      'scheduled' => 'Confirmed',
      'waiting' => token != null ? 'Waiting · token #$token' : 'Checked in',
      'in_consultation' => 'In consultation',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Colors.white)),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.label,
    required this.caption,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final String caption;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: tint,
      borderRadius: AppRadii.rCard,
      child: InkWell(
        borderRadius: AppRadii.rCard,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white,
                child: Icon(icon, size: 20, color: AppColors.brand700),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(caption,
                      style: text.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedsCard extends StatelessWidget {
  const _MedsCard({required this.meds});
  final List<String> meds;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medication_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Current medications', style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            if (meds.isEmpty)
              Text('None on file — add them in your profile.',
                  style: text.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final m in meds) Chip(label: Text(m))],
              ),
          ],
        ),
      ),
    );
  }
}
