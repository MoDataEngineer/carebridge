import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/shared/widgets/brand_avatar.dart';
import 'package:carebridge/shared/widgets/vital_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('BrandAvatar falls back to initials when no image is set',
      (tester) async {
    await tester.pumpWidget(_wrap(const BrandAvatar(name: 'Dr Priya Sharma')));
    // "Dr" prefix stripped -> Priya Sharma -> PS.
    expect(find.text('PS'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('VitalTile shows value + unit and flags out-of-range with an icon',
      (tester) async {
    await tester.pumpWidget(_wrap(const VitalTile(
      label: 'HbA1c',
      value: '7.2',
      unit: '%',
      reference: '4.0-5.6',
      flagged: true,
    )));
    expect(find.text('HBA1C'), findsOneWidget); // label uppercased
    expect(find.text('7.2'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
    // Flag is not colour-only — an icon accompanies it (a11y §5).
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
