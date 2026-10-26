import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service_test.dart' show Driver, Tokens;

class CleanupDriver extends Driver {
  Object? tokenError;
  bool failInstallation = false;
  bool failConsent = false;

  @override
  Future<void> deleteToken() async {
    calls.add('delete');
    final error = tokenError;
    if (error != null) throw error;
  }

  @override
  Future<void> deleteInstallation() async {
    if (failInstallation) throw StateError('private-installation-detail');
    await super.deleteInstallation();
  }

  @override
  Future<void> analytics(bool enabled) async {
    if (failConsent) throw StateError('private-consent-detail');
    await super.analytics(enabled);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const warning =
      'Push cleanup pending. Reconnect and retry before enabling push.';
  late SharedPreferences prefs;
  late CleanupDriver driver;
  late Tokens tokens;
  late FirebaseService service;
  final diagnostics = <String>[];

  FirebaseService make() => FirebaseService(
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    driver = CleanupDriver();
    tokens = Tokens();
    diagnostics.clear();
    service = make();
  });

  tearDown(() async {
    service.dispose();
    await driver.refreshes.close();
    await driver.opens.close();
    await driver.foreground.close();
  });

  for (final failure in ['server', 'sdk']) {
    test(
      'deletion stays pending after $failure push cleanup failure',
      () async {
        const request = 'subject-a:deletion-request';
        const pending = 'firebase.dev.deletion.pending';
        const completed = 'firebase.dev.deletion.completed';
        await service.start();
        tokens.failRevoke = failure == 'server';
        if (failure == 'sdk') {
          driver.tokenError = StateError('private-token-detail');
        }
        await service.deletionChanged(request);
        expect(prefs.getString(pending), request);
        expect(prefs.getString(completed), isNull);
        expect(driver.calls, isNot(contains('delete-installation')));
        await service.deletionChanged(null);
        expect(service.analyticsEnabled, isFalse);

        service.dispose();
        SharedPreferences.resetStatic();
        prefs = await SharedPreferences.getInstance();
        service = make();
        await service.start();
        expect(prefs.getString(pending), request);
        expect(prefs.getString(completed), isNull);
        expect(service.analyticsEnabled, isFalse);
        expect(driver.calls, isNot(contains('delete-installation')));

        tokens.failRevoke = false;
        driver.tokenError = null;
        await service.resume();
        expect(prefs.getString(pending), isNull);
        expect(prefs.getString(completed), request);
        expect(
          driver.calls.where((call) => call == 'delete-installation'),
          hasLength(1),
        );
        expect(service.problem, isNull);
        expect(diagnostics.join(), isNot(contains('private-token-detail')));
      },
    );
  }

  test(
    'Retry clears startup push warning only after cleanup succeeds',
    () async {
      driver.tokenError = StateError('private-token-detail');
      await service.start();
      expect(service.problem, warning);
      expect(service.pushCleanupDiagnostic, 'Push SDK cleanup failed.');
      expect(
        service.pushCleanupDiagnostic,
        isNot(contains('private-token-detail')),
      );
      driver.tokenError = null;
      final observed = <String?>[];
      final observedCategories = <String?>[];
      service.addListener(() => observed.add(service.problem));
      service.addListener(
        () => observedCategories.add(service.pushCleanupDiagnostic),
      );
      await service.resume();
      expect(service.problem, isNull);
      expect(service.pushCleanupDiagnostic, isNull);
      expect(observed, contains(null));
      expect(observedCategories, contains(null));
      expect(tokens.revocations, 2);
      expect(driver.calls.where((call) => call == 'delete'), hasLength(2));
      expect(service.pushEnabled, isFalse);
      expect(tokens.owners, isEmpty);
      expect(diagnostics.join(), isNot(contains('private-token-detail')));
      expect(diagnostics, contains('Push SDK cleanup failed.'));
      expect(diagnostics, isNot(contains('Push server cleanup failed.')));
    },
  );

  test('server revoke failure stays pending despite SDK success', () async {
    tokens.failRevoke = true;
    await service.start();
    await service.resume();
    expect(service.problem, warning);
    expect(service.pushCleanupDiagnostic, 'Push server cleanup failed.');
    expect(diagnostics.join(), isNot(contains('offline')));
    expect(tokens.revocations, 2);
    expect(diagnostics, contains('Push server cleanup failed.'));
    expect(diagnostics, isNot(contains('Push SDK cleanup failed.')));
    expect(driver.calls.where((call) => call == 'delete'), hasLength(2));
    tokens.failRevoke = false;
    await service.resume();
    expect(service.problem, isNull);
    expect(service.pushCleanupDiagnostic, isNull);
    expect(service.pushEnabled, isFalse);
  });

