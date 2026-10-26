@TestOn('vm')
@Tags(['firebase-configured'])
library;

import 'dart:async';
import 'dart:io';

import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/features/home/home.dart';
import 'package:clean_stream_laundry_app/features/login/login.dart';
import 'package:clean_stream_laundry_app/features/settings/settings.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_bootstrap.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_configuration.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/admission/mocks.dart';
import '../../features/loading/mocks.dart' show MockAppLinks;
import '../notifications/notification_service_test.dart'
    show MockPlugin, MockAndroidPlugin, FakeInit, FakeChannel;
import 'firebase_service_test.dart' show Driver, Tokens;

class InitialNotificationDriver extends Driver {
  Map<String, dynamic>? initial;

  @override
  Future<Map<String, dynamic>?> initialMessage() async => initial;
}

// Same explicit asset-bundle pattern as the newsletter fixture. No env asset
// or manifest is loaded; a separate read-only artwork root avoids cache copies.
class NotificationAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    }
    if (!const ['assets/splash-logo.png', 'assets/Google.png'].contains(key)) {
      throw StateError('Unexpected notification fixture asset: $key');
    }
    final root = Platform.environment['NOTIFICATION_TEST_ASSET_ROOT'] ?? '.';
    return ByteData.sublistView(File('$root/$key').readAsBytesSync());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(FakeInit());
    registerFallbackValue(FakeChannel());
  });

  for (final local in [false, true]) {
    for (final cold in [false, true]) {
      for (final destination in ['home', 'settings']) {
        testWidgets('signed-out ${local ? 'local' : 'FCM'} '
            '${cold ? 'cold' : 'warm'} $destination uses real login gate', (tester) async {
          final previousPlatform = debugDefaultTargetPlatformOverride;
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          // Synthetic build defines enable callback wiring only. Never start
          // the bootstrap's real SDK driver or contact a Firebase project.
          expect(FirebaseConfiguration.fromBuild(), isNotNull);
          SharedPreferences.setMockInitialValues({});
          PackageInfo.setMockInitialValues(
            appName: 'Fixture', packageName: 'fixture', version: '1.0.0',
            buildNumber: '1', buildSignature: '',
          );
          final auth = MockAdmissionAuthService();
          final profiles = MockAdmissionProfileService();
          final events = StreamController<AuthState>.broadcast();
          final links = MockAppLinks();
          when(() => auth.currentSession).thenReturn(null);
          when(() => auth.getCurrentUserId).thenReturn(null);
          when(() => auth.authStateChanges).thenAnswer((_) => events.stream);
          when(() => auth.onAuthChange).thenAnswer((_) => const Stream.empty());
          when(() => auth.isLoggedIn()).thenAnswer((_) async => AuthenticationResponses.failure);
          when(() => links.getInitialLink()).thenAnswer((_) async => null);
          GetIt.I.registerSingleton<AuthService>(auth);
          GetIt.I.registerSingleton<ProfileService>(profiles);

          final plugin = MockPlugin();
          final android = MockAndroidPlugin();
          void Function(NotificationResponse)? opened;
          final launch = Completer<NotificationAppLaunchDetails?>();
          when(() => plugin.initialize(settings: any(named: 'settings'),
            onDidReceiveNotificationResponse: any(named: 'onDidReceiveNotificationResponse'),
          )).thenAnswer((invocation) async {
            opened = invocation.namedArguments[#onDidReceiveNotificationResponse]
                as void Function(NotificationResponse)?;
            return true;
          });
          when(() => plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>())
              .thenReturn(android);
          when(() => android.createNotificationChannel(any())).thenAnswer((_) async {});
          when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer((_) => launch.future);
          GetIt.I.registerSingleton<FlutterLocalNotificationsPlugin>(plugin);

          final admission = AdmissionController(authService: auth, profileService: profiles);
          var admissionSignals = 0;
          admission.addListener(() => admissionSignals++);
          final router = RouterService().createRouter(auth,
            appLinks: links, admission: admission, profiles: profiles);
          NotificationService? notifications;
          final bootstrap = await FirebaseBootstrap.create(
            auth: auth, admission: admission, router: router,
            supabaseUrl: 'https://offline.invalid', publicKey: 'synthetic-public-key',
            notifications: () => notifications ??= NotificationService(),
          );
          final driver = InitialNotificationDriver();
          final tokens = Tokens();
          final delivery = FirebaseService(
            driver: driver, tokens: tokens,
            preferences: await SharedPreferences.getInstance(),
            environment: 'dev', platform: 'android', version: '1.0.0', build: '1',
            navigate: bootstrap.service.navigate,
            showNotification: (_) async {}, diagnostic: (_) {},
          );
          final paths = <String>[];
          router.routerDelegate.addListener(() {
            paths.add(router.routerDelegate.currentConfiguration.uri.path);
          });
          Future<void> mount() => tester.pumpWidget(DefaultAssetBundle(
            bundle: NotificationAssets(),
            child: MaterialApp.router(routerConfig: router,
              theme: ThemeData(splashFactory: NoSplash.splashFactory)),
          ));
          try {
            if (!cold) {
              await mount();
              await tester.pumpAndSettle();
              expect(find.byType(Login), findsOneWidget);
            }
            final signalsBefore = admissionSignals;
            final payload = destination == 'home' ? '/homePage' : '/settings';
            final response = NotificationResponse(
              notificationResponseType: NotificationResponseType.selectedNotification,
              payload: payload,
            );
            launch.complete(local && cold
                ? NotificationAppLaunchDetails(true, notificationResponse: response)
                : null);
            await notifications!.initialized;
            if (local) {
              if (!cold) opened!(response);
            } else {
              driver.initial = cold ? {'destination': destination} : null;
              await delivery.start();
              if (!cold) driver.opens.add({'destination': destination});
            }
            if (cold) await mount();
            await tester.pumpAndSettle();
            expect(admissionSignals, greaterThan(signalsBefore),
                reason: 'Delivery must actually pass through bootstrap admission');
            expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
            expect(find.byType(Login), findsOneWidget);
            expect(find.byType(HomePage), findsNothing);
            expect(find.byType(Settings), findsNothing);
            expect(paths, isNot(contains(payload)));
            verifyNever(() => profiles.getAdmissionStatus());
            expect(tokens.owners, isEmpty);
            expect(driver.calls, isNot(contains('permission:true')));
            expect(bootstrap.service.pushEnabled, isFalse);
            expect(bootstrap.service.analyticsEnabled, isFalse);
            expect(bootstrap.service.messagesEnabled, isFalse);
            expect(tester.takeException(), isNull);
          } finally {
            debugDefaultTargetPlatformOverride = previousPlatform;
            await tester.pumpWidget(const SizedBox());
            delivery.dispose();
            bootstrap.dispose();
            admission.dispose();
            router.dispose();
            await driver.refreshes.close();
            await driver.opens.close();
            await driver.foreground.close();
            await events.close();
            await GetIt.I.reset();
          }
        });
      }
    }
  }
}
