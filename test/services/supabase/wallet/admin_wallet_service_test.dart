@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clean_stream_laundry_app/services/supabase/supabase_admin_wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/topup_refunds/fixtures.dart';

class _Client extends SupabaseClient {
  _Client(super.url, super.key)
    : super(authOptions: const AuthClientOptions(autoRefreshToken: false));
  void Function()? beforeRpc;
  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    get = false,
  }) {
    beforeRpc?.call();
    return super.rpc<T>(fn, params: params, get: get);
  }
}

class _MockClient extends Mock implements SupabaseClient {}
class _MockAuth extends Mock implements GoTrueClient {}

const walletId = '33333333-3333-4333-8333-333333333333';
const createdAt = '2026-09-30T10:00:00.123456+00:00';
typedef _Request = ({String path, String method, String? bearer, String? apikey, Object? body});

String _searchId(int index) => '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';

Map<String, dynamic> _balance([String id = walletId]) => {
  'wallet_account_id': id,
  'user_id': customerB,
  'status': 'active',
  'paid_balance_cents': 12345,
  'promo_balance_cents': 500,
  'total_balance_cents': 12845,
};

Map<String, dynamic> _search({int page = 1, int count = 1, int total = 1}) => {
  'items': List.generate(count, (i) => _balance(_searchId((page - 1) * 25 + i))),
  'page': page,
  'pageSize': 25,
  'total': total,
  'nextCursor': total > page * 25 ? _searchId(page * 25 - 1) : null,
};

Map<String, dynamic> _detail({int page = 1, int loads = 1, bool moreLoads = false}) => {
  'balance': _balance(),
  'loads': List.generate(loads, (i) => {
    'id': 1000 - (page - 1) * 100 - i,
    'created_at': createdAt,
    'wallet_account_id': walletId,
    'amount_cents': 2300,
  }),
  'redemptions': page == 1 ? [{'id': 81, 'amount_cents': 750}] : [],
  'ledger': page == 1 ? [{'id': 82, 'amount_cents': -750}] : [],
  'page': page,
  'pageSize': 100,
  'hasMore': {'loads': moreLoads, 'redemptions': false, 'ledger': false},
  'nextCursor': {
    'loads': moreLoads ? <String, dynamic>{'createdAt': createdAt, 'id': '${1000 - (page - 1) * 100 - (loads - 1)}'} : null,
    'redemptions': null,
    'ledger': null,
  },
};