  for (final error in <Object>[
    FirebaseException(
      plugin: 'firebase_messaging',
      code: 'apns-token-not-set',
      message: 'private-provider-detail',
    ),
    PlatformException(code: 'unknown', message: 'private-provider-detail'),
  ]) {
    test(
      'SDK ${error.runtimeType} failure is not treated as cleanup',
      () async {
        driver.tokenError = error;
        await service.start();
        await service.resume();
        expect(service.problem, warning);
        expect(
          service.pushCleanupDiagnostic,
          error is FirebaseException
              ? 'Push SDK cleanup waiting for APNs.'
              : 'Push SDK cleanup failed.',
        );
        expect(tokens.revocations, 2);
        expect(service.pushEnabled, isFalse);
        expect(diagnostics.join(), isNot(contains('private-provider-detail')));
        expect(
          diagnostics,
          contains(
            error is FirebaseException
                ? 'Push SDK cleanup waiting for APNs.'
                : 'Push SDK cleanup failed.',
          ),
        );
      },
    );
  }

  test('both cleanup failures are retained and replaced on retry', () async {
    tokens.failRevoke = true;
    driver.tokenError = StateError('private-token-detail');
    await service.start();
    expect(service.problem, warning);
    expect(
      service.pushCleanupDiagnostic,
      'Push server cleanup failed.\nPush SDK cleanup failed.',
    );
    tokens.failRevoke = false;
    driver.tokenError = FirebaseException(
      plugin: 'firebase_messaging',
      code: 'apns-token-not-set',
      message: 'private-provider-detail',
    );
    await service.resume();
    expect(service.problem, warning);
    expect(service.pushCleanupDiagnostic, 'Push SDK cleanup waiting for APNs.');
    driver.tokenError = null;
    await service.resume();
    expect(service.problem, isNull);
    expect(service.pushCleanupDiagnostic, isNull);
    expect(tokens.revocations, 3);
    expect(driver.calls.where((call) => call == 'delete'), hasLength(3));
    expect(service.pushEnabled, isFalse);
    expect(tokens.owners, isEmpty);
    expect(diagnostics.join(), isNot(contains('private-')));
    expect(diagnostics.join(), isNot(contains('offline')));
  });

  test('successful push cleanup preserves unresolved device privacy', () async {
    await service.start();
    driver.failInstallation = true;
    await service.deletionChanged('synthetic-deletion-request');
    const privacyWarning =
        'Device privacy cleanup pending. Reconnect and retry.';
    expect(service.problem, privacyWarning);
    await service.resume();
    expect(service.pushCleanupDiagnostic, isNull);
    expect(diagnostics.join(), isNot(contains('private-installation-detail')));
    expect(service.problem, privacyWarning);
    expect(
      prefs.getString('firebase.dev.deletion.pending'),
      'synthetic-deletion-request',
    );
    expect(prefs.getString('firebase.dev.deletion.completed'), isNull);
    expect(service.analyticsEnabled, isFalse);
    expect(service.messagesEnabled, isFalse);
    expect(service.pushEnabled, isFalse);
  });

  test('successful push cleanup does not clear consent failures', () async {
    await service.start();
    driver.failConsent = true;
    await service.setMessages(false);
    await service.disablePush();
    expect(service.problem, 'Could not apply privacy consent. Please retry.');
    expect(service.pushCleanupDiagnostic, isNull);
    expect(diagnostics.join(), isNot(contains('private-consent-detail')));
  });

  test(
    'skipped unavailable SDK cleanup cannot clear an existing warning',
    () async {
      driver.tokenError = StateError('private-token-detail');
      await service.start();
      expect(service.pushCleanupDiagnostic, 'Push SDK cleanup failed.');
      driver.tokenError = null;
      service.available = false;
      await service.disablePush();
      expect(service.problem, warning);
      expect(service.pushCleanupDiagnostic, 'Push SDK cleanup failed.');
      expect(
        service.pushCleanupDiagnostic,
        isNot(contains('private-token-detail')),
      );
      expect(diagnostics.join(), isNot(contains('private-token-detail')));
      expect(tokens.revocations, 2);
      expect(driver.calls.where((call) => call == 'delete'), hasLength(1));
    },
  );
}
