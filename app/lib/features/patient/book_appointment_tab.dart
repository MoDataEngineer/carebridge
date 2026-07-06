import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'patient_models.dart';
import 'patient_repository.dart';

/// Book-appointment tab (Section 5.1): pick the hospital/clinic first, then a
/// doctor at that clinic (with specialty), then date → request. Shows the
/// patient's existing appointments below.
class BookAppointmentTab extends ConsumerStatefulWidget {
  const BookAppointmentTab({super.key});

  @override
  ConsumerState<BookAppointmentTab> createState() => _BookAppointmentTabState();
}

class _BookAppointmentTabState extends ConsumerState<BookAppointmentTab> {
  late Future<List<BookableDoctor>> _doctors;
  late Future<List<AppointmentRecord>> _appointments;
  String? _selectedState; // location filters (2026-07-06)
  String? _selectedCity;
  String? _selectedClinicId; // hospital/clinic
  BookableDoctor? _selected; // doctor at that clinic
  DateTime _when = DateTime.now().add(const Duration(days: 1));
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repo = ref.read(patientRepositoryProvider);
    _doctors = repo.bookableDoctors();
    _appointments = repo.appointments();
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
      setState(_reload);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Appointment requested')));
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
            // Location filters: distinct states, then cities in that state.
            final states = docs.map((d) => d.state).where((s) => s.isNotEmpty).toSet().toList()..sort();
            final cities = docs
                .where((d) => _selectedState == null || d.state == _selectedState)
                .map((d) => d.city)
                .where((c) => c.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            // Hospitals in the chosen place, alphabetical.
            final inPlace = docs.where((d) =>
                (_selectedState == null || d.state == _selectedState) &&
                (_selectedCity == null || d.city == _selectedCity));
            final clinics = <String, String>{}; // id -> name
            for (final d in inPlace) {
              clinics.putIfAbsent(d.clinicId, () => d.clinicName);
            }
            final clinicIds = clinics.keys.toList()
              ..sort((a, b) => clinics[a]!.compareTo(clinics[b]!));
            // Doctors at the chosen clinic only.
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
                    _selected = null; // clinic changed — re-pick the doctor
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BookableDoctor>(
                  key: ValueKey(_selectedClinicId), // reset on clinic change
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
                // Trust card (2026-07-06): the doctor's council registration
                // is always shown; the badge only when HPR is verified.
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
        FutureBuilder<List<AppointmentRecord>>(
          future: _appointments,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            final appts = snap.data ?? const [];
            if (appts.isEmpty) return const Text('No appointments yet.');
            return Column(
              children: [
                for (final a in appts)
                  ListTile(
                    leading: const Icon(Icons.event_available),
                    title: Text(a.scheduledTime.toString().substring(0, 16)),
                    subtitle: Text('Status: ${a.status}'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
