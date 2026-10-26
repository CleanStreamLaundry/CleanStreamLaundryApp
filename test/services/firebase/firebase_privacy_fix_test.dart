import 'dart:async';

import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_bootstrap.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/admission/mocks.dart';
import 'firebase_service_test.dart' show Driver, Tokens, drain;

class PrivacyDriver extends Driver {
  bool failAnalytics = false;
  bool failMessages = false;
  @override
  Future<void> analytics(bool enabled) async {
    await super.analytics(enabled);
    if (failAnalytics) throw StateError('Analytics unavailable');
  }

  @override
  Future<void> inAppMessaging(bool enabled) async {
    await super.inAppMessaging(enabled);
    if (failMessages) throw StateError('FIAM unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late PrivacyDriver driver;
  late Tokens tokens;
  late FirebaseService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    driver = PrivacyDriver();
    tokens = Tokens();
    service = FirebaseService(
      driver: driver,
      tokens: tokens,
      preferences: prefs,
      environment: 'dev',
      platform: 'ios',
      version: '1.0.0',
      build: '1',
      navigate: (_) async {},
      showNotification: (_) async {},
      diagnostic: (_) {},
    );
  });
  tearDown(() => service.dispose());

  test(
    'startup consent-effect failures remain independently retryable',
    () async {
      driver.failAnalytics = true;
      driver.failMessages = true;
      await service.start();
      expect(driver.calls, containsAll(['analytics:false', 'messages:false']));
      expect(service.problem, contains('privacy consent'));
      expect(service.analyticsEnabled, isTrue);
      expect(service.messagesEnabled, isFalse);
      driver.failAnalytics = false;
      driver.failMessages = false;
      driver.calls.clear();
      await service.resume();
      expect(driver.calls, containsAll(['analytics:true', 'messages:false']));
      expect(service.problem, isNull);
    },
  );

  test(
    'startup preserves previously explicit independent message consent',
    () async {
      await prefs.setBool('firebase.dev.consent.analytics', true);
      await prefs.setBool('firebase.dev.consent.messages', true);
      await service.start();
      expect(service.analyticsEnabled, isTrue);
      expect(service.messagesEnabled, isTrue);
      expect(prefs.getBool('firebase.dev.consent.messages'), isTrue);
      expect(driver.calls.last, 'messages:true');
    },
  );

  for (final effect in ['Analytics', 'FIAM', 'both']) {
    test(
      '$effect failure is truthful and resume retries consent effects',
      () async {
        await service.start();
        await service.setMessages(true);
        driver.failAnalytics = effect != 'FIAM';
        driver.failMessages = effect != 'Analytics';
        driver.calls.clear();
        await service.setMessages(false);
        expect(
          driver.calls,
          containsAll(['analytics:true', 'messages:false']),
        );
        expect(service.problem, contains('privacy consent'));
        await service.resume();
        expect(service.problem, contains('privacy consent'));
        driver.failAnalytics = false;
        driver.failMessages = false;
        driver.calls.clear();
        await service.resume();
        expect(
          driver.calls,
          containsAll(['analytics:true', 'messages:false']),
        );
        expect(driver.calls, isNot(contains('messages:true')));
        expect(service.problem, isNull);
        expect(prefs.getBool('firebase.dev.consent.analytics'), isNull);
        expect(prefs.getBool('firebase.dev.consent.messages'), isFalse);
      },
    );
  }

  test(
    'privacy revocation does not wait for pending push acquisition',
    () async {
      await service.start();
      await service.setMessages(true);
      await service.accountChanged(const PushAccount('A', 'bearer-A'));
      driver.delayedToken = Completer<String?>();
      final enabling = service.setPush(true);
      await drain();
      driver.calls.clear();
      final deleting = service.deletionChanged('subject:request');
      try {
        await drain();
        expect(
          driver.calls,
          containsAll(['analytics:false', 'messages:false']),
        );
      } finally {
        driver.delayedToken!.complete('token');
        await enabling;
        await deleting;
      }
    },
  );

