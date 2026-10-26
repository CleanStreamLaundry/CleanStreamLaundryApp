import 'dart:async';

import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service_test.dart' show Driver, Tokens;

class PermissionDriver extends Driver {
  Completer<void>? permissionStarted;
  int tokenReads = 0;

  @override
  Future<bool> permission({required bool request}) {
    if (!request && permissionStarted != null) {
      permissionStarted!.complete();
      permissionStarted = null;
    }
    return super.permission(request: request);
  }

  @override
  Future<String?> token() {
    tokenReads++;
    return super.token();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PermissionDriver driver;
  late Tokens tokens;
  late FirebaseService service;
  const account = PushAccount('A', 'bearer-A');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    driver = PermissionDriver();
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
    await service.start();
    await service.accountChanged(account);
    await service.setPush(true);
    expect(driver.tokenReads, 1);
    expect(tokens.owners, ['A:bearer-A']);
    tokens.owners.clear();
  });

  tearDown(() async {
    service.dispose();
    await driver.refreshes.close();
    await driver.opens.close();
    await driver.foreground.close();
  });

  for (final change in ['disable', 'sign-out', 'A-B-A', 'admission', 'none']) {
    test(
      'pending resume permission does not fetch stale token after $change',
      () async {
        final started = Completer<void>();
        driver.permissionStarted = started;
        driver.delayedPermission = Completer<bool>();
        final resume = service.resume();
        await started.future;

        Future<void>? cleanup;
        switch (change) {
          case 'disable':
            cleanup = service.disablePush();
          case 'sign-out':
            await service.accountChanged(null);
          case 'A-B-A':
            await service.accountChanged(const PushAccount('B', 'bearer-B'));
            await service.accountChanged(account);
          case 'admission':
            await service.accountChanged(account, admitted: false);
          case 'none':
            break;
        }

        driver.delayedPermission!.complete(true);
        await resume;
        if (cleanup != null) await cleanup;
        // Drain any account-change cleanup queued behind registration.
        await service.resume();
        if (change == 'none') {
          expect(driver.tokenReads, 3);
          expect(tokens.owners, ['A:bearer-A', 'A:bearer-A']);
          expect(service.pushEnabled, isTrue);
        } else {
          expect(driver.tokenReads, 1);
          expect(tokens.owners, isEmpty);
        }
      },
    );
  }
}
