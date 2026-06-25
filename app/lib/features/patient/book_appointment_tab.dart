import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'patient_models.dart';
import 'patient_repository.dart';

/// Book-appointment tab (Section 5.1). Phase 3 is a simple request form (pick a
/// doctor + date/time); real availability/slots is Phase 10. Shows the patient's
/// existing appointments below.
class BookAppointmentTab extends ConsumerStatefulWidget {
  const BookAppointmentTab({super.key});

  @override
  ConsumerState<BookAppointmentTab> createState() => _BookAppointmentTabState();
}

class _BookAppointmentTabState extends ConsumerState<BookAppointmentTab> {
  late Future<List<BookableDoctor>> _doctors;
  late Future<List<AppointmentRecord>> _appointments;
  BookableDoctor? _selected;
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
            return DropdownButtonFormField<BookableDoctor>(
              initialValue: _selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Doctor',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final d in docs)
                  DropdownMenuItem(
                    value: d,
                    child: Text('${d.doctorName} · ${d.clinicName}'),
                  ),
              ],
              onChanged: (v) => setState(() => _selected = v),
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