  test(
    'same-session refresh preserves consent but discards held old bearer',
    () async {
      await service.start();
      final identity = Object();
      await service.accountChanged(
        PushAccount('A', 'old', sessionIdentity: identity),
      );
      driver.delayedToken = Completer<String?>();
      final enabling = service.setPush(true);
      await drain();
      await service.accountChanged(
        PushAccount('A', 'new', sessionIdentity: identity),
        admitted: false,
      );
      await service.accountChanged(
        PushAccount('A', 'new', sessionIdentity: identity),
      );
      driver.delayedToken!.complete('held-token');
      await enabling;
      expect(tokens.owners, isEmpty);
      expect(service.pushEnabled, isTrue);
      driver.delayedToken = null;
      await service.resume();
      expect(tokens.owners, ['A:new']);
    },
  );

  for (final mode in [
    'refresh',
    'hard-login',
    'pending',
    'expired',
    'terms',
    'mfa',
  ]) {
    test('bootstrap admission boundary: $mode', () async {
      PackageInfo.setMockInitialValues(
        appName: 'QA',
        packageName: 'qa',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      final auth = MockAdmissionAuthService();
      final profiles = MockAdmissionProfileService();
      final events = StreamController<AuthState>.broadcast();
      var current = admissionSession(
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
        notifications: () =>
            throw StateError('Native Firebase disabled in fixture'),
      );
      addTearDown(() async {
        bootstrap.dispose();
        admission.dispose();
        router.dispose();
        await events.close();
      });
      await drain();
      bootstrap.service.pushEnabled = true;
      bootstrap.service.analyticsEnabled = true;
      bootstrap.service.messagesEnabled = true;
      if (mode == 'refresh' || mode == 'hard-login') {
        current = admissionSession(
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          revision: 'next',
        );
        events.add(
          AuthState(
            mode == 'refresh'
                ? AuthChangeEvent.tokenRefreshed
                : AuthChangeEvent.signedIn,
            current,
          ),
        );
        await drain();
        expect(bootstrap.service.pushEnabled, mode == 'refresh');
      }
      final held = Completer<AdmissionStatus>();
      when(() => profiles.getAdmissionStatus()).thenAnswer((_) => held.future);
      final checking = admission.revalidate();
      await drain();
      expect(bootstrap.service.pushEnabled, mode != 'hard-login');
      final pending = mode == 'pending' || mode == 'expired';
      held.complete(
        pending
            ? AdmissionStatus.fromJson({
                'subject_id': accountA,
                'account_access': 'restricted',
                'next_step': 'blocked',
                'account_state': 'pending_deletion',
                'reason': mode == 'expired'
                    ? 'restore_expired'
                    : 'explicit_restore_required',
                'restore_until': mode == 'expired'
                    ? '2020-01-01T00:00:00Z'
                    : '2099-01-01T00:00:00Z',
              })
            : admissionStatus(
                step: mode == 'terms'
                    ? 'review_terms'
                    : mode == 'mfa'
                    ? 'challenge_totp'
                    : 'home',
              ),
      );
      await checking;
      await drain();
      if (pending) {
        expect(admission.retainSafePresentation, isTrue);
        expect(admission.canUseTopupRefunds, isTrue);
        final marker =
            '$accountA:${admission.status!.restoreUntil!.toIso8601String()}';
        expect(prefs.getString('firebase..deletion.pending'), marker);
        expect(prefs.getString('firebase..deletion.completed'), isNull);
        expect(bootstrap.service.analyticsEnabled, isFalse);
        expect(bootstrap.service.messagesEnabled, isFalse);
        expect(prefs.getBool('firebase..consent.analytics'), isNull);
        expect(prefs.getBool('firebase..consent.messages'), isFalse);
      } else {
        expect(prefs.getString('firebase..deletion.pending'), isNull);
      }
      expect(bootstrap.service.pushEnabled, mode == 'refresh');
    });
  }
}
