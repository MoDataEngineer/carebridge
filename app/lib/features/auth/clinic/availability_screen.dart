import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/responsive_scaffold.dart';
import 'availability_models.dart';
import 'availability_repository.dart';

/// Weekly availability editor (founder request 2026-07-07). The doctor's
/// consultation times per weekday, each session with a patient capacity. Reached
/// from the roster (admin) or the doctor's own session. Patients book against
/// these in Phase C.
class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key, required this.doctorId, required this.doctorName});

  final String doctorId;
  final String doctorName;

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  List<DoctorSession>? _sessions;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(availabilityRepositoryProvider).sessionsFor(widget.doctorId);
      if (mounted) setState(() => _sessions = s);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(availabilityRepositoryProvider)
          .setSessions(widget.doctorId, _sessions ?? const []);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Availability saved')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addSession(int day) {
    setState(() => _sessions!.add(DoctorSession(
          dayOfWeek: day,
          label: null,
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 12, minute: 0),
          capacity: 20,
        )));
  }

  void _copyToAllDays(int fromDay) {
    final source = _sessions!.where((s) => s.dayOfWeek == fromDay).toList();
    setState(() {
      _sessions!.clear();
      for (final day in kWeekOrder) {
        for (final s in source) {
          _sessions!.add(s.copyForDay(day));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Availability · ${widget.doctorName}',
      maxContentWidth: 640,
      child: _error != null
          ? Text('Could not load availability: $_error')
          : _sessions == null
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Set consultation sessions for each day. Patients book into a '
                      'session; capacity is how many patients it holds before it '
                      'reads as full.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final day in kWeekOrder) _dayCard(day),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save availability'),
                    ),
                  ],
                ),
    );
  }

  Widget _dayCard(int day) {
    final sessions = _sessions!.where((s) => s.dayOfWeek == day).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(kWeekdayNames[day],
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (sessions.isNotEmpty)
                  TextButton(
                    onPressed: () => _copyToAllDays(day),
                    child: const Text('Copy to all days'),
                  ),
                IconButton(
                  tooltip: 'Add session',
                  icon: const Icon(Icons.add),
                  onPressed: () => _addSession(day),
                ),
              ],
            ),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Closed — no sessions.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            else
              for (final s in sessions) _sessionRow(s),
          ],
        ),
      ),
    );
  }

  Widget _sessionRow(DoctorSession s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: ValueKey('label-${identityHashCode(s)}'),
                  initialValue: s.label ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Label (e.g. Morning)',
                    isDense: true,
                  ),
                  onChanged: (v) => s.label = v.trim().isEmpty ? null : v.trim(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: ValueKey('cap-${identityHashCode(s)}'),
                  initialValue: '${s.capacity}',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max patients', isDense: true),
                  onChanged: (v) => s.capacity = int.tryParse(v) ?? s.capacity,
                ),
              ),
              IconButton(
                tooltip: 'Remove session',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _sessions!.remove(s)),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text('From ${s.start.format(context)}'),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: s.start);
                    if (t != null) setState(() => s.start = t);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text('To ${s.end.format(context)}'),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: s.end);
                    if (t != null) setState(() => s.end = t);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
