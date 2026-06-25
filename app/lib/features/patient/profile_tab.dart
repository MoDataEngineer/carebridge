import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'patient_models.dart';
import 'patient_repository.dart';

/// Profile tab: structured allergies / chronic conditions / current medications
/// (Section 5.1), editable and saved back through the patient-self RLS path.
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  PatientProfile? _profile;
  final _name = TextEditingController();
  late List<String> _allergies;
  late List<String> _chronic;
  late List<String> _meds;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ref.read(patientRepositoryProvider).loadProfile();
      setState(() {
        _profile = p;
        _name.text = p.name;
        _allergies = [...p.allergies];
        _chronic = [...p.chronicConditions];
        _meds = [...p.currentMedications];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final base = _profile;
    if (base == null) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(patientRepositoryProvider).saveProfile(
            base.copyWith(
              name: _name.text.trim(),
              allergies: _allergies,
              chronicConditions: _chronic,
              currentMedications: _meds,
            ),
          );
      if (!mounted) return;
      setState(() => _profile = updated);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Could not load profile: $_error'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Full name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (_profile?.abhaId == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('ABHA not linked (optional in pilot)',
                style: TextStyle(fontStyle: FontStyle.italic)),
          ),
        _ChipEditor(
          label: 'Allergies',
          values: _allergies,
          onChanged: (v) => setState(() => _allergies = v),
        ),
        _ChipEditor(
          label: 'Chronic conditions',
          values: _chronic,
          onChanged: (v) => setState(() => _chronic = v),
        ),
        _ChipEditor(
          label: 'Current medications',
          values: _meds,
          onChanged: (v) => setState(() => _meds = v),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save profile'),
        ),
      ],
    );
  }
}

/// Add/remove string chips for a structured list field.
class _ChipEditor extends StatefulWidget {
  const _ChipEditor({required this.label, required this.values, required this.onChanged});
  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ChipEditor> createState() => _ChipEditorState();
}

class _ChipEditorState extends State<_ChipEditor> {
  final _ctrl = TextEditingController();

  void _add() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    widget.onChanged([...widget.values, v]);
    _ctrl.clear();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final v in widget.values)
                Chip(
                  label: Text(v),
                  onDeleted: () => widget.onChanged(
                    [...widget.values]..remove(v),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: 'Add ${widget.label.toLowerCase()}…',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              IconButton(icon: const Icon(Icons.add), onPressed: _add),
            ],
          ),
        ],
      ),
    );
  }
}
