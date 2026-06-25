import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/enums.dart';
import 'doctor_models.dart';
import 'doctor_repository.dart';

/// Add-visit form (Section 5.2) — doctor-scoped only (AC-9). Captures a diagnosis,
/// optional notes/follow-up, and one or more prescription lines using the D5
/// structured schedule fields. Voice input (D6) and templates land in Phase 9.
class AddVisitForm extends ConsumerStatefulWidget {
  const AddVisitForm({
    super.key,
    required this.scope,
    required this.patient,
    required this.onSaved,
  });

  final DoctorScope scope;
  final PatientSearchResult patient;
  final VoidCallback onSaved;

  @override
  ConsumerState<AddVisitForm> createState() => _AddVisitFormState();
}

class _AddVisitFormState extends ConsumerState<AddVisitForm> {
  final _diagnosis = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _followUp;
  final List<_PrescriptionDraft> _rx = [_PrescriptionDraft()];
  bool _saving = false;

  @override
  void dispose() {
    _diagnosis.dispose();
    _notes.dispose();
    for (final d in _rx) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_diagnosis.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a diagnosis')));
      return;
    }
    final scope = widget.scope;
    // UI mirror of AC-9; the DB rejects this too if it ever slipped through.
    if (!scope.canWrite || scope.doctorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Writing a visit requires a doctor identity'),
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final prescriptions = _rx
          .where((d) => d.drug.text.trim().isNotEmpty)
          .map((d) => d.toModel())
          .toList();
      await ref.read(doctorRepositoryProvider).addVisit(
            patientId: widget.patient.id,
            doctorId: scope.doctorId!,
            clinicId: scope.clinicId,
            visit: NewVisit(
              diagnosis: _diagnosis.text.trim(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              followUpDate: _followUp,
              prescriptions: prescriptions,
            ),
          );
      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save visit: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('New visit · ${widget.patient.name}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _diagnosis,
          decoration: const InputDecoration(
            labelText: 'Diagnosis',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_repeat),
          title: Text(_followUp == null
              ? 'No follow-up'
              : 'Follow-up: ${_followUp!.toString().substring(0, 10)}'),
          trailing: TextButton(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDate: _followUp ?? DateTime.now().add(const Duration(days: 7)),
              );
              if (d != null) setState(() => _followUp = d);
            },
            child: const Text('Set'),
          ),
        ),
        const Divider(height: 24),
        Text('Prescriptions', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var i = 0; i < _rx.length; i++) _prescriptionCard(i),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _rx.add(_PrescriptionDraft())),
            icon: const Icon(Icons.add),
            label: const Text('Add prescription'),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save visit'),
        ),
      ],
    );
  }

  Widget _prescriptionCard(int i) {
    final d = _rx[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: d.drug,
              decoration: const InputDecoration(labelText: 'Drug name'),
            ),
            TextField(
              controller: d.dosage,
              decoration: const InputDecoration(labelText: 'Dosage (e.g. 10mg)'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final slot in const ['morning', 'afternoon', 'night'])
                  FilterChip(
                    label: Text(slot[0].toUpperCase() + slot.substring(1)),
                    selected: d.schedule[slot]!,
                    onSelected: (v) => setState(() => d.schedule[slot] = v),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: d.durationDays,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Duration (days)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<FoodRelation>(
                    initialValue: d.food,
                    decoration: const InputDecoration(labelText: 'Food'),
                    items: const [
                      DropdownMenuItem(value: FoodRelation.none, child: Text('—')),
                      DropdownMenuItem(value: FoodRelation.before, child: Text('Before')),
                      DropdownMenuItem(value: FoodRelation.after, child: Text('After')),
                      DropdownMenuItem(value: FoodRelation.withFood, child: Text('With')),
                    ],
                    onChanged: (v) => setState(() => d.food = v ?? FoodRelation.none),
                  ),
                ),
                if (_rx.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      _rx.removeAt(i).dispose();
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mutable per-line editing state for one prescription card.
class _PrescriptionDraft {
  final drug = TextEditingController();
  final dosage = TextEditingController();
  final durationDays = TextEditingController();
  final Map<String, bool> schedule = {'morning': false, 'afternoon': false, 'night': false};
  FoodRelation food = FoodRelation.none;

  NewPrescription toModel() => NewPrescription(
        drugName: drug.text.trim(),
        dosage: dosage.text.trim().isEmpty ? null : dosage.text.trim(),
        schedule: Map.of(schedule),
        relationToFood: food,
        durationDays: int.tryParse(durationDays.text.trim()),
      );

  void dispose() {
    drug.dispose();
    dosage.dispose();
    durationDays.dispose();
  }
}
