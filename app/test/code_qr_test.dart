import 'package:carebridge/shared/widgets/code_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('CodeQr renders a scannable QR for the given code',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: CodeQr(code: 'AB12CD')))));
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
