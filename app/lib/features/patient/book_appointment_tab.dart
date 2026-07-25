import 'dart:async';

import 'package:flutter/material.dart';
import '../../shared/widgets/pills_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/brand_avatar.dart';
import 'patient_models.dart';
import 'patient_repository.dart';

/// Book-appointment tab (Section 5.1): pick the hospital/clinic first, then a
/// doctor at that clinic (with specialty), then date → request. Shows the
/// patient's existing appointments below, and — when the patient is in today's
/// queue — a LIVE tracker card that updates in real time as the doctor checks
/// them in and calls patients through (Supabase Realtime).
class BookAppointmentTab extends ConsumerStatefulWidget {
  const BookAppointmentTab({super.key});

  @override
  ConsumerState<BookAppointmentTab> createState() => _BookAppointmentTabState();
}

class _BookAppointmentTabState extends ConsumerState<BookAppointmentTab> {
  late Future<List<BookableDoctor>> _doctors;
  Map<String, String> _doctorNames = const {}; // doctorId -> name (for tracker)
  Map<String, BookableDoctor> _docsById = const {}; // branding for tracker/confirm

  List<AppointmentRecord> _appts = const [];
  bool _apptsLoading = true;
  NowServing? _nowServing;

  StreamSubscription<void>? _sub;
  Timer? _timer;

  String? _selectedState;
  String? _selectedCity;
  String? _selectedClinicId;
  BookableDoctor? _selected;
  DateTime _when = DateTime.now().add(const Duration(days: 1));
  bool _booking = false;

