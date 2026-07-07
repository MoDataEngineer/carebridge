import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void initState() {
    super.initState();
    final repo = ref.read(patientRepositoryProvider);
    _doctors = repo.bookableDoctors();
    _doctors.then((list) {
      if (mounted) {
        setState(() =>
            _doctorNames = {for (final d in list) d.doctorId: d.doctorName});
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

  Future<void> _book() async {
    final doc = _selected;
    if (doc == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick a doctor first')));
      return;
    }
    setState(() => _booking = true);
    try {
      await ref.read(patientRepositoryProvider).bookAppointment(doctor: doc, when: _when);
      if (!mounted) return;
      await _loadAppts();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Appointment requested')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Booking failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
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
          ),
          const SizedBox(height: 16),
        ],
        Text('Request an appointment', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        FutureBuilder<List<BookableDoctor>>(
          future: _doctors,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
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
                      : (v) => setState(() => _selected = v),
                ),
                if (_selected != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        _selected!.hprVerified ? Icons.verified : Icons.badge_outlined,
                        color: _selected!.hprVerified ? Colors.blue : null,
                      ),
                      title: Text(_selected!.councilRegNumber.isEmpty
                          ? 'License details not provided'
                          : 'Reg. no ${_selected!.councilRegNumber}'
                            '${_selected!.councilName.isEmpty ? '' : ' · ${_selected!.councilName}'}'),
                      subtitle: Text(_selected!.hprVerified
                          ? 'Verified in the national Health Professional Registry'
                          : 'Registered medical practitioner'),
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
          leading: const Icon(Icons.schedule),
          title: Text('When: ${_when.toString().substring(0, 16)}'),
          trailing: TextButton(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDate: _when,
              );
              if (date != null) setState(() => _when = date);
            },
            child: const Text('Change'),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _booking ? null : _book,
          child: _booking
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Request appointment'),
        ),
        const Divider(height: 32),
        Text('Your appointments', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_apptsLoading)
          const LinearProgressIndicator()
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
  const _QueueTracker({required this.appt, this.nowServing, this.doctorName});
  final AppointmentRecord appt;
  final NowServing? nowServing;
  final String? doctorName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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

    return Card(
      color: inConsult ? scheme.primary : scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(inConsult ? Icons.meeting_room : Icons.confirmation_number,
                    color: inConsult ? scheme.onPrimary : scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    doctorName == null
                        ? 'You\'re in the queue'
                        : 'In queue for $doctorName',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: inConsult ? scheme.onPrimary : scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              appt.queuePosition != null ? 'Your token  #${appt.queuePosition}' : 'Checked in',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: inConsult ? scheme.onPrimary : scheme.onPrimaryContainer,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: inConsult ? scheme.onPrimary : scheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
