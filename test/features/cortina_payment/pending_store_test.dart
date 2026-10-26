import 'dart:convert';

import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class _SecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  const payment = CortinaPendingPayment(
    requestId: 'request', method: 'card', amountCents: 150,
  );
  const reference = CortinaVendReference(sessionId: 'session', accessToken: 'capability');
  late CortinaPendingStore store;
  late String scope;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = CortinaPendingStore(project: 'https://test.invalid');
    scope = store.scope(accountId: 'owner', machineId: 7);
  });

  test('separate adapter restores the same structured record and reference', () async {
    await store.claim(scope, payment);
    await store.attach(scope, 'request', reference);
    final restarted = CortinaPendingStore(project: 'https://test.invalid');
    final saved = await restarted.read(scope);
    expect(saved?.requestId, 'request');
    expect(saved?.method, 'card');
    expect(saved?.amountCents, 150);
    expect(saved?.reference?.sessionId, 'session');
    expect(saved?.reference?.accessToken, 'capability');
  });

  test('account, guest, project and machine keys do not collide', () {
    expect({
      scope,
      store.scope(accountId: null, machineId: 7),
      store.scope(accountId: 'null', machineId: 7),
      store.scope(accountId: 'other', machineId: 7),
      store.scope(accountId: 'owner', machineId: 8),
      CortinaPendingStore(project: 'https://other.invalid').scope(accountId: 'owner', machineId: 7),
    }, hasLength(6));
  });

  test('serialized competing claims cannot replace the first attempt', () async {
    final first = store.claim(scope, payment);
    final second = store.claim(scope, const CortinaPendingPayment(
      requestId: 'other', method: 'wallet', amountCents: 150,
    ));
    await expectLater(second, throwsStateError);
    await first;
    expect((await store.read(scope))?.requestId, 'request');
  });

  test('stale attachment and clear cannot change a different attempt', () async {
    await store.claim(scope, payment);
    await expectLater(store.attach(scope, 'stale', reference), throwsStateError);
    await expectLater(store.clear(scope, 'stale'), throwsStateError);
    expect((await store.read(scope))?.requestId, 'request');
    expect((await store.read(scope))?.reference, isNull);
  });

  test('same reference is idempotent but conflicting reference is refused', () async {
    await store.claim(scope, payment);
    await store.attach(scope, 'request', reference);
    await store.attach(scope, 'request', reference);
    await expectLater(store.attach(scope, 'request', const CortinaVendReference(
      sessionId: 'other', accessToken: 'other',
    )), throwsStateError);
    expect((await store.read(scope))?.reference?.sessionId, 'session');
  });

  test('matching confirmed clear permits a fresh attempt', () async {
    await store.claim(scope, payment);
    await store.clear(scope, 'request');
    expect(await store.read(scope), isNull);
    await store.claim(scope, const CortinaPendingPayment(
      requestId: 'fresh', method: 'wallet', amountCents: 200,
    ));
    expect((await store.read(scope))?.requestId, 'fresh');
  });

  for (final malformed in [
    '{invalid',
    jsonEncode({'version': 2}),
    jsonEncode({...payment.toJson(), 'sessionId': 'session'}),
    jsonEncode({...payment.toJson(), 'amountCents': 1.5}),
  ]) {
    test('malformed record remains untouched: $malformed', () async {
      const storage = FlutterSecureStorage();
      await storage.write(key: scope, value: malformed);
      await expectLater(store.read(scope), throwsFormatException);
      await expectLater(store.claim(scope, payment), throwsFormatException);
      expect(await storage.read(key: scope), malformed);
    });
  }

  for (final operation in ['claim', 'attach', 'clear']) {
    test('$operation rejects a secure storage exception', () async {
      final storage = _SecureStorage();
      when(() => storage.read(key: scope)).thenAnswer((_) async =>
        operation == 'claim' ? null : jsonEncode(payment.toJson()),
      );
      when(() => storage.write(key: scope, value: any(named: 'value')))
        .thenThrow(StateError('Secure storage unavailable'));
      when(() => storage.delete(key: scope)).thenThrow(StateError('Secure storage unavailable'));
      final failing = CortinaPendingStore(
        project: 'https://test.invalid', storage: storage,
      );
      await expectLater(switch (operation) {
        'claim' => failing.claim(scope, payment),
        'attach' => failing.attach(scope, 'request', reference),
        _ => failing.clear(scope, 'request'),
      }, throwsStateError);
    });

    test('$operation checks secure storage readback before proceeding', () async {
      final storage = _SecureStorage();
      when(() => storage.read(key: scope)).thenAnswer((_) async =>
        operation == 'claim' ? null : jsonEncode(payment.toJson()),
      );
      when(() => storage.write(key: scope, value: any(named: 'value')))
        .thenAnswer((_) async {});
      when(() => storage.delete(key: scope)).thenAnswer((_) async {});
      final failing = CortinaPendingStore(project: 'https://test.invalid', storage: storage);
      await expectLater(switch (operation) {
        'claim' => failing.claim(scope, payment),
        'attach' => failing.attach(scope, 'request', reference),
        _ => failing.clear(scope, 'request'),
      }, throwsStateError);
    });
  }
}
