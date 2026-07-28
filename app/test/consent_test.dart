import 'package:carebridge/core/theme/app_theme.dart';
import 'package:carebridge/features/consent/consent_models.dart';
import 'package:carebridge/features/consent/consent_repository.dart';
import 'package:carebridge/features/consent/privacy_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 5 patient consent UI tests with a fake repository (no network):
///  - "Doctors with access" lists grants and one-tap revoke removes one;
///  - a pending Flow B request can be approved and then disappears;
///  - generating a consent code surfaces it to show in person.
class _FakeConsentRepo implements ConsentRepository {
  final List<GrantView> grants = [
    GrantView(
      grantId: 'g1',
      doctorId: 'd1',
      doctorName: 'Dr Rao',
      clinicName: 'City Clinic',
      type: 'standing',
      grantedAt: DateTime(2026, 2, 1),
    ),
  ];
  final List<AccessRequestView> requests = [
    const AccessRequestView(grantId: 'r1', doctorName: 'Dr New', clinicName: 'Med Center'),
  ];

  String? respondedGrant;
  bool? respondedApprove;
  String? revoked;

  // P13 wearable sharing: doctorId → wearable-grant-id.
  final Map<String, String> shares = {};
  String? sharedWith;
  String? revokedWearable;

  @override
  Future<List<GrantView>> doctorsWithAccess() async => List.of(grants);

  @override
  Future<Map<String, String>> wearableShares() async => Map.of(shares);

  @override
  Future<void> shareWearables(String doctorId) async {
    sharedWith = doctorId;
    shares[doctorId] = 'w-$doctorId';
  }

  @override
  Future<void> revokeWearable(String grantId) async {
    revokedWearable = grantId;
    shares.removeWhere((_, v) => v == grantId);
  }

  @override
  Future<void> revokeGrant(String grantId) async {
    revoked = grantId;
    grants.removeWhere((g) => g.grantId == grantId);
  }

  @override
  Future<List<AccessRequestView>> pendingRequests() async => List.of(requests);

  @override
  Future<void> respondRequest(String grantId, bool approve) async {
    respondedGrant = grantId;
    respondedApprove = approve;
    requests.removeWhere((r) => r.grantId == grantId);
  }

  @override
  Future<List<AccessLogView>> whoViewed() async => [
        AccessLogView(
          accessorType: 'doctor',
          accessorLabel: 'Dr Rao',
          viewedAt: DateTime(2026, 2, 2, 9, 30),
          whatViewed: 'consent granted (Flow A in-person)',
        ),
      ];

  @override
  Future<ConsentCode> createConsentCode() async =>
      ConsentCode(code: 'abc123def456', expiresAt: DateTime(2026, 2, 2, 10, 0));
}

Widget _harness(_FakeConsentRepo repo) => ProviderScope(
      overrides: [consentRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: PrivacyTab()),
      ),
    );

void main() {
  testWidgets('lists doctors with access and revokes one', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeConsentRepo();
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dr Rao · City Clinic'), findsOneWidget);

    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();

    expect(repo.revoked, 'g1');
    expect(find.textContaining('Dr Rao · City Clinic'), findsNothing);
    expect(find.text('No doctor currently has access.'), findsOneWidget);
  });

  testWidgets('approves a pending Flow B request', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeConsentRepo();
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dr New · Med Center'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(repo.respondedGrant, 'r1');
    expect(repo.respondedApprove, true);
    expect(find.text('No pending access requests.'), findsOneWidget);
  });

  testWidgets('generates a consent code to share', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness(_FakeConsentRepo()));
    await tester.pumpAndSettle();

    expect(find.text('abc123def456'), findsNothing);
    await tester.tap(find.text('Generate consent code'));
    await tester.pumpAndSettle();
    expect(find.text('abc123def456'), findsOneWidget);
  });

  // P13 trust: sharing vitals is patient-initiated (off by default) and creates
  // a SEPARATE wearable grant — never implied by the clinical grant.
  testWidgets('vitals sharing is off by default and toggling creates a share',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeConsentRepo();
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    // A clinical grant exists, but vitals are NOT shared until toggled.
    final toggle = find.byType(SwitchListTile);
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(repo.sharedWith, isNull);

    await tester.tap(find.text('Share my vitals'));
    await tester.pumpAndSettle();

    expect(repo.sharedWith, 'd1'); // wearable grant created for that doctor
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });
}
