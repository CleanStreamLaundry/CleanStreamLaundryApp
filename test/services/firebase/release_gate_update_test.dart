import 'dart:async';

import 'package:clean_stream_laundry_app/features/release_controls/release_gate.dart';
import 'package:clean_stream_laundry_app/logic/models/release_policy.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'firebase_service_test.dart' show Driver, Tokens, policyJson;

class UpdateLauncher extends UrlLauncherPlatform {
  bool throwsOnFailure = false;
  Completer<bool>? pending;
  final urls = <String>[];
  final modes = <PreferredLaunchMode>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    modes.add(options.mode);
    if (pending != null) return pending!.future;
    if (throwsOnFailure) throw StateError('Fixture store unavailable');
    return false;
  }
}

void main() {
  const error = 'Could not open the app store. Please try again.';
  const store = 'https://play.google.com/store/apps/details?id='
      'com.cleanstreamlaundrysolutions.clean_stream_laundry_app';
  late FirebaseService service;
  late UpdateLauncher launcher;
  late UrlLauncherPlatform originalLauncher;

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
    originalLauncher = UrlLauncherPlatform.instance;
    launcher = UpdateLauncher();
    UrlLauncherPlatform.instance = launcher;
  });
  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
    service.dispose();
  });

  for (final requiredUpdate in [false, true]) {
    for (final throwsOnFailure in [false, true]) {
      testWidgets(
        '${requiredUpdate ? 'required' : 'recommended'} update shows '
        '${throwsOnFailure ? 'thrown' : 'false'} launch failure and clears on retry',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var browseTaps = 0;
          launcher.throwsOnFailure = throwsOnFailure;
          service.policy = ReleasePolicy.parse(
            policyJson(blocked: requiredUpdate ? [10] : [], url: store),
            'android',
          );
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: ReleaseGate(
                service: service,
                child: Scaffold(body: Center(child: TextButton(
                  onPressed: () => browseTaps++,
                  child: const Text('Browse'),
                ))),
              ),
            ),
          ));
          final update = requiredUpdate
              ? find.text('Open App Store')
              : find.byTooltip('Update');
          expect(find.text(error), findsNothing);
          await tester.tap(update);
          await tester.pumpAndSettle();
          expect(launcher.urls, [store]);
          expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
          expect(find.text(error), findsOneWidget);
          await tester.ensureVisible(find.text(error));
          await tester.pumpAndSettle();
          expect(find.text(error).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);

          launcher.pending = Completer<bool>();
          await tester.ensureVisible(update);
          await tester.tap(update);
          await tester.pump();
          expect(find.text(error), findsNothing);
          launcher.pending!.complete(true);
          await tester.pumpAndSettle();
          expect(find.text(error), findsNothing);
          expect(launcher.urls, [store, store]);
          expect(service.analyticsEnabled, isFalse);
          expect(service.pushEnabled, isFalse);

          if (requiredUpdate) {
            expect(find.text('Update required'), findsOneWidget);
            expect(find.text('Browse').hitTestable(), findsNothing);
          } else {
            await tester.tap(find.text('Browse'));
            expect(browseTaps, 1);
            await tester.tap(find.byTooltip('Dismiss'));
            await tester.pumpAndSettle();
            expect(find.text('An update is available'), findsNothing);
            expect(find.text('Browse').hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('unset store URL does not offer or invoke an update launcher', (tester) async {
    service.policy = ReleasePolicy.parse(policyJson(), 'android');
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: ReleaseGate(
        service: service,
        child: const Scaffold(body: Text('Browse')),
      ),
    ));
    expect(find.text('An update is available'), findsOneWidget);
    expect(find.byTooltip('Update'), findsNothing);
    expect(launcher.urls, isEmpty);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Browse'), findsOneWidget);
  });
}