void main() {
  late HttpServer server;
  late _Client client;
  late SupabaseAdminWalletService service;
  late Session session;
  late List<_Request> requests;
  Object? response;
  Future<Object?> Function(_Request)? respond;
  Future<void> Function(HttpRequest)? authResponse;
  int status = 200;

  setUp(() async {
    requests = [];
    response = _search();
    respond = null;
    authResponse = null;
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path.startsWith('/auth/')) {
        if (authResponse != null) {
          await authResponse!(request);
        } else {
          expect(request.uri.path, '/auth/v1/logout');
          request.response.statusCode = 204;
          await request.response.close();
        }
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      final captured = (
        path: request.uri.path,
        method: request.method,
        bearer: request.headers.value('authorization'),
        apikey: request.headers.value('apikey'),
        body: body.isEmpty ? null : jsonDecode(body),
      );
      requests.add(captured);
      final data = respond == null ? response : await respond!(captured);
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(data));
      await request.response.close();
    });
    client = _Client('http://127.0.0.1:${server.port}', 'synthetic-public-key');
    await client.auth.setInitialSession(jsonEncode(refundSession().toJson()));
    await Future<void>.delayed(Duration.zero);
    session = client.auth.currentSession!;
    service = SupabaseAdminWalletService(client: client);
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('real SDK search sends captured bearer and only canonical RPC', () async {
    response = {'items': [_balance()], 'page': 1, 'pageSize': 25, 'total': 1, 'nextCursor': null};
    expect(await service.searchWallets('  pi_abc,%_  '), [_balance()]);
    expect(requests.single.path, '/rest/v1/rpc/admin_wallet_read');
    expect(requests.single.method, 'POST');
    expect(requests.single.apikey, 'synthetic-public-key');
    expect(requests.single.bearer, 'Bearer ${session.accessToken}');
    expect(requests.single.body, {
      'action': 'search',
      'payload': {'query': 'pi_abc,%_', 'page': 1},
    });
    expect(client.getChannels(), isEmpty);
  });

  test('empty search keeps the existing 25-row bound without continuation', () async {
    response = _search(count: 25, total: 101);
    expect(await service.searchWallets('  '), hasLength(25));
    expect(requests, hasLength(1));
    expect((requests.single.body as Map)['payload'], {'query': '', 'page': 1});
  });

  test('nonempty search continues at most four pages preserving 100-row bound', () async {
    respond = (request) async => _search(
      page: ((request.body as Map)['payload'] as Map)['page'] as int,
      count: 25,
      total: 126,
    );
    final rows = await service.searchWallets('customer');
    expect(rows, hasLength(100));
    expect(rows.first['wallet_account_id'], _searchId(0));
    expect(rows.last['wallet_account_id'], _searchId(99));
    expect(requests, hasLength(4));
    expect(requests.map((r) => r.bearer), everyElement('Bearer ${session.accessToken}'));
  });

  test('search stops at its actual last page and empty results stay empty', () async {
    respond = (request) async {
      final page = ((request.body as Map)['payload'] as Map)['page'] as int;
      return _search(page: page, count: page == 1 ? 25 : 2, total: 27);
    };
    expect(await service.searchWallets('customer'), hasLength(27));
    expect(requests, hasLength(2));
    respond = null;
    response = _search(count: 0, total: 0);
    expect(await service.searchWallets('none'), isEmpty);
  });

  test('detail uses wallet ID only and preserves response shape and signed cents', () async {
    response = _detail();
    final detail = await service.getWalletDetail(walletId);
    expect(detail.keys, unorderedEquals(['balance', 'loads', 'redemptions', 'ledger']));
    expect(detail['balance'], _balance());
    expect((detail['ledger'] as List).single['amount_cents'], -750);
    expect((detail['loads'] as List).single['amount_cents'], 2300);
    expect(requests.single.body, {
      'action': 'detail',
      'payload': {'walletId': walletId, 'page': 1},
    });
    expect(requests.single.path, '/rest/v1/rpc/admin_wallet_read');
  });

  test('detail completes only after every collection continuation finishes', () async {
    respond = (request) async {
      final page = ((request.body as Map)['payload'] as Map)['page'] as int;
      final data = _detail(page: page, loads: page == 1 ? 100 : 3, moreLoads: page == 1);
      data['ledger'] = List.generate(page == 1 ? 100 : 1,
        (i) => {'id': 1000 - (page - 1) * 100 - i, 'created_at': createdAt});
      (data['hasMore'] as Map)['ledger'] = page == 1;
      (data['nextCursor'] as Map)['ledger'] = page == 1 ? {'createdAt': createdAt, 'id': '901'} : null;
      return data;
    };
    final detail = await service.getWalletDetail(walletId);
    expect(detail['loads'], hasLength(103));
    expect((detail['loads'] as List).last['id'], 898);
    expect(detail['redemptions'], hasLength(1));
    expect(detail['ledger'], hasLength(101));
    expect(requests, hasLength(2));
    expect(requests.map((r) => r.bearer), everyElement('Bearer ${session.accessToken}'));
    expect(((requests[1].body as Map)['payload'] as Map)['after'], {
      'loads': {'createdAt': createdAt, 'id': '901'},
      'redemptions': null,
      'ledger': {'createdAt': createdAt, 'id': '901'},
    });
  });

  test('insert between offset pages rejects repeated ledger ID instead of inflated history', () async {
    respond = (request) async {
      final page = ((request.body as Map)['payload'] as Map)['page'] as int;
      final data = _detail(page: page, loads: 0);
      data['redemptions'] = [];
      // Initial history101..1: page1 is101..2. A new102 shifts page2
      // to2,1. Keep balance unchanged to exercise ID detection itself.
      data['ledger'] = page == 1
          ? List.generate(100, (i) => {'id': 101 - i, 'amount_cents': 1, 'created_at': createdAt})
          : [{'id': 2, 'amount_cents': 1}, {'id': 1, 'amount_cents': 1}];
      (data['hasMore'] as Map)['ledger'] = page == 1;
      (data['nextCursor'] as Map)['ledger'] = page == 1 ? {'createdAt': createdAt, 'id': '2'} : null;
      return data;
    };
    await expectLater(service.getWalletDetail(walletId),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('refresh needed'))));
    expect(requests, hasLength(2));
    expect(requests.map((r) => r.path), everyElement('/rest/v1/rpc/admin_wallet_read'));
  });

  for (final collection in ['loads', 'redemptions', 'ledger']) {
    test('$collection rejects duplicate numeric identities without deduplicating silently', () async {
      response = _detail()..[collection] = [{'id': 1}, {'id': '01'}];
      await expectLater(service.getWalletDetail(walletId),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('refresh needed'))));
      expect(requests, hasLength(1));
    });
  }

  for (final invalidId in [null, 1.5]) {
    test('invalid history identity $invalidId requests refresh', () async {
      response = _detail()..['ledger'] = [{'id': invalidId}];
      await expectLater(service.getWalletDetail(walletId),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('refresh needed'))));
      expect(requests, hasLength(1));
    });
  }

  test('material balance change between detail pages rejects the whole read', () async {
    respond = (request) async {
      final page = ((request.body as Map)['payload'] as Map)['page'] as int;
      final data = _detail(page: page, loads: page == 1 ? 100 : 1, moreLoads: page == 1);
      if (page == 2) {
        (data['balance'] as Map)['paid_balance_cents'] = 12346;
        (data['balance'] as Map)['total_balance_cents'] = 12846;
      }
      return data;
    };
    await expectLater(service.getWalletDetail(walletId),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('refresh needed'))));
    expect(requests, hasLength(2));
  });

  test('shifted search pages reject repeated wallet identity', () async {
    respond = (request) async {
      final page = ((request.body as Map)['payload'] as Map)['page'] as int;
      final data = _search(page: page, count: 25, total: 50);
      if (page == 2) (data['items'] as List)[0] = _balance(_searchId(24));
      return data;
    };
    await expectLater(service.searchWallets('customer'),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('refresh needed'))));
    expect(requests, hasLength(2));
  });

  test('keyset continuation survives an insert before the first ledger page', () async {
    respond = (request) async {
      final payload = (request.body as Map)['payload'] as Map;
      final page = payload['page'] as int;
      final data = _detail(page: page, loads: 0);
      data['redemptions'] = [];
      if (page == 1) {
        expect(payload.containsKey('after'), isFalse);
        data['ledger'] = List.generate(100, (i) => {'id': 101 - i, 'created_at': createdAt});
      } else {
        expect(payload['after'], {
          'loads': null, 'redemptions': null,
          'ledger': {'createdAt': createdAt, 'id': '2'},
        });
        // Insert102 is ahead of the captured cursor. Strictly older rows
        // return1, not the duplicate2 that an offset query would return.
        data['ledger'] = [{'id': 1, 'created_at': createdAt}];
      }
      (data['hasMore'] as Map)['ledger'] = page == 1;
      (data['nextCursor'] as Map)['ledger'] = page == 1 ? {'createdAt': createdAt, 'id': '2'} : null;
      return data;
    };
    final detail = await service.getWalletDetail(walletId);
    final ids = (detail['ledger'] as List).map((row) => row['id']).toList();
    expect(ids, hasLength(101));
    expect(ids.toSet(), hasLength(101));
    expect(ids.first, 101);
    expect(ids.last, 1);
    expect(ids, isNot(contains(102)));
    expect(requests, hasLength(2));
  });

  test('search uses nextCursor rather than a changing advisory total', () async {
    respond = (request) async {
      final payload = (request.body as Map)['payload'] as Map;
      if (payload['page'] == 1) {
        return _search(count: 25, total: 26);
      }
      expect(payload['after'], _searchId(24));
      return _search(page: 2, count: 2, total: 0);
    };
    expect(await service.searchWallets('customer'), hasLength(27));
    expect(requests, hasLength(2));
  });

  test('detail continuation preserves microseconds and large decimal ID bytes', () async {
    respond = (request) async {
      final payload = (request.body as Map)['payload'] as Map;
      final page = payload['page'] as int;
      final data = _detail(page: page, loads: page == 1 ? 100 : 1, moreLoads: page == 1);
      if (page == 1) {
        data['loads'] = List.generate(100, (i) => {'id': 9007199254741092 - i, 'created_at': createdAt});
        (data['nextCursor'] as Map)['loads'] = {'createdAt': createdAt, 'id': '9007199254740993'};
      } else {
        expect((payload['after'] as Map)['loads'], {'createdAt': createdAt, 'id': '9007199254740993'});
        data['loads'] = [{'id': 9007199254740992, 'created_at': createdAt}];
      }
      return data;
    };
    expect((await service.getWalletDetail(walletId))['loads'], hasLength(101));
    expect(requests, hasLength(2));
  });

  test('an exhausted collection cannot restart on a later page', () async {
    respond = (request) async {
      final page = ((request.body as Map)['payload'] as Map)['page'] as int;
      final data = _detail(page: page, loads: page == 1 ? 100 : 1, moreLoads: page == 1);
      if (page == 2) data['ledger'] = [{'id': 9999}];
      return data;
    };
    await expectLater(service.getWalletDetail(walletId),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('refresh needed'))));
    expect(requests, hasLength(2));
  });

  for (final invalid in ['missing key', 'wrong timestamp', 'numeric id', 'wrong last id', 'unexpected cursor']) {
    test('malformed detail cursor $invalid is rejected without continuation', () async {
      final data = _detail(loads: 100, moreLoads: true);
      final cursors = data['nextCursor'] as Map;
      switch (invalid) {
        case 'missing key': cursors.remove('ledger');
        case 'wrong timestamp': (cursors['loads'] as Map)['createdAt'] = 'not a timestamp';
        case 'numeric id': (cursors['loads'] as Map)['id'] = 901;
        case 'wrong last id': (cursors['loads'] as Map)['id'] = '902';
        default: (data['hasMore'] as Map)['loads'] = false;
      }
      response = data;
      await expectLater(service.getWalletDetail(walletId), throwsFormatException);
      expect(requests, hasLength(1));
    });
  }

  test('search cursor must match the final row before continuation', () async {
    response = _search(count: 25, total: 26)..['nextCursor'] = _searchId(23);
    await expectLater(service.searchWallets('customer'), throwsFormatException);
    expect(requests, hasLength(1));
  });

  for (final code in ['PT401', 'PT403', 'PT404', '22023']) {
    test('$code is propagated without direct-table fallback or retry', () async {
      status = code == 'PT401' ? 401 : code == 'PT403' ? 403 : code == 'PT404' ? 404 : 400;
      response = {'code': code, 'message': 'synthetic_denial'};
      await expectLater(service.getWalletDetail(walletId),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', code)));
      expect(requests, hasLength(1));
      expect(requests.single.path, '/rest/v1/rpc/admin_wallet_read');
    });
  }

  test('second-page failure rejects the entire read instead of partial detail', () async {
    respond = (request) async {
      final page = ((request.body as Map)['payload'] as Map)['page'] as int;
      if (page == 1) return _detail(loads: 100, moreLoads: true);
      status = 403;
      return {'code': 'PT403', 'message': 'admin_access_changed'};
    };
    await expectLater(service.getWalletDetail(walletId), throwsA(isA<PostgrestException>()));
    expect(requests, hasLength(2));
  });

  for (final invalid in ['missing', 'expired']) {
    test('$invalid session rejects before any wallet dispatch', () async {
      final mock = _MockClient(), auth = _MockAuth();
      final expired = refundSession(seconds: -60);
      when(() => mock.auth).thenReturn(auth);
      when(() => auth.currentSession).thenReturn(invalid == 'missing' ? null : expired);
      when(() => auth.currentUser).thenReturn(expired.user);
      await expectLater(SupabaseAdminWalletService(client: mock).searchWallets(''), throwsStateError);
      verifyNever(() => mock.rpc<dynamic>(any(), params: any(named: 'params')));
      expect(requests, isEmpty);
    });
  }

  for (final change in ['signout', 'A-B', 'A-B-A']) {
    test('late response after $change is discarded', () async {
      final gate = Completer<void>();
      respond = (_) async { await gate.future; return _detail(loads: 100, moreLoads: true); };
      final result = expectLater(service.getWalletDetail(walletId), throwsStateError);
      while (requests.isEmpty) { await Future<void>.delayed(Duration.zero); }
      if (change == 'signout') {
        await client.auth.signOut(scope: SignOutScope.local);
      } else {
        await client.auth.setInitialSession(jsonEncode(refundSession(id: customerB).toJson()));
        if (change == 'A-B-A') await client.auth.setInitialSession(jsonEncode(session.toJson()));
      }
      gate.complete();
      await result;
      expect(requests, hasLength(1));
      expect(requests.single.bearer, 'Bearer ${session.accessToken}');
    });
  }

  test('captured A bearer survives actual SDK refresh and B sign-in', () async {
    final refreshing = Completer<void>(), release = Completer<void>();
    var authCalls = 0;
    authResponse = (request) async {
      await utf8.decoder.bind(request).join();
      authCalls++;
      final password = request.uri.queryParameters['grant_type'] == 'password';
      if (!password) { refreshing.complete(); await release.future; }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(refundSession(id: password ? customerB : customerA).toJson()));
      await request.response.close();
    };
    client.beforeRpc = () {
      unawaited(client.auth.setInitialSession(jsonEncode(refundSession(seconds: 20).toJson())));
    };
    final result = expectLater(service.searchWallets(''), throwsStateError);
    await refreshing.future.timeout(const Duration(seconds: 2));
    await client.auth.signInWithPassword(email: 'b@synthetic.invalid', password: 'synthetic-password');
    release.complete();
    await result;
    expect(authCalls, 2);
    expect(requests, hasLength(1));
    expect(requests.single.bearer, 'Bearer ${session.accessToken}');
    expect(client.auth.currentUser!.id, customerB);
  });

  for (final invalid in ['envelope', 'page', 'size', 'items', 'count', 'missing cursor', 'oversized']) {
    test('malformed search $invalid fails closed', () async {
      final data = _search();
      response = switch (invalid) {
        'envelope' => [],
        'page' => data..['page'] = 2,
        'size' => data..['pageSize'] = 100,
        'items' => data..['items'] = [1],
        'count' => data..['total'] = '1',
        'missing cursor' => data..remove('nextCursor'),
        _ => _search(count: 26, total: 26),
      };
      await expectLater(service.searchWallets('x'), throwsFormatException);
      expect(requests, hasLength(1));
    });
  }

  for (final invalid in ['foreign wallet', 'missing rows', 'continuation', 'short page']) {
    test('malformed detail $invalid fails closed', () async {
      final data = _detail();
      response = switch (invalid) {
        'foreign wallet' => data..['balance'] = _balance('another-wallet'),
        'missing rows' => data..remove('ledger'),
        'continuation' => data..['hasMore'] = {'loads': false},
        _ => _detail(moreLoads: true),
      };
      await expectLater(service.getWalletDetail(walletId), throwsFormatException);
      expect(requests, hasLength(1));
    });
  }

  test('one deadline spans pages and never returns partial data', () async {
    final finish = Completer<void>();
    respond = (request) async {
      final page = ((request.body as Map)['payload'] as Map)['page'] as int;
      if (page == 1) {
        await Future<void>.delayed(const Duration(seconds: 6));
        return _detail(loads: 100, moreLoads: true);
      }
      await finish.future;
      return _detail(page: 2);
    };
    final clock = Stopwatch()..start();
    try {
      await expectLater(service.getWalletDetail(walletId), throwsA(isA<TimeoutException>()));
      expect(clock.elapsed, lessThan(const Duration(seconds: 14)));
      expect(requests, hasLength(2));
    } finally {
      finish.complete();
      await Future<void>.delayed(Duration.zero);
    }
  }, timeout: const Timeout(Duration(seconds: 20)));

  final writes = <String, Future<void> Function(SupabaseAdminWalletService)>{
    'adjust': (s) => s.adjustWallet(walletAccountId: walletId,
      amountCents: 750, paidAmountCents: 0, promoAmountCents: 750, note: 'promo note'),
    'lock': (s) => s.lockWallet(walletId, true),
    'cash': (s) => s.recordCashRedemptionOrStripeRefund(walletAccountId: walletId,
      amountCents: -500, note: 'cash note'),
    'complaint': (s) => s.recordDeletedAccountComplaint(walletAccountId: walletId,
      note: 'complaint note'),
  };

  for (final entry in writes.entries) {
    for (final invalid in ['missing', 'expired']) {
      test('write ${entry.key} rejects $invalid caller before dispatch', () async {
        final mock = _MockClient(), auth = _MockAuth();
        final expired = refundSession(seconds: -60);
        when(() => mock.auth).thenReturn(auth);
        when(() => auth.currentSession).thenReturn(invalid == 'missing' ? null : expired);
        when(() => auth.currentUser).thenReturn(expired.user);
        await expectLater(entry.value(SupabaseAdminWalletService(client: mock)), throwsStateError);
        verifyNever(() => mock.rpc<dynamic>(any(), params: any(named: 'params')));
        expect(requests, isEmpty);
      });
    }

    for (final change in ['signout', 'A-B', 'A-B-A']) {
      test('write ${entry.key} discards late $change completion without replay', () async {
        final sent = Completer<void>(), release = Completer<void>();
        respond = (_) async {
          sent.complete();
          await release.future;
          return null;
        };
        final result = expectLater(entry.value(service), throwsStateError);
        await sent.future.timeout(const Duration(seconds: 2));
        if (change == 'signout') {
          await client.auth.signOut(scope: SignOutScope.local);
        } else {
          await client.auth.setInitialSession(jsonEncode(refundSession(id: customerB).toJson()));
          if (change == 'A-B-A') {
            await client.auth.setInitialSession(jsonEncode(session.toJson()));
          }
        }
        release.complete();
        await result;
        expect(requests, hasLength(1));
        expect(requests.single.bearer, 'Bearer ${session.accessToken}');
      });
    }

    test('write ${entry.key} pins A bearer through actual SDK refresh and B sign-in', () async {
      final refreshing = Completer<void>(), release = Completer<void>();
      var authCalls = 0;
      response = null;
      authResponse = (request) async {
        await utf8.decoder.bind(request).join();
        authCalls++;
        final password = request.uri.queryParameters['grant_type'] == 'password';
        if (!password) { refreshing.complete(); await release.future; }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(refundSession(id: password ? customerB : customerA).toJson()));
        await request.response.close();
      };
      client.beforeRpc = () {
        unawaited(client.auth.setInitialSession(jsonEncode(refundSession(seconds: 20).toJson())));
      };
      final result = expectLater(entry.value(service), throwsStateError);
      await refreshing.future.timeout(const Duration(seconds: 2));
      await client.auth.signInWithPassword(email: 'b@synthetic.invalid', password: 'synthetic-password');
      release.complete();
      await result;
      expect(authCalls, 2);
      expect(requests, hasLength(1));
      expect(requests.single.bearer, 'Bearer ${session.accessToken}');
      expect(requests.single.apikey, 'synthetic-public-key');
      expect(client.auth.currentUser!.id, customerB);
    });
  }

  test('write server rejection propagates unchanged without retry', () async {
    status = 403;
    response = {'code': 'PT403', 'message': 'admin_access_changed'};
    await expectLater(writes['adjust']!(service), throwsA(
      isA<PostgrestException>().having((error) => error.code, 'code', 'PT403'),
    ));
    expect(requests, hasLength(1));
  });

  test('all existing write names parameters and integer-cent conversions remain unchanged', () async {
    response = null;
    await service.adjustWallet(walletAccountId: walletId, amountCents: 750,
      paidAmountCents: 0, promoAmountCents: 750, note: 'promo note');
    await service.lockWallet(walletId, true);
    await service.lockWallet(walletId, false);
    await service.recordCashRedemptionOrStripeRefund(walletAccountId: walletId,
      amountCents: -500, note: 'cash note');
    await service.recordDeletedAccountComplaint(walletAccountId: walletId, note: 'complaint note');
    expect(requests.map((r) => r.bearer), everyElement('Bearer ${session.accessToken}'));
    expect(requests.map((r) => r.apikey), everyElement('synthetic-public-key'));
    expect(requests.map((r) => r.path), [
      '/rest/v1/rpc/admin_adjust_wallet',
      '/rest/v1/rpc/admin_set_wallet_status',
      '/rest/v1/rpc/admin_set_wallet_status',
      '/rest/v1/rpc/admin_record_legal_cash_redemption',
      '/rest/v1/rpc/record_deleted_account_complaint',
    ]);
    expect(requests.map((r) => r.body), [
      {'wallet_id': walletId, 'amount_cents': 750, 'paid_amount_cents': 0,
        'promo_amount_cents': 750, 'adjustment_note': 'promo note'},
      {'wallet_id': walletId, 'new_status': 'locked', 'status_note': 'Wallet locked by admin'},
      {'wallet_id': walletId, 'new_status': 'active', 'status_note': 'Wallet unlocked by admin'},
      {'wallet_id': walletId, 'amount_cents': 500, 'stripe_refund_id': null, 'redemption_note': 'cash note'},
      {'wallet_id': walletId, 'complaint_note': 'complaint note', 'resolution': 'denied'},
    ]);
  });
}
