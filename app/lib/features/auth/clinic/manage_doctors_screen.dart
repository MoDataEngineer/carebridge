import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/constants/medical_specialties.dart';
import '../../../shared/widgets/brand_avatar.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import 'availability_screen.dart';
import 'branding_repository.dart';
import 'clinic_models.dart';
import 'clinic_sign_out_button.dart';
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
  ClinicBranding _branding = const ClinicBranding();

  String? get _clinicId =>
      ref.read(clinicSessionControllerProvider).active?.clinicId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    // Admin roster shows deactivated doctors too (so they can be restored);
    // the "Who are you?" picker still uses the active-only default elsewhere.
    final docs =
        await ref.read(rosterRepositoryProvider).listDoctors(includeInactive: true);
    if (mounted) setState(() => _docs = docs);
    final clinic = _clinicId;
    if (clinic == null) return;
    try {
      final b = await ref.read(brandingRepositoryProvider).current(clinic);
      if (mounted) setState(() => _branding = b);
    } catch (_) {/* branding is decorative — never block the roster */}
  }

  /// Pick an image and upload it as a doctor photo ([doctorId]) or, when null,
  /// the clinic logo (UI brief: doctor branding, uploadable).
  Future<void> _uploadImage({String? doctorId}) async {
    final clinic = _clinicId;
    if (clinic == null) return;
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
    if (picked == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last
          : 'png';
      final url = await ref.read(brandingRepositoryProvider).upload(
          clinicId: clinic, bytes: bytes, extension: ext, doctorId: doctorId);
      if (!mounted) return;
      setState(() => _branding = ClinicBranding(
            photos: doctorId == null
                ? _branding.photos
                : {..._branding.photos, doctorId: url},
            logoUrl: doctorId == null ? url : _branding.logoUrl,
          ));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(doctorId == null ? 'Clinic logo updated' : 'Photo updated')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  /// Shared add/edit form. [existing] non-null → edit mode (fields pre-filled,
  /// PIN optional = leave unchanged). Returns the entered values, or null if
  /// cancelled. Kept as one form so add and edit never drift apart.
  Future<_DoctorFormResult?> _doctorFormDialog({DoctorSummary? existing}) async {
    final isEdit = existing != null;
    final name = TextEditingController(text: existing?.name ?? '');
    final councilReg = TextEditingController(text: existing?.councilRegNumber ?? '');
    final councilName = TextEditingController(text: existing?.councilName ?? '');
    final specialty = TextEditingController(text: existing?.specialty ?? '');
    final specialtyFocus = FocusNode();
    final hpr = TextEditingController(text: existing?.hprId ?? '');
    // Phone is stored as +91XXXXXXXXXX; show just the local 10 digits (the '+91 '
    // prefix is added back on save).
    final phoneDigits = (existing?.phone ?? '').replaceAll(RegExp(r'\D'), '');
    final phone = TextEditingController(
        text: phoneDigits.length > 10
            ? phoneDigits.substring(phoneDigits.length - 10)
            : phoneDigits);
    final pin = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit doctor' : 'Add doctor'),
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
                decoration: InputDecoration(
                    labelText: isEdit
                        ? 'Reset PIN (leave blank to keep current)'
                        : 'Doctor PIN (4–6 digits)',
                    helperText: 'The doctor uses this to unlock their session'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isEdit ? 'Save' : 'Add')),
        ],
      ),
    );
    if (ok != true) return null;
    final localPhone = phone.text.trim();
    return _DoctorFormResult(
      name: name.text,
      councilRegNumber: councilReg.text,
      councilName: councilName.text,
      specialty: specialty.text,
      hprId: hpr.text.trim().isEmpty ? null : hpr.text.trim(),
      phone: localPhone.isEmpty ? null : '+91$localPhone',
      pin: pin.text.trim().isEmpty ? null : pin.text.trim(),
    );
  }

  Future<void> _addDoctorDialog() async {
    final r = await _doctorFormDialog();
    if (r == null) return;
    if (r.pin == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('A PIN is required when adding a doctor.')));
      }
      return;
    }
    try {
      final added = await ref.read(rosterRepositoryProvider).addDoctor(
            name: r.name,
            councilRegNumber: r.councilRegNumber,
            councilName: r.councilName,
            specialty: r.specialty,
            hprId: r.hprId,
            pin: r.pin!,
            phone: r.phone,
          );
      // Keep the in-session roster in sync so the picker sees the new doctor.
      ref.read(clinicSessionControllerProvider.notifier).doctorAdded(added);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${added.name} added — tap "Availability" to set consultation times')));
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add doctor: $e')));
      }
    }
  }

  Future<void> _editDoctorDialog(DoctorSummary doctor) async {
    final r = await _doctorFormDialog(existing: doctor);
    if (r == null) return;
    try {
      final updated = await ref.read(rosterRepositoryProvider).updateDoctor(
            doctorId: doctor.id,
            name: r.name,
            councilRegNumber: r.councilRegNumber,
            councilName: r.councilName,
            specialty: r.specialty,
            hprId: r.hprId,
            phone: r.phone,
            pin: r.pin,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${updated.name} updated')));
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update doctor: $e')));
      }
    }
  }

  /// Deactivate (soft delete) or restore a doctor. Deactivation is confirmed —
  /// it removes them from the picker/booking but preserves their visit history.
  Future<void> _toggleActive(DoctorSummary doctor) async {
    final deactivating = doctor.isActive;
    if (deactivating) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Deactivate ${doctor.name}?'),
          content: const Text(
              'They will no longer appear for booking or the "Who are you?" '
              'sign-in, but all their past visits and prescriptions are kept. '
              'You can restore them any time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deactivate')),
          ],
        ),
      );
      if (confirm != true) return;
    }
    try {
      await ref
          .read(rosterRepositoryProvider)
          .setDoctorActive(doctor.id, !doctor.isActive);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(deactivating
              ? '${doctor.name} deactivated'
              : '${doctor.name} restored')));
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update status: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: 'Manage doctors',
      showBack: false,
      actions: const [ClinicSignOutButton()],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _addDoctorDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Add doctor'),
          ),
          const SizedBox(height: 12),
          // Hospital branding: uploadable logo, shown to patients when booking.
          Card(
            child: ListTile(
              leading: BrandAvatar(
                  name: ref.watch(clinicSessionControllerProvider)
                          .login?.clinicName ?? 'Clinic',
                  imageUrl: _branding.logoUrl,
                  square: true),
              title: const Text('Hospital logo'),
              subtitle: const Text('Shown to patients when they book'),
              trailing: TextButton.icon(
                icon: const Icon(Icons.upload, size: 18),
                label: Text(_branding.logoUrl == null ? 'Upload' : 'Replace'),
                onPressed: () => _uploadImage(),
              ),
            ),
          ),
          const SizedBox(height: 4),
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
            for (final d in _docs!) _doctorCard(d),
        ],
      ),
    );
  }

  Widget _doctorCard(DoctorSummary d) {
    final inactive = !d.isActive;
    final subtitle = d.specialty.isEmpty
        ? 'Tap the avatar to add a photo'
        : '${d.specialty} · tap the avatar to add a photo';
    return Card(
      // Deactivated doctors read as muted so the roster shows status at a glance.
      color: inactive
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: Opacity(
        opacity: inactive ? 0.6 : 1,
        child: ListTile(
          // Doctor photo (uploadable; initials until one is set). Disabled while
          // deactivated — restore first to edit branding.
          leading: InkWell(
            customBorder: const CircleBorder(),
            onTap: inactive ? null : () => _uploadImage(doctorId: d.id),
            child: BrandAvatar(name: d.name, imageUrl: _branding.photos[d.id]),
          ),
          title: Row(
            children: [
              Flexible(child: Text(d.name)),
              if (inactive) ...[
                const SizedBox(width: 8),
                _pill(context, 'Deactivated'),
              ],
            ],
          ),
          subtitle: Text(inactive ? 'Not shown for booking or sign-in' : subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!inactive)
                IconButton(
                  tooltip: 'Availability',
                  icon: const Icon(Icons.schedule),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        AvailabilityScreen(doctorId: d.id, doctorName: d.name),
                  )),
                ),
              PopupMenuButton<String>(
                tooltip: 'Doctor options',
                onSelected: (v) {
                  if (v == 'edit') _editDoctorDialog(d);
                  if (v == 'toggle') _toggleActive(d);
                },
                itemBuilder: (_) => [
                  if (!inactive)
                    const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(inactive ? 'Restore doctor' : 'Deactivate'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onErrorContainer)),
    );
  }
}

/// Values captured by the shared add/edit doctor form.
class _DoctorFormResult {
  const _DoctorFormResult({
    required this.name,
    required this.councilRegNumber,
    required this.councilName,
    required this.specialty,
    required this.hprId,
    required this.phone,
    required this.pin,
  });
  final String name;
  final String councilRegNumber;
  final String councilName;
  final String specialty;
  final String? hprId;
  final String? phone;
  final String? pin;
}
