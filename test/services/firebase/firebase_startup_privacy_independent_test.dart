import 'dart:async';

import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service_test.dart' show Driver, Tokens;

class HeldStartupCleanup extends Tokens {
  final entered = Completer<void>();
  final released = Completer<void>();

  @override
  Future<void> revoke() async {
    if (!entered.isCompleted) entered.complete();
    await released.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final deletingAccount in [false, true]) {
    test(
      'startup respects newer privacy state, deletion=$deletingAccount',
      () async {
        SharedPreferences.setMockInitialValues({
          'firebase.dev.consent.analytics': true,
          'firebase.dev.consent.messages': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final driver = Driver();
        final tokens = HeldStartupCleanup();
        final service = FirebaseService(
          driver: driver,
          tokens: tokens,
          preferences: prefs,
          environment: 'dev',
          platform: 'android',
          version: '1.0.0',
          build: '10',
          navigate: (_) async {},
          showNotification: (_) async {},
          diagnostic: (_) {},
        );
        addTearDown(service.dispose);
        final starting = service.start();
        await tokens.entered.future;
        expect(service.available, isTrue);

        // Privacy changes must not wait for held push cleanup.
        final changing = deletingAccount
            ? service.deletionChanged('subject:request')
            : service.setMessages(false);
        await Future<void>.delayed(Duration.zero);
        expect(prefs.getBool('firebase.dev.consent.analytics'), isNull);
        expect(prefs.getBool('firebase.dev.consent.messages'), isFalse);
        driver.calls.clear();
        tokens.released.complete();
        await starting;
        await changing;

        expect(
          driver.calls,
          deletingAccount
              ? isNot(contains('analytics:true'))
              : contains('analytics:true'),
          reason:
              'Analytics follows policy unless deletion requires a privacy pause.',
        );
        expect(driver.calls, isNot(contains('messages:true')));
        expect(service.analyticsEnabled, !deletingAccount);
        expect(service.messagesEnabled, isFalse);
        expect(prefs.getBool('firebase.dev.consent.analytics'), isNull);
        expect(prefs.getBool('firebase.dev.consent.messages'), isFalse);
      },
    );
  }
}
