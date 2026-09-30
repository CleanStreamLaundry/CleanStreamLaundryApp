import 'package:clean_stream_laundry_app/features/release_controls/firebase_settings.dart';
import 'package:clean_stream_laundry_app/features/release_controls/release_gate.dart';
import 'package:clean_stream_laundry_app/logic/models/release_policy.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service_test.dart' show Driver, Tokens, policyJson;

void main() {
  late FirebaseService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = FirebaseService(
      driver: Driver(),
      tokens: Tokens(),
      preferences: await SharedPreferences.getInstance(),
      environment: 'dev',
      platform: 'android',
      version: '1.0.0',
      build: '10',
      navigate: (_) async {},
      showNotification: (_) async {},
      diagnostic: (_) {},
    );
  });
  tearDown(() => service.dispose());
  testWidgets(
    'consent defaults unchecked and unavailable switches cannot opt in',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FirebaseSettings(service: service)),
        ),
      );
      for (final tile in tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      )) {
        expect(tile.value, isFalse);
        expect(tile.onChanged, isNull);
      }
    },
  );
  testWidgets('settings explicitly enable analytics, FIAM then revoke both', (
    tester,
  ) async {
    await tester.runAsync(service.start);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FirebaseSettings(service: service)),
      ),
    );
    await tester.tap(find.text('Usage analytics'));
    await tester.pumpAndSettle();
    expect(service.analyticsEnabled, isTrue);
    await tester.tap(find.text('In-app messages'));
    await tester.pumpAndSettle();
    expect(service.messagesEnabled, isTrue);
    await tester.tap(find.text('Usage analytics'));
    await tester.pumpAndSettle();
    expect(service.analyticsEnabled, isFalse);
    expect(service.messagesEnabled, isFalse);
  });
  for (final width in [320.0, 800.0]) {
    testWidgets(
      'known block is visible and blocks underlying input at width $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var taps = 0;
        service.policy = ReleasePolicy.parse(
          policyJson(blocked: [10]),
          'android',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ReleaseGate(
              service: service,
              child: Scaffold(
                body: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Spend'),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Update required'), findsOneWidget);
        await tester.tap(find.text('Spend'), warnIfMissed: false);
        await tester.pump();
        expect(taps, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('recommended update can be dismissed without blocking browsing', (
    tester,
  ) async {
    service.policy = ReleasePolicy.parse(policyJson(), 'android');
    await tester.pumpWidget(
      MaterialApp(
        home: ReleaseGate(
          service: service,
          child: const Scaffold(body: Text('Browse')),
        ),
      ),
    );
    expect(find.text('An update is available'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('An update is available'), findsNothing);
    expect(find.text('Browse'), findsOneWidget);
  });
  testWidgets('required update still permits consent revocation', (
    tester,
  ) async {
    await tester.runAsync(service.start);
    await tester.runAsync(() => service.setAnalytics(true));
    service.policy = ReleasePolicy.parse(policyJson(blocked: [10]), 'android');
    await tester.pumpWidget(
      MaterialApp(
        home: ReleaseGate(
          service: service,
          child: const Scaffold(body: Text('Browse')),
        ),
      ),
    );
    await tester.tap(find.text('Privacy and notifications'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Usage analytics'));
    await tester.tap(find.text('Usage analytics'));
    await tester.pumpAndSettle();
    expect(service.analyticsEnabled, isFalse);
    expect(find.text('Update required'), findsOneWidget);
  });
}
