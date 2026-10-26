import 'package:clean_stream_laundry_app/features/release_controls/firebase_settings.dart';
import 'package:clean_stream_laundry_app/features/release_controls/release_gate.dart';
import 'package:clean_stream_laundry_app/logic/models/release_policy.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service_test.dart' show Tokens, policyJson;
import 'push_cleanup_retry_test.dart' show CleanupDriver;

void main() {
  late FirebaseService service;
  late CleanupDriver driver;
  late Tokens tokens;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    driver = CleanupDriver();
    tokens = Tokens();
    service = FirebaseService(
      driver: driver,
      tokens: tokens,
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
  tearDown(() async {
    service.dispose();
    await driver.refreshes.close();
    await driver.opens.close();
    await driver.foreground.close();
  });
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
  testWidgets('no analytics toggle; messages remain an independent choice', (
    tester,
  ) async {
    await tester.runAsync(service.start);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FirebaseSettings(service: service)),
      ),
    );
    expect(find.text('Usage analytics'), findsNothing);
    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(service.analyticsEnabled, isTrue);
    await tester.tap(find.text('In-app messages'));
    await tester.pumpAndSettle();
    expect(service.messagesEnabled, isTrue);
    await tester.tap(find.text('In-app messages'));
    await tester.pumpAndSettle();
    expect(service.analyticsEnabled, isTrue);
    expect(service.messagesEnabled, isFalse);
  });
  testWidgets(
    'debug cleanup categories fit narrow settings and clear through Retry',
    (tester) async {
      const warning =
          'Push cleanup pending. Reconnect and retry before enabling push.';
      const categories =
          'Push server cleanup failed.\nPush SDK cleanup failed.';
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      driver.tokenError = StateError('private-token-detail');
      tokens.failRevoke = true;
      await tester.runAsync(service.start);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: FirebaseSettings(service: service),
            ),
          ),
        ),
      );
      expect(find.text(warning), findsOneWidget);
      expect(find.text(categories), findsOneWidget);
      expect(find.textContaining('private-token-detail'), findsNothing);
      expect(find.textContaining('offline'), findsNothing);
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, warning),
      );
      expect((tile.subtitle! as Text).data, categories);
      final titleRect = tester.getRect(find.text(warning));
      final subtitleRect = tester.getRect(find.text(categories));
      expect(titleRect.bottom, lessThanOrEqualTo(subtitleRect.top));
      expect(subtitleRect.left, greaterThanOrEqualTo(0));
      expect(subtitleRect.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
      driver.tokenError = null;
      tokens.failRevoke = false;
      await tester.ensureVisible(find.byTooltip('Retry'));
      await tester.longPress(find.byTooltip('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Retry'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(service.problem, isNull);
      expect(service.pushCleanupDiagnostic, isNull);
      expect(find.text(warning), findsNothing);
      expect(find.text(categories), findsNothing);
      expect(find.byTooltip('Retry'), findsNothing);
      expect(tokens.revocations, 2);
      expect(driver.calls.where((call) => call == 'delete'), hasLength(2));
      expect(service.pushEnabled, isFalse);
      expect(tokens.owners, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
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
    await tester.runAsync(() => service.setMessages(true));
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
    expect(find.text('Usage analytics'), findsNothing);
    await tester.ensureVisible(find.text('In-app messages'));
    await tester.tap(find.text('In-app messages'));
    await tester.pumpAndSettle();
    expect(service.analyticsEnabled, isTrue);
    expect(service.messagesEnabled, isFalse);
    expect(find.text('Update required'), findsOneWidget);
  });
}
