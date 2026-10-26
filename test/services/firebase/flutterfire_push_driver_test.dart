import 'dart:async';

import 'package:clean_stream_laundry_app/services/firebase/firebase_configuration.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:clean_stream_laundry_app/services/firebase/flutterfire_driver.dart';
import 'package:firebase_core/firebase_core.dart'
    show Firebase, FirebaseException;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service_test.dart' show Driver, Tokens;

// Real push adapter/channel path; unrelated Firebase effects and permission use
// the service fixture. The method-channel host below still substitutes for iOS.
class _PushDriver extends Driver {
  final FlutterFireDriver adapter;
  int refreshEvents = 0;

  _PushDriver(this.adapter);

  @override
  Future<String?> token() => adapter.token();

  @override
  Future<void> deleteToken() => adapter.deleteToken();

  @override
  Stream<String> get tokenChanges => adapter.tokenChanges.map((token) {
    refreshEvents++;
    return token;
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/firebase_messaging');
  final calls = <String>[];
  late Completer<void> enabling;
  String? apns;
  bool autoInit = false;
  bool failDisable = false;
  bool failGetToken = false;
  Future<void> Function()? onEnable;
  final output = <String>[];

  FlutterFireDriver driver(TargetPlatform platform) => FlutterFireDriver(
    FirebaseConfiguration(
      'dev',
      platform == TargetPlatform.iOS ? 'ios' : 'android',
      Firebase.app().options,
    ),
  );

  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() action,
  ) async {
    final previous = debugDefaultTargetPlatformOverride;
    final originalDebugPrint = debugPrint;
    debugDefaultTargetPlatformOverride = platform;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) output.add(message);
    };
    try {
      await action();
    } finally {
      debugDefaultTargetPlatformOverride = previous;
      debugPrint = originalDebugPrint;
    }
  }

  Future<void> refresh(String value) async {
    final done = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('Messaging#onTokenRefresh', value),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    calls.clear();
    output.clear();
    apns = null;
    autoInit = false;
    failDisable = false;
    failGetToken = false;
    onEnable = null;
    enabling = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'Messaging#getAPNSToken':
          calls.add('apns');
          return {'token': apns};
        case 'Messaging#setAutoInitEnabled':
          final enabled = (call.arguments as Map)['enabled'] as bool;
          calls.add('auto:$enabled');
          if (!enabled && failDisable) {
            throw PlatformException(
              code: 'unknown',
              message: 'private-disable',
            );
          }
          autoInit = enabled;
          if (enabled) {
            if (!enabling.isCompleted) enabling.complete();
            await onEnable?.call();
          }
          return {'isAutoInitEnabled': enabled};
        case 'Messaging#getToken':
          calls.add('get');
          if (failGetToken) {
            throw PlatformException(code: 'unknown', message: 'private-get');
          }
          return {'token': 'private-existing-token'};
        case 'Messaging#deleteToken':
          calls.add('delete');
          return null;
        default:
          throw StateError('Unexpected messaging method: ${call.method}');
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    TestFirebaseCoreHostApi.setUp(null);
    expect(output.join(), isNot(contains('private-')));
  });

  for (final early in [false, true]) {
    test(
      'fresh iOS registers and receives token, early refresh=$early',
      () async {
        await onPlatform(TargetPlatform.iOS, () async {
          if (early) {
            onEnable = () async {
              apns = 'private-apns';
              await refresh('private-fresh-token');
              await refresh('private-second-token');
            };
          }
          final result = driver(TargetPlatform.iOS).token();
          await enabling.future;
          expect(calls, ['apns', 'auto:true']);
          if (!early) {
            apns = 'private-apns';
            await refresh('private-fresh-token');
          }
          expect(await result, 'private-fresh-token');
          expect(calls, ['apns', 'auto:true', 'auto:false']);
          expect(autoInit, isFalse);
          expect(FirebaseMessaging.instance.isAutoInitEnabled, isFalse);
          await refresh('private-late-token');
          expect(calls, ['apns', 'auto:true', 'auto:false']);
        });
      },
    );
  }

  test('existing iOS APNs uses explicit getToken without auto-init', () async {
    await onPlatform(TargetPlatform.iOS, () async {
      apns = 'private-apns';
      expect(
        await driver(TargetPlatform.iOS).token(),
        'private-existing-token',
      );
      expect(calls, ['apns', 'apns', 'get']);
      expect(autoInit, isFalse);
    });
  });

  test('existing iOS token failure does not enable auto-init', () async {
    await onPlatform(TargetPlatform.iOS, () async {
      apns = 'private-apns';
      failGetToken = true;
      await expectLater(
        driver(TargetPlatform.iOS).token(),
        throwsA(isA<FirebaseException>()),
      );
      expect(calls, ['apns', 'apns', 'get']);
      expect(autoInit, isFalse);
    });
  });

  test('enable failure disables auto-init and allows a fresh retry', () async {
    await onPlatform(TargetPlatform.iOS, () async {
      onEnable = () async {
        throw PlatformException(code: 'unknown', message: 'private-enable');
      };
      await expectLater(
        driver(TargetPlatform.iOS).token(),
        throwsA(isA<FirebaseException>()),
      );
      expect(calls, ['apns', 'auto:true', 'auto:false']);
      expect(autoInit, isFalse);
      await refresh('private-late-token');
      onEnable = () async {
        apns = 'private-apns';
        await refresh('private-retry-token');
      };
      expect(await driver(TargetPlatform.iOS).token(), 'private-retry-token');
      expect(autoInit, isFalse);
      expect(calls, [
        'apns',
        'auto:true',
        'auto:false',
        'apns',
        'auto:true',
        'auto:false',
      ]);
    });
  });

  for (final enableReply in ['immediate', 'late-error', 'late-success']) {
    test(
      'iOS timeout disables registration, enable reply=$enableReply',
      () async {
        await onPlatform(TargetPlatform.iOS, () async {
          final held = Completer<void>();
          if (enableReply != 'immediate') onEnable = () => held.future;
          final result = driver(TargetPlatform.iOS).token();
          final checked = expectLater(result, throwsA(isA<TimeoutException>()));
          await enabling.future;
          expect(calls, ['apns', 'auto:true']);
          await checked;
          expect(calls, ['apns', 'auto:true', 'auto:false']);
          expect(autoInit, isFalse);
          if (enableReply != 'immediate') {
            if (enableReply == 'late-success') {
              held.complete();
            } else {
              held.completeError(
                PlatformException(
                  code: 'unknown',
                  message: 'private-late-enable',
                ),
              );
            }
            await Future<void>.delayed(Duration.zero);
          }
          // A late reply can stale the Dart cache without repeating the native set.
          expect(
            FirebaseMessaging.instance.isAutoInitEnabled,
            enableReply == 'late-success',
          );
          await refresh('private-late-token');
          expect(autoInit, isFalse);
          expect(calls, ['apns', 'auto:true', 'auto:false']);
        });
      },
    );
  }

  test(
    'failure to disable auto-init is not reported as token success',
    () async {
      await onPlatform(TargetPlatform.iOS, () async {
        failDisable = true;
        onEnable = () async {
          apns = 'private-apns';
          await refresh('private-fresh-token');
        };
        await expectLater(
          driver(TargetPlatform.iOS).token(),
          throwsA(isA<FirebaseException>()),
        );
        expect(calls, ['apns', 'auto:true', 'auto:false']);
        failDisable = false;
        await driver(TargetPlatform.iOS).deleteToken();
        expect(autoInit, isFalse);
        expect(calls.skip(3), ['auto:false', 'apns', 'delete']);
      });
    },
  );

  test('Android stays explicit and cleanup keeps auto-init off', () async {
    await onPlatform(TargetPlatform.android, () async {
      final adapter = driver(TargetPlatform.android);
      expect(await adapter.token(), 'private-existing-token');
      expect(calls, ['get']);
      await adapter.deleteToken();
      expect(calls, ['get', 'auto:false', 'delete']);
      expect(autoInit, isFalse);
    });
  });

  test(
    'iOS cleanup with absent APNs still fails without registering',
    () async {
      await onPlatform(TargetPlatform.iOS, () async {
        await expectLater(
          driver(TargetPlatform.iOS).deleteToken(),
          throwsA(
            isA<FirebaseException>().having(
              (error) => error.code,
              'code',
              'apns-token-not-set',
            ),
          ),
        );
        expect(calls, ['auto:false', 'apns']);
        expect(autoInit, isFalse);
      });
    },
  );

  for (final invalidation in ['A-B-A', 'disable']) {
    test('service rejects early iOS refresh after $invalidation', () async {
      await onPlatform(TargetPlatform.iOS, () async {
        SharedPreferences.setMockInitialValues({});
        final hybrid = _PushDriver(driver(TargetPlatform.iOS))..offline = true;
        final tokens = Tokens();
        final service = FirebaseService(
          driver: hybrid,
          tokens: tokens,
          preferences: await SharedPreferences.getInstance(),
          environment: 'dev',
          platform: 'ios',
          version: '1.0.0',
          build: '10',
          navigate: (_) async {},
          showNotification: (_) async {},
          diagnostic: output.add,
        );
        final held = Completer<void>();
        Future<void>? pending;
        var finished = false;
        try {
          await service.start();
          await service.accountChanged(const PushAccount('A', 'bearerA'));
          await service.resume();
          expect(service.available, isTrue);
          expect(calls, isNot(contains('auto:true')));
          calls.clear();
          onEnable = () => held.future;
          pending = service.setPush(true).then((_) {
            finished = true;
          });
          await enabling.future;
          expect(calls, ['apns', 'auto:true']);
          expect(autoInit, isTrue);
          apns = 'private-apns';
          await refresh('private-early-token');
          await Future<void>.delayed(Duration.zero);
          expect(hybrid.refreshEvents, 1);
          expect(service.pushEnabled, isTrue);
          expect(finished, isFalse);
          expect(tokens.owners, isEmpty);

          final Future<void> invalidated;
          if (invalidation == 'A-B-A') {
            await service.accountChanged(const PushAccount('B', 'bearerB'));
            invalidated = service.accountChanged(
              const PushAccount('A', 'bearerA'),
            );
          } else {
            invalidated = service.disablePush();
          }
          expect(service.pushEnabled, isFalse);
          held.complete();
          await pending;
          await invalidated;
          // Public serialized barrier also drains the early refresh's queued work.
          await service.resume();
          expect(finished, isTrue);
          expect(
            output.where(
              (message) => message.startsWith('Push registration unavailable.'),
            ),
            isEmpty,
          );
          expect(tokens.owners, isEmpty);
          expect(service.pushEnabled, isFalse);
          expect(autoInit, isFalse);
          expect(FirebaseMessaging.instance.isAutoInitEnabled, isFalse);
          expect(calls.where((call) => call == 'auto:true'), hasLength(1));
          expect(calls, contains('delete'));
          expect(calls, isNot(contains('get')));

          final settledCalls = List<String>.of(calls);
          await refresh('private-late-token');
          await Future<void>.delayed(Duration.zero);
          expect(hybrid.refreshEvents, 2);
          expect(calls, settledCalls);
          expect(tokens.owners, isEmpty);
          expect(service.pushEnabled, isFalse);
        } finally {
          if (!held.isCompleted) held.complete();
          await pending;
          await service.disablePush();
          service.dispose();
          await hybrid.refreshes.close();
          await hybrid.opens.close();
          await hybrid.foreground.close();
        }
      });
    });
  }
}