  // Sessions for the chosen doctor + date (migration 0026).
  List<AvailableSession>? _sessions;
  String? _selectedSessionId;
  bool _loadingSessions = false;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(patientRepositoryProvider);
    _doctors = repo.bookableDoctors();
    _doctors.then((list) {
      if (mounted) {
        setState(() {
          _doctorNames = {for (final d in list) d.doctorId: d.doctorName};
          _docsById = {for (final d in list) d.doctorId: d};
        });
      }
    }).catchError((_) {});
    _loadAppts();
    // Live: any change to the patient's own appointment rows (check-in, called,
    // completed) refetches. A short timer also refreshes "now serving" so the
    // count ahead ticks down as OTHER patients are seen (whose rows we can't see).
    _sub = repo.appointmentChanges().listen((_) => _loadAppts());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshNowServing());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAppts() async {
    try {
      final appts = await ref.read(patientRepositoryProvider).appointments();
      if (!mounted) return;
      setState(() {
        _appts = appts;
        _apptsLoading = false;
      });
      await _refreshNowServing();
    } catch (_) {
      if (mounted) setState(() => _apptsLoading = false);
    }
  }

  Future<void> _refreshNowServing() async {
    AppointmentRecord? active;
    for (final a in _appts) {
      if (a.isActiveToday && a.doctorId != null) {
        active = a;
        break;
      }
    }
    if (active == null) {
      if (mounted && _nowServing != null) setState(() => _nowServing = null);
      return;
    }
    try {
      final ns = await ref.read(patientRepositoryProvider).nowServing(active.doctorId!);
      if (mounted) setState(() => _nowServing = ns);
    } catch (_) {/* best-effort */}
  }

  Future<void> _loadSessions() async {
    final doc = _selected;
    if (doc == null) {
      setState(() {
        _sessions = null;
        _selectedSessionId = null;
      });
      return;
    }
    setState(() {
      _loadingSessions = true;
      _selectedSessionId = null;
    });
    try {
      final s = await ref
          .read(patientRepositoryProvider)
          .availableSessions(doc.doctorId, _when);
      if (mounted) setState(() => _sessions = s);
    } catch (_) {
      if (mounted) setState(() => _sessions = const []);
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _book() async {
    final sid = _selectedSessionId;
    if (sid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick a session first')));
      return;
    }
    final doc = _selected;
    setState(() => _booking = true);
    BookingResult? result;
    try {
      result =
          await ref.read(patientRepositoryProvider).requestAppointment(sid, _when);
      if (!mounted) return;
      await _loadAppts();
      await _loadSessions();
      if (mounted) setState(() => _selectedSessionId = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Booking failed: $e')));
      }
    } finally {
      // Clear the busy state BEFORE any confirmation dialog — otherwise the
      // button's spinner keeps animating behind the modal.
      if (mounted) setState(() => _booking = false);
    }

    if (!mounted || result == null) return;
    if (result.confirmed && doc != null) {
      // Booking-confirmed moment (reskin, reference #3): a bottom sheet with a
      // green check disc, doctor photo + hospital logo (branding spec) and the
      // scheduled details — instead of a passing snackbar.
      final green = AppStatusColors.of(context).success;
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded, size: 36, color: green),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Booking confirmed',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.titleLarge),
                Text('Your appointment has been scheduled.',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 20),
                Row(
                  children: [
                    BrandAvatar(
                        name: doc.doctorName, imageUrl: doc.photoUrl, radius: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(doc.doctorName,
                              style: Theme.of(ctx).textTheme.titleMedium),
                          Text(doc.clinicName,
                              style: Theme.of(ctx).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    BrandAvatar(
                        name: doc.clinicName,
                        imageUrl: doc.logoUrl,
                        radius: 18,
                        square: true),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.event, size: 18),
                    const SizedBox(width: 8),
                    Text(_when.toString().substring(0, 10)),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done')),
              ],
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.confirmed
            ? 'Appointment confirmed.'
            : 'This session is fully booked — your request was sent; the doctor may still approve it.'),
      ));
    }
  }

  Widget _sessionPicker() {
    if (_loadingSessions) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: PillsLoader(size: 28)),
      );
    }
    final sessions = _sessions;
    if (sessions == null) return const SizedBox.shrink();
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No consultation sessions on this day — try another date.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    // Slot chips (reskin, reference #3): tappable pills instead of list rows.
    // Full sessions stay selectable — overflow becomes a request (founder rule).
    AvailableSession? selected;
    for (final s in sessions) {
      if (s.sessionId == _selectedSessionId) selected = s;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Choose a session', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in sessions)
              ChoiceChip(
                selected: _selectedSessionId == s.sessionId,
                onSelected: (_) =>
                    setState(() => _selectedSessionId = s.sessionId),
                avatar: _selectedSessionId == s.sessionId
                    ? null
                    : Icon(
                        s.full ? Icons.hourglass_bottom : Icons.schedule,
                        size: 16,
                        color: s.full ? scheme.error : scheme.primary,
                      ),
                label: Text('${s.label ?? 'Session'} · ${s.window}'),
              ),
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                selected.full ? Icons.info_outline : Icons.event_available,
                size: 16,
                color: selected.full ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selected.full
                      ? 'Fully booked — the doctor may still approve your request'
                      : '${selected.remaining} of ${selected.capacity} slots left',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected.full ? scheme.error : null),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The one appointment the patient is actively in today (if any).
    AppointmentRecord? active;
    for (final a in _appts) {
      if (a.isActiveToday) {
        active = a;
        break;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (active != null) ...[
          _QueueTracker(
            appt: active,
            nowServing: _nowServing,
            doctorName: _doctorNames[active.doctorId],
            photoUrl: _docsById[active.doctorId]?.photoUrl,
          ),
          const SizedBox(height: 16),
        ],
        Text('Request an appointment', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        FutureBuilder<List<BookableDoctor>>(
          future: _doctors,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: PillsLoader(size: 28)),
              );
            }
            final docs = snap.data ?? const [];
            if (docs.isEmpty) return const Text('No doctors available to book yet.');
            final states = docs.map((d) => d.state).where((s) => s.isNotEmpty).toSet().toList()..sort();
            final cities = docs
                .where((d) => _selectedState == null || d.state == _selectedState)
                .map((d) => d.city)
                .where((c) => c.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            final inPlace = docs.where((d) =>
                (_selectedState == null || d.state == _selectedState) &&
                (_selectedCity == null || d.city == _selectedCity));
            final clinics = <String, String>{};
            for (final d in inPlace) {
              clinics.putIfAbsent(d.clinicId, () => d.clinicName);
            }
            final clinicIds = clinics.keys.toList()
              ..sort((a, b) => clinics[a]!.compareTo(clinics[b]!));
            final atClinic = [
              for (final d in docs)
                if (d.clinicId == _selectedClinicId) d
            ]..sort((a, b) => a.doctorName.compareTo(b.doctorName));
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedState,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'State',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final s in states)
                            DropdownMenuItem(value: s, child: Text(s)),
                        ],
                        onChanged: (v) => setState(() {
                          _selectedState = v;
                          _selectedCity = null;
                          _selectedClinicId = null;
                          _selected = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('city-$_selectedState'),
                        initialValue: _selectedCity,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'City',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final c in cities)
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) => setState(() {
                          _selectedCity = v;
                          _selectedClinicId = null;
                          _selected = null;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('clinic-$_selectedState-$_selectedCity'),
                  initialValue: _selectedClinicId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Hospital / clinic',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final id in clinicIds)
                      DropdownMenuItem(value: id, child: Text(clinics[id]!)),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedClinicId = v;
                    _selected = null;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BookableDoctor>(
                  key: ValueKey(_selectedClinicId),
                  initialValue: _selected,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Doctor',
                    helperText: _selectedClinicId == null
                        ? 'Pick a hospital first'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final d in atClinic)
                      DropdownMenuItem(
                        value: d,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                d.specialty.isEmpty
                                    ? d.doctorName
                                    : '${d.doctorName} · ${d.specialty}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (d.hprVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, size: 16, color: Colors.blue),
                            ],
                          ],
                        ),
                      ),
                  ],
                  onChanged: _selectedClinicId == null
                      ? null
                      : (v) {
                          setState(() => _selected = v);
                          _loadSessions();
                        },
                ),
                if (_selected != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      // Doctor photo (or initials) — branding, 0030.
                      leading: BrandAvatar(
                          name: _selected!.doctorName,
                          imageUrl: _selected!.photoUrl),
                      title: Text(_selected!.councilRegNumber.isEmpty
                          ? 'License details not provided'
                          : 'Reg. no ${_selected!.councilRegNumber}'
                            '${_selected!.councilName.isEmpty ? '' : ' · ${_selected!.councilName}'}'),
                      subtitle: Text(_selected!.hprVerified
                          ? 'Verified in the national Health Professional Registry'
                          : 'Registered medical practitioner'),
                      trailing: BrandAvatar(
                          name: _selected!.clinicName,
                          imageUrl: _selected!.logoUrl,
                          radius: 18,
                          square: true),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text('Date: ${_when.toString().substring(0, 10)}'),
          trailing: TextButton(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDate: _when,
              );
              if (date != null) {
                setState(() => _when = date);
                _loadSessions();
              }
            },
            child: const Text('Change'),
          ),
        ),
        // Sessions for the chosen doctor + date (migration 0026).
        if (_selected != null) _sessionPicker(),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _booking ? null : _book,
          child: _booking
              ? const SizedBox(
                  height: 20, width: 20, child: PillsLoader(size: 20))
              : const Text('Request appointment'),
        ),
        const Divider(height: 32),
        Text('Your appointments', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_apptsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: PillsLoader(size: 28)),
          )
        else if (_appts.isEmpty)
          const Text('No appointments yet.')
        else
          for (final a in _appts)
            ListTile(
              leading: const Icon(Icons.event_available),
              title: Text(a.scheduledTime.toString().substring(0, 16)),
              subtitle: Text('Status: ${a.status}'
                  '${a.queuePosition != null ? ' · token #${a.queuePosition}' : ''}'),
            ),
      ],
    );
  }
}

