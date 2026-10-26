import 'dart:async';

import 'package:clean_stream_laundry_app/services/firebase/firebase_configuration.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:clean_stream_laundry_app/services/firebase/flutterfire_driver.dart';
import 'package:firebase_core/firebase_core.dart'
    show Firebase, FirebaseException;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'firebase_deletion_test.dart' show DeletionDriver;
import 'firebase_service_test.dart' show Tokens, drain;

class DeletionPersistence extends InMemorySharedPreferencesStore {
  DeletionPersistence() : super.empty();

  String? rejectedWrite;
  String? rejectedRemove;
  bool throwWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == rejectedWrite) {
      if (throwWrite) throw StateError('synthetic disk failure');
      return false;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async =>
      key == rejectedRemove ? false : super.remove(key);
}

class StartupDeletionDriver extends DeletionDriver {
  Completer<void>? initialization;

  @override
  Future<void> initialize() async => initialization?.future;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const pending = 'firebase.dev.deletion.pending';
  const completed = 'firebase.dev.deletion.completed';
  const request = 'subject-A:2099-01-01T00:00:00.000Z';
  late SharedPreferencesStorePlatform originalStore;
  late DeletionPersistence disk;
  late SharedPreferences prefs;
  late StartupDeletionDriver driver;
  late Tokens tokens;
  final services = <FirebaseService>[];

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
      diagnostic: (_) {},
    );
    services.add(service);
    return service;
  }

  Future<void> restartPreferences() async {
    SharedPreferences.resetStatic();
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() async {
    originalStore = SharedPreferencesStorePlatform.instance;
    disk = DeletionPersistence();
    SharedPreferencesStorePlatform.instance = disk;
    await restartPreferences();
    driver = StartupDeletionDriver();
    tokens = Tokens();
  });

  tearDown(() async {
    for (final service in services) {
      service.dispose();
    }
    services.clear();
    await driver.refreshes.close();
    await driver.opens.close();
    await driver.foreground.close();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = originalStore;
  });

  test(
    'real installations SDK dispatches delete and propagates host failure',
    () async {
      setupFirebaseCoreMocks();
      addTearDown(() => TestFirebaseCoreHostApi.setUp(null));
      await Firebase.initializeApp();
      const prefix =
          'dev.flutter.pigeon.firebase_app_installations_platform_interface.'
          'FirebaseAppInstallationsHostApi';
      const channel = BasicMessageChannel<Object?>(
        '$prefix.delete',
        StandardMessageCodec(),
      );
      const listener = BasicMessageChannel<Object?>(
        '$prefix.registerIdChangeListener',
        StandardMessageCodec(),
      );
      final calls = <Object?>[];
      var fail = false;
      binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        listener,
        (_) async => ['unavailable', 'No native listener in fixture', null],
      );
      binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        channel,
        (message) async {
          calls.add(message);
          return fail
              ? ['unavailable', 'synthetic deletion failure', null]
              : [null];
        },
      );
      addTearDown(() {
        binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
          channel,
          null,
        );
        binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
          listener,
          null,
        );
      });
      final adapter = FlutterFireDriver(
        FirebaseConfiguration.resolve(
          environment: 'dev',
          platform: 'android',
          androidKey: 'AIza${'0' * 35}',
          iosKey: '',
        )!,
      );
      await adapter.deleteInstallation();
      fail = true;
      await expectLater(
        adapter.deleteInstallation(),
        throwsA(isA<FirebaseException>()),
      );
      expect(calls, [
        ['[DEFAULT]'],
        ['[DEFAULT]'],
      ]);
    },
  );

  test('deletion during initialization outranks saved consent', () async {
    await prefs.setBool('firebase.dev.consent.analytics', true);
    await prefs.setBool('firebase.dev.consent.messages', true);
    driver.initialization = Completer<void>();
    final service = make();
    final starting = service.start();
    try {
      await service
          .deletionChanged(request)
          .timeout(const Duration(seconds: 1));
      expect((await disk.getAll())['flutter.$pending'], request);
      expect(driver.calls, isNot(contains('delete-installation')));
    } finally {
      driver.initialization!.complete();
      await starting;
    }
    expect(
      driver.calls.where((call) => call == 'delete-installation'),
      hasLength(1),
    );
    expect(driver.calls, isNot(contains('analytics:true')));
    expect(driver.calls, isNot(contains('messages:true')));
    expect(service.analyticsEnabled, isFalse);
    expect(service.messagesEnabled, isFalse);
  });

  for (final switchAccount in [false, true]) {
    test(
      'late permission cannot revive deletion opt-in, switch=$switchAccount',
      () async {
        final service = make();
        await service.start();
        await service.accountChanged(const PushAccount('A', 'bearer-A'));
        await service.setMessages(true);
        driver.delayedPermission = Completer<bool>();
        final enabling = service.setPush(true);
        await drain();
        expect(driver.calls, contains('permission:true'));
        driver.calls.clear();
        final deleting = service.deletionChanged(request);
        try {
          if (switchAccount) {
            await service.deletionChanged(null);
            await service.accountChanged(const PushAccount('B', 'bearer-B'));
          }
          await drain();
          expect(
            driver.calls,
            containsAll(['analytics:false', 'messages:false']),
          );
          expect((await disk.getAll())['flutter.$pending'], request);
          expect(service.pushEnabled, isFalse);
          expect(driver.calls, isNot(contains('delete-installation')));
        } finally {
          driver.delayedPermission!.complete(true);
          await enabling;
          await deleting;
        }
        await service.resume();
        expect(tokens.owners, isEmpty);
        expect(service.pushEnabled, isFalse);
        expect(
          driver.calls.where((call) => call == 'delete-installation'),
          hasLength(1),
        );
        if (switchAccount) {
          driver.delayedPermission = null;
          await service.setPush(true);
          expect(tokens.owners, ['B:bearer-B']);
        }
      },
    );
  }

  for (final throwsWrite in [false, true]) {
    test(
      'pending marker failure blocks deletion then retries, throw=$throwsWrite',
      () async {
        final service = make();
        await service.start();
        disk.rejectedWrite = 'flutter.$pending';
        disk.throwWrite = throwsWrite;
        await service.deletionChanged(request);
        expect(driver.calls, isNot(contains('delete-installation')));
        expect((await disk.getAll())['flutter.$pending'], isNull);
        expect(service.problem, contains('cleanup pending'));
        expect(service.analyticsEnabled, isFalse);
        disk.rejectedWrite = null;
        await service.resume();
        expect((await disk.getAll())['flutter.$completed'], request);
        expect((await disk.getAll())['flutter.$pending'], isNull);
      },
    );
  }

  test(
    'restart retries persisted provider failure without restoring consent',
    () async {
      final first = make();
      await first.start();
      driver.failDeletion = true;
      await first.deletionChanged(request);
      await restartPreferences();
      expect(prefs.getString(pending), request);
      driver.failDeletion = false;
      driver.calls.clear();
      final restarted = make();
      await restarted.start();
      expect(
        driver.calls.where((call) => call == 'delete-installation'),
        hasLength(1),
      );
      expect(driver.calls, isNot(contains('analytics:true')));
      expect((await disk.getAll())['flutter.$completed'], request);
      expect((await disk.getAll())['flutter.$pending'], isNull);
    },
  );

  test(
    'restart after pending removal failure does not repeat provider deletion',
    () async {
      final service = make();
      await service.start();
      disk.rejectedRemove = 'flutter.$pending';
      await service.deletionChanged(request);
      expect((await disk.getAll())['flutter.$pending'], request);
      expect((await disk.getAll())['flutter.$completed'], request);
      await restartPreferences();
      disk.rejectedRemove = null;
      driver.calls.clear();
      await make().start();
      expect(driver.calls, isNot(contains('delete-installation')));
      expect((await disk.getAll())['flutter.$pending'], isNull);
    },
  );

  for (final throwsWrite in [false, true]) {
    test(
      'failed completion write must be persisted on retry before clearing pending, '
      'throw=$throwsWrite',
      () async {
        final service = make();
        await service.start();
        disk.rejectedWrite = 'flutter.$completed';
        disk.throwWrite = throwsWrite;
        await service.deletionChanged(request);
        expect((await disk.getAll())['flutter.$pending'], request);
        expect((await disk.getAll())['flutter.$completed'], isNull);
        expect(service.problem, contains('cleanup pending'));
        await service.resume();
        expect((await disk.getAll())['flutter.$pending'], request);
        expect((await disk.getAll())['flutter.$completed'], isNull);
        expect(service.problem, contains('cleanup pending'));
        expect(
          driver.calls.where((call) => call == 'delete-installation'),
          hasLength(1),
        );
        disk.rejectedWrite = null;
        await service.resume();
        final durable = await disk.getAll();
        expect(
          durable['flutter.$completed'],
          request,
          reason:
              'A failed SharedPreferences write updates only its cache; '
              'retry must durably acknowledge completion before discarding pending cleanup.',
        );
        expect(durable['flutter.$pending'], isNull);
        expect(service.problem, isNull);
        expect(
          driver.calls.where((call) => call == 'delete-installation'),
          hasLength(1),
        );
        await restartPreferences();
        driver.calls.clear();
        final restarted = make();
        await restarted.deletionChanged(request);
        await restarted.start();
        expect(driver.calls, isNot(contains('delete-installation')));
      },
    );
  }
}
