import 'package:carebridge/core/routing/app_router.dart';
import 'package:carebridge/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 1 smoke test: the three-button entry screen renders and each role
/// button routes to its placeholder auth screen. (Deeper session-scoping tests —
/// solo auto-skip, doctor isolation, admin inherited visibility — are written in
/// Phases 2 and 5 where that logic exists.)
void main() {
  // Fresh router per call so navigation state never leaks between tests.
  Widget harness() => ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: createAppRouter(),
        ),
      );

  testWidgets('entry screen shows exactly the three role buttons', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('Diagnostic Partner'), findsOneWidget);
    // There is no literal "Clinic" button (Section 2).
    expect(find.text('Clinic'), findsNothing);
  });

  testWidgets('Doctor button routes to clinic login (not a doctor login)', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();

    expect(find.text('Clinic sign in'), findsOneWidget);
  });

  testWidgets('Patient and Diagnostic buttons route to their auth screens', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();
    expect(find.text('Patient sign in'), findsOneWidget);

    // back to entry
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Diagnostic Partner'));
    await tester.pumpAndSettle();
    expect(find.text('Diagnostic partner sign in'), findsOneWidget);
  });
}
