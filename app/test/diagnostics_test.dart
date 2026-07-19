import 'dart:typed_data';

import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/diagnostics/diagnostic_portal_screen.dart';
import 'package:carebridge/features/diagnostics/diagnostics_models.dart';
import 'package:carebridge/features/diagnostics/diagnostics_repository.dart';
import 'package:carebridge/features/diagnostics/test_orders_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 6 diagnostics UI tests with a fake repository (no network). The fake
/// stands in for the Flow C SECURITY DEFINER functions, so the widget tests
/// assert the user-visible behaviour:
///   - a patient/doctor Tests view renders orders + an uploaded structured report;
///   - a doctor-scoped Tests view can order a test and is shown the order code;
///   - the partner portal lists its queue, and uploading closes the order.
class _FakeDiagnosticsRepo implements DiagnosticsRepository {
  _FakeDiagnosticsRepo();

  final List<TestOrderView> patientOrders = [
    const TestOrderView(
      id: 'o1',
      testType: 'pathology',
      testName: 'CBC',
      status: 'report_ready',
      reports: [
        TestReportView(reportType: 'structured', structuredValues: {'Hb': 13.5}),
      ],
    ),
  ];

  final List<PartnerQueueItem> queue = [
    const PartnerQueueItem(
      orderId: 'o2',
      patientName: 'Asha Rao',
      testType: 'imaging',
      testName: 'Chest X-Ray',
      status: 'ordered',
      hasReport: false,
    ),
  ];

  String? orderedFor;
  String? uploadedOrder;

  @override
  Future<String> orderTest({
    required String patientId,
    required String testType,
    required String testName,
    String? partnerId,
  }) async {
    orderedFor = patientId;
    return 'ORDERCODE123';
  }

  @override
  Future<List<TestOrderView>> ordersForPatient(String? patientId) async =>
      List.of(patientOrders);

  @override
  Future<ClaimedOrder> claimOrder(String code) async => const ClaimedOrder(
        orderId: 'o2',
        patientName: 'Asha Rao',
        testType: 'imaging',
        testName: 'Chest X-Ray',
        doctorName: 'Dr Rao',
        clinicName: 'City Clinic',
        status: 'ordered',
      );

  @override
  Future<List<PartnerQueueItem>> partnerQueue() async => List.of(queue);

  @override
  Future<void> updateStatus(String orderId, String status) async {}

  @override
  Future<void> uploadReport({
    required String orderId,
    required String reportType,
    String? fileUrl,
    Map<String, dynamic>? structuredValues,
  }) async {
    uploadedOrder = orderId;
    // Simulate the grant closing: the order leaves the partner's actionable set.
    queue.removeWhere((q) => q.orderId == orderId);
  }

  @override
  Future<String> uploadReportFile({
    required String orderId,
    required String filename,
    required Uint8List bytes,
  }) async =>
      '$orderId/$filename';

  @override
  Future<String> signedUrl(String path) async => 'https://signed.example/$path';
}

Widget _harness(_FakeDiagnosticsRepo repo, Widget child) => ProviderScope(
      overrides: [diagnosticsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light, home: child),
    );

void main() {
  testWidgets('Tests view renders an order and its structured report', (tester) async {
    await tester.pumpWidget(_harness(_FakeDiagnosticsRepo(), const TestOrdersView()));
    await tester.pumpAndSettle();

    expect(find.textContaining('CBC'), findsOneWidget);
    expect(find.text('Report ready'), findsOneWidget);
    // VitalTile uppercases the measurement label (medical-data hierarchy).
    expect(find.text('HB'), findsOneWidget);
    expect(find.text('13.5'), findsOneWidget);
    // No order action without canOrder.
    expect(find.text('Order test'), findsNothing);
  });

  testWidgets('doctor-scoped Tests view orders a test and shows the code', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeDiagnosticsRepo();
    await tester.pumpWidget(
        _harness(repo, const TestOrdersView(patientId: 'p1', canOrder: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Order test'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Test type'), 'pathology');
    await tester.enterText(find.widgetWithText(TextField, 'Test name'), 'LFT');
    await tester.tap(find.text('Create order'));
    await tester.pumpAndSettle();

    expect(repo.orderedFor, 'p1');
    expect(find.text('ORDERCODE123'), findsOneWidget); // code shown to share
  });

  testWidgets('partner portal uploads a result and closes the order', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeDiagnosticsRepo();
    await tester.pumpWidget(_harness(repo, const DiagnosticPortalScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Chest X-Ray · imaging'), findsOneWidget);
    expect(find.text('Asha Rao'), findsOneWidget);

    await tester.tap(find.text('Upload result'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Measure (e.g. Hb)'), 'Finding');
    await tester.enterText(find.widgetWithText(TextField, 'Value'), 'Normal');
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(repo.uploadedOrder, 'o2');
    // Order left the queue once the report closed the grant.
    expect(find.text('Chest X-Ray · imaging'), findsNothing);
  });
}
