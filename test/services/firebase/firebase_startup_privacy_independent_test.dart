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
    entered.complete();
    await released.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup must not restore saved consent over a newer revocation',
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

      // Startup runs unawaited; enabled settings can receive newer user intent.
      await service.setAnalytics(true);
      await service.setMessages(true);
      await service.setAnalytics(false);
      expect(prefs.getBool('firebase.dev.consent.analytics'), isFalse);
      expect(prefs.getBool('firebase.dev.consent.messages'), isFalse);
      driver.calls.clear();
      tokens.released.complete();
      await starting;

      expect(
        driver.calls,
        isNot(contains('analytics:true')),
        reason:
            'An older startup snapshot must not re-enable revoked collection.',
      );
      expect(driver.calls, isNot(contains('messages:true')));
      expect(service.analyticsEnabled, isFalse);
      expect(service.messagesEnabled, isFalse);
      expect(prefs.getBool('firebase.dev.consent.analytics'), isFalse);
      expect(prefs.getBool('firebase.dev.consent.messages'), isFalse);
    },
  );
}
