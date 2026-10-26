import 'dart:convert';

import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const key =
      'cortina.pending.v1.'
      '%5B%22https%3A%2F%2Ftest.invalid%22%2C%22owner%22%2C7%5D';
  const payment = CortinaPendingPayment(
    requestId: 'channel-fixture-request',
    method: 'card',
    amountCents: 150,
  );
  final calls = <MethodCall>[];
  final records = <String, String>{};
  var failRead = false;

  setUp(() {
    calls.clear();
    records.clear();
    failRead = false;
    // Keep the real Dart plugin; intercept only its native transport.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      final arguments = call.arguments as Map;
      switch (call.method) {
        case 'read':
          if (failRead) {
            throw PlatformException(code: 'fixture_read_failure');
          }
          return records[arguments['key']];
        case 'write':
          records[arguments['key'] as String] = arguments['value'] as String;
          return null;
        default:
          fail('Unexpected secure-storage native call: ${call.method}');
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '${platform.name} pending-store channel preserves key and policy',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        try {
          final store = CortinaPendingStore(project: 'https://test.invalid');
          final scope = store.scope(accountId: 'owner', machineId: 7);
          expect(scope, key);
          await store.claim(scope, payment);
          expect(calls.map((call) => call.method), ['read', 'write', 'read']);
          expect(records, {key: jsonEncode(payment.toJson())});
          for (final call in calls) {
            final arguments = call.arguments as Map;
            expect(arguments['key'], key);
            final options = arguments['options'] as Map;
            if (platform == TargetPlatform.android) {
              expect(options['resetOnError'], 'false');
              expect(
                options['keyCipherAlgorithm'],
                'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
              );
              expect(options['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
              expect(options['migrateOnAlgorithmChange'], 'true');
              expect(options['migrateWithBackup'], 'false');
              expect(options['enforceBiometrics'], 'false');
              expect(options['storageNamespace'], '');
              expect(options['preferencesKeyPrefix'], '');
            } else {
              expect(options['accountName'], 'flutter_secure_storage_service');
              expect(options['accessibility'], 'unlocked_this_device');
              expect(options['synchronizable'], 'false');
              expect(options['useSecureEnclave'], 'false');
              expect(options.containsKey('groupId'), isFalse);
              expect(options.containsKey('accessControlFlags'), isFalse);
            }
          }
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );

    test(
      '${platform.name} native read error cannot delete or replace pending data',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        try {
          final retained = jsonEncode(payment.toJson());
          records[key] = retained;
          failRead = true;
          final store = CortinaPendingStore(project: 'https://test.invalid');
          final error = isA<PlatformException>().having(
            (value) => value.code,
            'code',
            'fixture_read_failure',
          );
          await expectLater(store.read(key), throwsA(error));
          await expectLater(store.claim(key, payment), throwsA(error));
          expect(calls.map((call) => call.method), ['read', 'read']);
          expect(calls.map((call) => (call.arguments as Map)['key']), [
            key,
            key,
          ]);
          expect(records, {key: retained});
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );
  }
}
