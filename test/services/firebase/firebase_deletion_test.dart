import 'dart:async';

import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service_test.dart' show Driver, Tokens, drain;

class DeletionDriver extends Driver {
  bool failDeletion = false;
  Completer<void>? deletion;
  Completer<String>? policyFetch;
  int fetches = 0;

  @override
  Future<void> deleteInstallation() async {
    calls.add('delete-installation');
    await deletion?.future;
    if (failDeletion) throw StateError('private-provider-detail');
  }

  @override
  Future<String> releasePolicy() async {
    fetches++;
    return policyFetch?.future ?? raw;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pending = 'firebase.dev.deletion.pending';
  const completed = 'firebase.dev.deletion.completed';
  const request = 'current-subject:deletion-deadline';
  late SharedPreferences prefs;
  late DeletionDriver driver;
  late Tokens tokens;
  final diagnostics = <String>[];

  FirebaseService make() {
    final service = FirebaseService(
      driver: driver,
      tokens: tokens,
      preferences: prefs,
      environment: 'dev',
      platform: 'android',
      version: '1.0.0',
      build: '1',
      navigate: (_) async {},
      showNotification: (_) async {},
      diagnostic: diagnostics.add,
    );
    addTearDown(service.dispose);
    return service;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    driver = DeletionDriver();
    tokens = Tokens();
    diagnostics.clear();
  });

  test(
    'confirmed deletion revokes consent and deletes installation once',
    () async {
      final service = make();
      await service.start();
      await service.setMessages(true);
      await service.accountChanged(const PushAccount('a', 'bearer'));
      await service.setPush(true);
      driver.calls.clear();
      await service.deletionChanged(request);
      expect(service.analyticsEnabled, isFalse);
      expect(service.messagesEnabled, isFalse);
      expect(service.pushEnabled, isFalse);
      expect(
        driver.calls.indexOf('analytics:false'),
        lessThan(driver.calls.indexOf('delete-installation')),
      );
      expect(
        driver.calls.indexOf('messages:false'),
        lessThan(driver.calls.indexOf('delete-installation')),
      );
      expect(prefs.getString(pending), isNull);
      expect(prefs.getString(completed), request);
      await service.deletionChanged(null);
      await service.deletionChanged(request);
      await service.resume();
      expect(
        driver.calls.where((call) => call == 'delete-installation'),
        hasLength(1),
      );
    },
  );

  test('failure retries on resume without logging provider details', () async {
    final service = make();
    await service.start();
    driver.failDeletion = true;
    await service.deletionChanged(request);
    expect(prefs.getString(pending), request);
    expect(prefs.getString(completed), isNull);
    final fetches = driver.fetches;
    await service.refreshReleasePolicy();
    expect(driver.fetches, fetches);
    expect(diagnostics.join(), isNot(contains('private-provider-detail')));
    driver.failDeletion = false;
    await service.resume();
    expect(prefs.getString(pending), isNull);
    expect(prefs.getString(completed), request);
    expect(driver.fetches, greaterThan(fetches));
  });

  test(
    'startup retries durable cleanup without restoring old opt-ins',
    () async {
      await prefs.setString(pending, request);
      await prefs.setBool('firebase.dev.consent.analytics', true);
      await prefs.setBool('firebase.dev.consent.messages', true);
      final service = make();
      await service.start();
      expect(driver.calls, contains('delete-installation'));
      expect(driver.calls, isNot(contains('analytics:true')));
      expect(driver.calls, isNot(contains('messages:true')));
      expect(service.analyticsEnabled, isFalse);
      expect(service.messagesEnabled, isFalse);
      expect(prefs.getString(pending), isNull);
    },
  );

  test(
    'startup acknowledges completed cleanup without repeating provider delete',
    () async {
      await prefs.setString(pending, request);
      await prefs.setString(completed, request);
      final service = make();
      await service.start();
      expect(driver.calls, isNot(contains('delete-installation')));
      expect(prefs.getString(pending), isNull);
    },
  );

  test(
    'deletion before Firebase startup remains durable and is applied',
    () async {
      final service = make();
      await service.deletionChanged(request);
      expect(prefs.getString(pending), request);
      expect(driver.calls, isNot(contains('delete-installation')));
      await service.start();
      expect(
        driver.calls.where((call) => call == 'delete-installation'),
        hasLength(1),
      );
      await service.resume();
      expect(service.analyticsEnabled, isFalse);
    },
  );

  test(
    'cleanup pauses analytics; restoration resumes policy but not messaging opt-ins',
    () async {
      final service = make();
      await service.start();
      driver.deletion = Completer<void>();
      final cleanup = service.deletionChanged(request);
      await drain();
      await service.deletionChanged(null);
      await service.accountChanged(const PushAccount('b', 'new-bearer'));
      await service.setMessages(true);
      await service.setPush(true);
      expect(service.analyticsEnabled, isFalse);
      expect(service.messagesEnabled, isFalse);
      expect(service.pushEnabled, isFalse);
      driver.deletion!.complete();
      await cleanup;
      expect(service.analyticsEnabled, isTrue);
      expect(service.messagesEnabled, isFalse);
      expect(service.pushEnabled, isFalse);
      await service.setPush(true);
      expect(service.analyticsEnabled, isTrue);
      expect(tokens.owners, ['b:new-bearer']);
    },
  );

  test(
    'in-flight policy fetch finishes before deletion; cached policy remains',
    () async {
      final service = make();
      await service.start();
      await drain();
      final policy = service.policy;
      driver.policyFetch = Completer<String>();
      final fetch = service.refreshReleasePolicy();
      final cleanup = service.deletionChanged(request);
      await drain();
      expect(driver.calls, isNot(contains('delete-installation')));
      expect(service.policy, policy);
      driver.policyFetch!.complete(driver.raw);
      await fetch;
      await cleanup;
      expect(driver.calls, contains('delete-installation'));
      expect(prefs.getString('firebase.dev.android.release.v1'), driver.raw);
    },
  );

  test(
    'ordinary sign-out and consent revocation do not erase installations',
    () async {
      final service = make();
      await service.start();
      await service.accountChanged(const PushAccount('a', 'bearer'));
      await service.accountChanged(null);
      await service.setMessages(false);
      await service.disablePush();
      await service.resume();
      expect(driver.calls, isNot(contains('delete-installation')));
    },
  );

  test('cleanup markers stay scoped to their Firebase environment', () async {
    await prefs.setString('firebase.prod.deletion.pending', request);
    final service = make();
    await service.start();
    expect(driver.calls, isNot(contains('delete-installation')));
    expect(prefs.getString('firebase.prod.deletion.pending'), request);
  });
}
