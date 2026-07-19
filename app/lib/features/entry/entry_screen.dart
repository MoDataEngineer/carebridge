import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/breakpoints.dart';
import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/ayulekha_logo.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/role_button.dart';
import '../../shared/widgets/theme_toggle_button.dart';

/// THE entry screen (Section 2): three role choices, nothing else.
/// Founder decision 2026-07-04: the clinic entry is labelled "Hospital"
/// (2026-07-07: "Hospital / Doctor" — doctors can sign in with their own
/// mobile). Diagnostic Partner stays flat.
/// Reskin 2026-07-19 (mint/teal direction): painted logo mark, tagline, and
/// three soft-tinted role cards — same three destinations, same labels.
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = !Breakpoints.isMobile(context);
    return Scaffold(
      body: Stack(
        children: [
          const Align(
            alignment: Alignment.topRight,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: ThemeToggleButton(),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: FadeSlideIn(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: AyulekhaLogo(size: wide ? 88 : 72)),
                        const SizedBox(height: AppSpacing.xl),
                        Text('Ayulekha',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5)),
                        const SizedBox(height: AppSpacing.sm),
                        Text('Your health record, with your consent.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                        const SizedBox(height: AppSpacing.xxl),
                        RoleButton(
                          label: 'Patient',
                          caption: 'Book visits, view records & reports',
                          icon: Icons.person_outline,
                          tint: AppColors.tintMint,
                          tintDark: AppColors.tintMintDark,
                          onTap: () => context.push(Routes.patientAuth),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        RoleButton(
                          label: 'Hospital / Doctor',
                          caption: 'Queue, visits, prescriptions & roster',
                          icon: Icons.local_hospital_outlined,
                          tint: AppColors.tintSky,
                          tintDark: AppColors.tintSkyDark,
                          onTap: () => context.push(Routes.clinicLogin),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        RoleButton(
                          label: 'Diagnostic Partner',
                          caption: 'Receive orders & upload reports',
                          icon: Icons.biotech_outlined,
                          tint: AppColors.tintPeach,
                          tintDark: AppColors.tintPeachDark,
                          onTap: () => context.push(Routes.diagnosticLogin),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
