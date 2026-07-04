import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/enums.dart';
import 'doctor_models.dart';
import 'doctor_repository.dart';
import 'paid_tools_repository.dart';
import 'rx_voice_parser.dart';

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

  // Paid tools (Section 9): drug autocomplete + templates + voice input.
  List<String> _drugNames = const [];
  List<RxTemplate> _templates = const [];
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (widget.scope.paid) {
      // Best-effort loads; the form works without them.
      ref.read(paidToolsRepositoryProvider).myDrugNames().then((v) {
        if (mounted) setState(() => _drugNames = v);
      }).catchError((_) {});
      ref.read(paidToolsRepositoryProvider).templates().then((v) {
        if (mounted) setState(() => _templates = v);
      }).catchError((_) {});
    }
  }

  /// Voice prescription (paid, D6): dictation -> deterministic parse ->
  /// filled draft the doctor MUST review — never auto-saved.
  Future<void> _voiceInput() async {
    final voice = ref.read(voiceInputProvider);
    final ok = await voice.init();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Microphone/speech recognition unavailable')));
      }
      return;
    }
    setState(() => _listening = true);
    await voice.listen((text, isFinal) {
      if (!isFinal || !mounted) return;
      setState(() => _listening = false);
      final parsed = parseSpokenPrescription(text);
      if (parsed == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not understand: "$text" — try again')));
        return;
      }
      setState(() {
        final d = _emptyOrNewDraft();
        d.drug.text = parsed.drugName;
        if (parsed.dosage != null) d.dosage.text = parsed.dosage!;
        if (parsed.durationDays != null) {
          d.durationDays.text = '${parsed.durationDays}';
        }
        parsed.schedule.forEach((k, v) => d.schedule[k] = v);
        d.food = switch (parsed.relationToFood) {
          'before' => FoodRelation.before,
          'after' => FoodRelation.after,
          'with' => FoodRelation.withFood,
          _ => FoodRelation.none,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Heard you — review the prescription before saving')));
    });
  }

  _PrescriptionDraft _emptyOrNewDraft() {
    final empty = _rx.where((d) => d.drug.text.trim().isEmpty).firstOrNull;
    if (empty != null) return empty;
    final d = _PrescriptionDraft();
    _rx.add(d);
    return d;
  }

  Future<void> _saveAsTemplate() async {
    final items = _rx
        .where((d) => d.drug.text.trim().isNotEmpty)
        .map((d) => {
              'drug_name': d.drug.text.trim(),
              'dosage': d.dosage.text.trim(),
              'schedule': Map.of(d.schedule),
              'duration_days': int.tryParse(d.durationDays.text.trim()),
            })
        .toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one prescription first')));
      return;
    }
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as template'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Template name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await ref
          .read(paidToolsRepositoryProvider)
          .saveTemplate(ctrl.text.trim(), items);
      final refreshed = await ref.read(paidToolsRepositoryProvider).templates();
      if (mounted) {
        setState(() => _templates = refreshed);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Template saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save template: $e')));
      }
    }
  }

  void _applyTemplate(RxTemplate t) {
    setState(() {
      for (final item in t.items) {
        final d = _emptyOrNewDraft();
        d.drug.text = (item['drug_name'] ?? '') as String;
        d.dosage.text = (item['dosage'] ?? '') as String;
        final dur = item['duration_days'];
        d.durationDays.text = dur == null ? '' : '$dur';
        final sched = (item['schedule'] ?? const {}) as Map;
        sched.forEach((k, v) {
          if (d.schedule.containsKey('$k')) d.schedule['$k'] = v == true;
        });
      }
    });
  }

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
        Row(
          children: [
            Expanded(
              child: Text('Prescriptions',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            // Paid tools (Section 9): voice + templates.
            if (widget.scope.paid) ...[
              IconButton(
                tooltip: 'Voice prescription',
                icon: Icon(_listening ? Icons.mic : Icons.mic_none,
                    color: _listening
                        ? Theme.of(context).colorScheme.error
                        : null),
                onPressed: _voiceInput,
              ),
              PopupMenuButton<String>(
                tooltip: 'Templates',
                icon: const Icon(Icons.snippet_folder_outlined),
                onSelected: (v) {
                  if (v == '__save__') {
                    _saveAsTemplate();
                  } else {
                    _applyTemplate(_templates.firstWhere((t) => t.id == v));
                  }
                },
                itemBuilder: (_) => [
                  for (final t in _templates)
                    PopupMenuItem(value: t.id, child: Text(t.name)),
                  const PopupMenuItem(
                      value: '__save__', child: Text('Save current as template…')),
                ],
              ),
            ],
          ],
        ),
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
            // Paid: autocomplete from this doctor's own prescribing history.
            RawAutocomplete<String>(
              textEditingController: d.drug,
              focusNode: d.focus,
              optionsBuilder: (v) {
                if (!widget.scope.paid || v.text.trim().length < 2) {
                  return const Iterable<String>.empty();
                }
                final q = v.text.trim().toLowerCase();
                return _drugNames.where((n) => n.toLowerCase().contains(q));
              },
              onSelected: (v) => setState(() => d.drug.text = v),
              fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: const InputDecoration(labelText: 'Drug name'),
              ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180, maxWidth: 320),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final o in options)
                          ListTile(
                            dense: true,
                            title: Text(o),
                            onTap: () => onSelected(o),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
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
  final focus = FocusNode();
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
    focus.dispose();
    dosage.dispose();
    durationDays.dispose();
  }
}
