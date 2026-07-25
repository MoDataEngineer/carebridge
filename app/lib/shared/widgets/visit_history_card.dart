import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../features/patient/patient_models.dart';

/// One visit rendered as a polished record card — a dated mint chip, the
/// diagnosis as the headline, doctor notes, a bulleted prescription list, and a
/// follow-up line. Shared by the patient's read-only History tab and the
/// doctor/admin patient view so both read as one product.
class VisitHistoryCard extends StatelessWidget {
  const VisitHistoryCard({super.key, required this.visit});

  final VisitRecord visit;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _fmt(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadii.rCard,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.tintMint,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event, size: 14, color: AppColors.brand700),
                const SizedBox(width: 6),
                Text(_fmt(visit.visitDate),
                    style: text.labelMedium?.copyWith(
                        color: AppColors.brand700, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(visit.diagnosis?.isNotEmpty == true ? visit.diagnosis! : 'Visit',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (visit.notes != null && visit.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(visit.notes!,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (visit.prescriptions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('PRESCRIBED',
                style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            for (final p in visit.prescriptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.brand400,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${p.drugName}'
                        '${p.dosage != null ? ' ${p.dosage}' : ''}'
                        ' — ${p.scheduleLabel}'
                        '${p.durationDays != null ? ' · ${p.durationDays}d' : ''}',
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (visit.followUpDate != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(Icons.history, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Follow-up advised · ${_fmt(visit.followUpDate!)}',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
