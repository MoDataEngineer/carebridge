import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/constants/medical_specialties.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'clinic_models.dart';
import 'roster_repository.dart';
import 'session_controller.dart';

/// Admin-scoped roster management (Section 5.2): list the hospital's doctors
/// and add new ones (ID-4: name, medical council reg number, council name,
/// specialty, optional HPR — never block on HPR). A solo doctor uses this
/// same screen to add themself after registering the hospital.
class ManageDoctorsScreen extends ConsumerStatefulWidget {
  const ManageDoctorsScreen({super.key});

  @override
  ConsumerState<ManageDoctorsScreen> createState() => _ManageDoctorsScreenState();
}

class _ManageDoctorsScreenState extends ConsumerState<ManageDoctorsScreen> {
  List<DoctorSummary>? _docs; // null = still loading

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final docs = await ref.read(rosterRepositoryProvider).listDoctors();
    if (mounted) setState(() => _docs = docs);
  }

  Future<void> _addDoctorDialog() async {
    final name = TextEditingController();
    final councilReg = TextEditingController();
    final councilName = TextEditingController();
    final specialty = TextEditingController();
    final specialtyFocus = FocusNode();
    final hpr = TextEditingController();
    final phone = TextEditingController();
    final pin = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add doctor'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Doctor name'),
              ),
              TextField(
                controller: councilReg,
                decoration: const InputDecoration(
                    labelText: 'Medical council registration number'),
              ),
              TextField(
                controller: councilName,
                decoration: const InputDecoration(
                    labelText: 'Council name (e.g. NMC)'),
              ),
              // ID-4 specialty: searchable picker over the standard list —
              // type to filter, tap to select; free text stays allowed so an
              // unlisted sub-specialty never blocks adding a doctor.
              RawAutocomplete<String>(
                textEditingController: specialty,
                focusNode: specialtyFocus,
                optionsBuilder: (v) {
                  final q = v.text.trim().toLowerCase();
                  if (q.isEmpty) return kMedicalSpecialties;
                  return kMedicalSpecialties
                      .where((s) => s.toLowerCase().contains(q));
                },
                fieldViewBuilder: (ctx, ctrl, focus, _) => TextField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: const InputDecoration(
                    labelText: 'Specialty',
                    hintText: 'Type to search — e.g. Cardiology',
                  ),
                ),
                optionsViewBuilder: (ctx, onSelected, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxHeight: 220, maxWidth: 280),
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
                controller: hpr,
                decoration: const InputDecoration(
                    labelText: 'HPR ID (optional — verification never blocks)'),
              ),
              // D13: a doctor's own mobile lets them sign in directly (their
              // number → their PIN → their workspace, no shared hospital login).
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Doctor mobile (optional)',
                    prefixText: '+91 ',
                    helperText: 'Lets this doctor sign in directly with their own number'),
              ),
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(
                    labelText: 'Doctor PIN (4–6 digits)',
                    helperText: 'The doctor uses this to unlock their session'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final added = await ref.read(rosterRepositoryProvider).addDoctor(
            name: name.text,
            councilRegNumber: councilReg.text,
            councilName: councilName.text,
            specialty: specialty.text,
            hprId: hpr.text.trim().isEmpty ? null : hpr.text.trim(),
            pin: pin.text,
            phone: phone.text.trim().isEmpty ? null : '+91${phone.text.trim()}',
          );
      // Keep the in-session roster in sync so the picker sees the new doctor.
      ref.read(clinicSessionControllerProvider.notifier).doctorAdded(added);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${added.name} added')));
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add doctor: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Manage doctors',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _addDoctorDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Add doctor'),
          ),
          const SizedBox(height: 16),
          if (_docs == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_docs!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No doctors yet. Add your first doctor — for a solo '
                'practice, add yourself.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final d in _docs!)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.badge),
                  title: Text(d.name),
                  subtitle: Text(d.specialty),
                ),
              ),
        ],
      ),
    );
  }
}
