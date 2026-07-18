import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/constants/medical_conditions.dart';
import '../abha/abdm_models.dart';
import '../abha/abha_link_screen.dart';
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
  final _abha = TextEditingController();
  late List<String> _allergies;
  late List<String> _chronic;
  late List<String> _meds;
  bool _loading = true;
  bool _saving = false;
  bool _linking = false;
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
        _abha.text = p.abhaId ?? '';
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
    final abha = _abha.text.replaceAll(RegExp(r'[\s-]'), '');
    if (abha.isNotEmpty && !RegExp(r'^\d{14}$').hasMatch(abha)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ABHA number is 14 digits — or leave it blank.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await ref.read(patientRepositoryProvider).saveProfile(
            base.copyWith(
              name: _name.text.trim(),
              abhaId: abha, // blank saves as NULL (repository)
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

  /// Open the in-app ABHA flow (create or verify). On success the linked ABHA
  /// number flows back into the field and the profile is saved immediately, so
  /// the link is persisted without a second tap.
  Future<void> _linkAbha(AbhaLinkMode mode) async {
    setState(() => _linking = true);
    try {
      final profile = await Navigator.of(context).push<AbhaProfile>(
        MaterialPageRoute(builder: (_) => AbhaLinkScreen(mode: mode)),
      );
      if (profile == null || !mounted) return;
      _abha.text = profile.abhaNumber;
      await _save();
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _abha.dispose();
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
        const SizedBox(height: 12),
        // D3 / Phase 11: ABHA optional in pilot — captured (not yet verified;
        // verification needs ABDM sandbox keys). REQUIRE_ABHA flips it to
        // mandatory later.
        TextField(
          controller: _abha,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'ABHA number (optional)',
            hintText: '14-digit ABHA — link it below, or leave blank',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        // ID-1 / ID-2: link an ABHA in-app via ABDM. Create makes a new ABHA
        // from Aadhaar; Verify links an existing one. Both write the resulting
        // number back into the field above and save.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _linking ? null : () => _linkAbha(AbhaLinkMode.create),
                icon: const Icon(Icons.add_card, size: 18),
                label: const Text('Create ABHA'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _linking ? null : () => _linkAbha(AbhaLinkMode.verify),
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('Verify ABHA'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _SafetyHeader(),
        _ChipEditor(
          label: 'Allergies',
          values: _allergies,
          suggestions: kCommonAllergies,
          onChanged: (v) => setState(() => _allergies = v),
        ),
        _ChipEditor(
          label: 'Chronic conditions',
          values: _chronic,
          suggestions: kCommonChronicConditions,
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

/// Prominent banner over the allergies / conditions / medications fields — this
/// is the Layer-1 safety information a doctor sees first, so it must stay
/// visible and never collapse into an accordion (UI brief §3).
class _SafetyHeader extends StatelessWidget {
  const _SafetyHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.health_and_safety_outlined, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Safety information',
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                  'Shown to any doctor you grant access — keep it up to date.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Add/remove string chips for a structured list field. When [suggestions] is
/// non-empty the input becomes a searchable picker (type to filter, tap to add)
/// mirroring the doctor-registration specialty field — free text stays allowed
/// so an unlisted entry never blocks saving.
class _ChipEditor extends StatefulWidget {
  const _ChipEditor({
    required this.label,
    required this.values,
    required this.onChanged,
    this.suggestions = const [],
  });
  final String label;
  final List<String> values;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ChipEditor> createState() => _ChipEditorState();
}

class _ChipEditorState extends State<_ChipEditor> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  void _add([String? value]) {
    final v = (value ?? _ctrl.text).trim();
    if (v.isEmpty) return;
    // Skip case-insensitive duplicates so tapping a suggestion twice is a no-op.
    if (widget.values.any((e) => e.toLowerCase() == v.toLowerCase())) {
      _ctrl.clear();
      return;
    }
    widget.onChanged([...widget.values, v]);
    _ctrl.clear();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
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
                child: widget.suggestions.isEmpty ? _plainField() : _pickerField(),
              ),
              IconButton(icon: const Icon(Icons.add), onPressed: () => _add()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _plainField() => TextField(
        controller: _ctrl,
        decoration: InputDecoration(
          hintText: 'Add ${widget.label.toLowerCase()}…',
          isDense: true,
        ),
        onSubmitted: (_) => _add(),
      );

  /// Searchable picker over [suggestions] — already-selected values are hidden
  /// from the list, and tapping an option adds it immediately.
  Widget _pickerField() => RawAutocomplete<String>(
        textEditingController: _ctrl,
        focusNode: _focus,
        optionsBuilder: (v) {
          final q = v.text.trim().toLowerCase();
          final chosen = widget.values.map((e) => e.toLowerCase()).toSet();
          return widget.suggestions.where((s) =>
              !chosen.contains(s.toLowerCase()) &&
              (q.isEmpty || s.toLowerCase().contains(q)));
        },
        onSelected: _add,
        fieldViewBuilder: (ctx, ctrl, focus, _) => TextField(
          controller: ctrl,
          focusNode: focus,
          decoration: InputDecoration(
            hintText: 'Search or add ${widget.label.toLowerCase()}…',
            isDense: true,
          ),
          onSubmitted: (_) => _add(),
        ),
        optionsViewBuilder: (ctx, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
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
      );
}
