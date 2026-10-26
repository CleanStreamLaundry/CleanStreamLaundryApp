import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/logic/models/release_policy.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_bootstrap.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_service_test.dart' show Driver, Tokens, policyJson, drain;
import '../../features/admission/mocks.dart';

class FailingSuppressionDriver extends Driver {
  bool failSuppression = false;
  @override
  Future<void> inAppMessaging(bool enabled) async {
    if (!enabled && failSuppression) throw StateError('FIAM unavailable');
    await super.inAppMessaging(enabled);
  }
}

String bearer(String session) =>
    'Bearer header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'A', 'session_id': session})))}.signature';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late FailingSuppressionDriver driver;
  late Tokens tokens;
  late FirebaseService service;
  FirebaseService make({
    String environment = 'dev',
    String platform = 'android',
    FirebaseDriver? adapter,
  }) => FirebaseService(
    driver: adapter ?? driver,
    tokens: tokens,
    preferences: prefs,
    environment: environment,
    platform: platform,
    version: '1.0.0',
    build: '10',
    navigate: (_) async {},
    showNotification: (_) async {},
    diagnostic: (_) {},
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    driver = FailingSuppressionDriver();
    tokens = Tokens();
    service = make();
  });
  tearDown(() => service.dispose());

  test(
    'REGRESSION: FIAM failure must not prevent Analytics consent revocation',
    () async {
      await service.start();
      await service.setMessages(true);
      driver.calls.clear();
      driver.failSuppression = true;
      await service.deletionChanged('subject:request');
      expect(service.analyticsEnabled, isFalse);
      expect(service.messagesEnabled, isFalse);
      expect(prefs.getBool('firebase.dev.consent.analytics'), isNull);
      expect(
        driver.calls,
        contains('analytics:false'),
        reason:
            'An unrelated FIAM failure leaves native Analytics collection enabled despite revocation.',
      );
    },
  );

  test(
    'REGRESSION: same-user new session invalidates pending token acquisition',
    () async {
      await service.start();
      await service.accountChanged(PushAccount('A', bearer('session-1')));
      driver.delayedToken = Completer<String?>();
      final enable = service.setPush(true);
      await drain();
      await service.accountChanged(
        PushAccount('A', bearer('session-2')),
        admitted: false,
      );
      await service.accountChanged(PushAccount('A', bearer('session-2')));
      driver.delayedToken!.complete('old-session-token');
      await enable;
      expect(
        tokens.owners,
        isEmpty,
        reason:
            'A completed admission check for a new session must not revive the old session opt-in.',
      );
    },
  );

  test(
    'explicit push revoke during token acquisition prevents binding',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'Bearer A'));
      driver.delayedToken = Completer<String?>();
      final enable = service.setPush(true);
      await drain();
      final revoke = service.disablePush();
      driver.delayedToken!.complete('old-token');
      await Future.wait([enable, revoke]);
      expect(tokens.owners, isEmpty);
      expect(service.pushEnabled, isFalse);
    },
  );

  test(
    'soft admission pause without re-admission prevents an in-flight bind',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'Bearer A'));
      driver.delayedToken = Completer<String?>();
      final enable = service.setPush(true);
      await drain();
      await service.accountChanged(
        const PushAccount('A', 'Bearer A'),
        admitted: false,
      );
      driver.delayedToken!.complete('token');
      await enable;
      expect(tokens.owners, isEmpty);
    },
  );

  test(
    'native initialization failure retains a cached mandatory block',
    () async {
      await prefs.setString(
        'firebase.dev.android.release.v1',
        policyJson(blocked: [10]),
      );
      driver.failInitialize = true;
      await service.start();
      expect(service.available, isFalse);
      expect(service.decision, ReleaseDecision.blocked);
    },
  );

  for (final scope in [('prod', 'android'), ('dev', 'ios')]) {
    test(
      'release policy and installation consent do not cross $scope',
      () async {
        await prefs.setBool('firebase.dev.consent.messages', true);
        await prefs.setString(
          'firebase.dev.android.release.v1',
          policyJson(blocked: [10]),
        );
        driver.offline = true;
        final scoped = make(environment: scope.$1, platform: scope.$2);
        addTearDown(scoped.dispose);
        await scoped.start();
        expect(scoped.decision, ReleaseDecision.allowed);
        expect(scoped.analyticsEnabled, isTrue);
        if (scope.$1 == 'prod') expect(scoped.messagesEnabled, isFalse);
      },
    );
  }

  test(
    'malformed store-link policy cannot clear known cached maintenance',
    () async {
      await prefs.setString(
        'firebase.dev.android.release.v1',
        policyJson(maintenance: true),
      );
      driver.raw = policyJson(
        url: 'https://play.google.com.evil.invalid/store/apps/details',
      );
      await service.start();
      await service.refreshReleasePolicy();
      expect(service.decision, ReleaseDecision.maintenance);
    },
  );

  for (final event in [AuthChangeEvent.signedIn, AuthChangeEvent.signedOut]) {
    test(
      'bootstrap clears prior opt-in on $event during an admission check',
      () async {
        PackageInfo.setMockInitialValues(
          appName: 'QA',
          packageName: 'qa',
          version: '1.0.0',
          buildNumber: '10',
          buildSignature: '',
        );
        final auth = MockAdmissionAuthService();
        final profiles = MockAdmissionProfileService();
        final events = StreamController<AuthState>.broadcast();
        Session? current = admissionSession(
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
        when(() => auth.currentSession).thenAnswer((_) => current);
        when(() => auth.authStateChanges).thenAnswer((_) => events.stream);
        when(
          () => profiles.getAdmissionStatus(),
        ).thenAnswer((_) async => admissionStatus());
        final admission = AdmissionController(
          authService: auth,
          profileService: profiles,
        );
        final router = GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
        );
        await admission.revalidate();
        final bootstrap = await FirebaseBootstrap.create(
          auth: auth,
          admission: admission,
          router: router,
          supabaseUrl: 'https://mock.invalid',
          publicKey: 'public',
          notifications: () => throw StateError(
            'Firebase remains disabled in this integration fixture',
          ),
        );
        await drain();
        // Seed existing consent; SDK/native behavior is separately exercised with Driver.
        bootstrap.service.pushEnabled = true;
        final pending = Completer<AdmissionStatus>();
        when(
          () => profiles.getAdmissionStatus(),
        ).thenAnswer((_) => pending.future);
        final checking = admission.revalidate();
        current = event == AuthChangeEvent.signedOut
            ? null
            : admissionSession(
                expiresAt: DateTime.now().add(const Duration(hours: 1)),
                revision: 'new-login-session',
              );
        events.add(AuthState(event, current));
        await drain();
        final consentSurvived = bootstrap.service.pushEnabled;
        pending.complete(admissionStatus());
        await checking;
        bootstrap.dispose();
        admission.dispose();
        router.dispose();
        await events.close();
        expect(
          consentSurvived,
          isFalse,
          reason:
              'isChecking must not classify a hard login boundary as only a soft admission refresh.',
        );
      },
    );
  }
}