/// Prominent live card shown while the patient is in today's queue — updates in
/// real time via Realtime + a short poll for the "ahead of you" count.
class _QueueTracker extends StatelessWidget {
  const _QueueTracker(
      {required this.appt, this.nowServing, this.doctorName, this.photoUrl});
  final AppointmentRecord appt;
  final NowServing? nowServing;
  final String? doctorName;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final inConsult = appt.status == 'in_consultation';
    final ahead = nowServing?.aheadOf(appt.queuePosition);

    final String subtitle;
    if (inConsult) {
      subtitle = 'It\'s your turn — please go in.';
    } else if (nowServing?.servingToken != null) {
      subtitle = ahead == null || ahead <= 0
          ? 'Now serving #${nowServing!.servingToken} — you\'re next.'
          : 'Now serving #${nowServing!.servingToken} — $ahead ahead of you.';
    } else {
      subtitle = 'Checked in — waiting for the doctor to start.';
    }

    // Teal gradient hero card (reskin) — the live consultation header.
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: inConsult
              ? const [AppColors.brand600, AppColors.brand900]
              : const [AppColors.brand400, AppColors.brand700],
        ),
        borderRadius: AppRadii.rCard,
        boxShadow: [
          BoxShadow(
            color: AppColors.brand600.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Consultation header carries the doctor's face (branding).
              if (doctorName != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: BrandAvatar(
                      name: doctorName!, imageUrl: photoUrl, radius: 18),
                )
              else
                Icon(
                    inConsult
                        ? Icons.meeting_room
                        : Icons.confirmation_number,
                    color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doctorName == null
                      ? 'You\'re in the queue'
                      : 'In queue for $doctorName',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            appt.queuePosition != null
                ? 'Your token  #${appt.queuePosition}'
                : 'Checked in',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}
