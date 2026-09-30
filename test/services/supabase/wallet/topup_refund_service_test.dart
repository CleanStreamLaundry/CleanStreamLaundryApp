@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/topup_refunds/fixtures.dart';

class _Payment extends Mock implements PaymentService {}

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

void main() {
  late HttpServer server;
  late _Client client;
  late SupabaseWalletService service;
  late Session session;
  late List<({String path, String? bearer, Object? body})> requests;
  Object? response;
  Future<void>? delayResponse;
  int status = 200;
  Future<void> Function(HttpRequest)? authResponse;

  setUp(() async {
    requests = [];
    response = [];
    status = 200;
    delayResponse = null;
    authResponse = null;
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
      requests.add((
        path: request.uri.path,
        bearer: request.headers.value('authorization'),
        body: jsonDecode(await utf8.decoder.bind(request).join()),
      ));
      await delayResponse;
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = _Client('http://127.0.0.1:${server.port}', 'synthetic-public-key');
    await client.auth.setInitialSession(jsonEncode(refundSession().toJson()));
    await Future<void>.delayed(Duration.zero);
    session = client.auth.currentSession!;
    service = SupabaseWalletService(client: client, paymentService: _Payment());
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'top-ups use captured bearer, lossless cursor and only customer RPC',
    () async {
      response = [topupJson()];
      final result = await service.listRefundableTopups(
        session: session,
        beforeLoadId: '9223372036854775807',
      );
      expect(result.single.loadId, '9007199254740993');
      expect(
        requests.single.path,
        '/rest/v1/rpc/list_voluntary_topup_refund_topups',
      );
      expect(requests.single.bearer, 'Bearer ${session.accessToken}');
      expect(requests.single.body, {'p_before_load_id': '9223372036854775807'});
      expect(client.getChannels(), isEmpty);
    },
  );
  test(
    'request cursor uses timestamp plus UUID, no customer argument',
    () async {
      final before = TopupRefund.fromJson(refundJson());
      response = [refundJson()];
      await service.listTopupRefunds(session: session, before: before);
      expect(requests.single.path, '/rest/v1/rpc/list_voluntary_topup_refunds');
      expect(requests.single.body, {
        'p_before': before.requestedAt.toIso8601String(),
        'p_before_id': before.id,
      });
    },
  );
  test(
    'request reserves full server amount without destination or amount overrides',
    () async {
      response = refundJson();
      final result = await service.requestTopupRefund(
        session: session,
        loadId: '9007199254740993',
      );
      expect(result.status, TopupRefundStatus.requested);
      expect(
        requests.single.path,
        '/rest/v1/rpc/request_voluntary_topup_refund',
      );
      expect(requests.single.body, {'p_load_id': '9007199254740993'});
    },
  );
  for (final invalid in ['wrong actor', 'expired', 'missing']) {
    test('$invalid session blocks before dispatch', () async {
      if (invalid == 'wrong actor') {
        await client.auth.setInitialSession(
          jsonEncode(refundSession(id: customerB).toJson()),
        );
      } else if (invalid == 'expired') {
        session = refundSession(seconds: -1);
      } else {
        await client.auth.signOut(scope: SignOutScope.local);
      }
      await expectLater(
        service.requestTopupRefund(session: session, loadId: '1'),
        throwsStateError,
      );
      expect(requests, isEmpty);
    });
  }
  test('malformed input never dispatches', () async {
    await expectLater(
      service.requestTopupRefund(session: session, loadId: '01'),
      throwsFormatException,
    );
    await expectLater(
      service.listTopupRefunds(
        session: session,
        before: TopupRefund.fromJson(refundJson(customer: customerB)),
      ),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });
  for (final kind in [
    'foreign customer',
    'wrong load',
    'unknown status',
    'unconfirmed success',
  ]) {
    test('rejects $kind mutation response', () async {
      response = switch (kind) {
        'foreign customer' => refundJson(customer: customerB),
        'wrong load' => refundJson(load: '2'),
        'unknown status' => refundJson(status: 'paid'),
        _ => refundJson(status: 'succeeded')..['completed_at'] = null,
      };
      await expectLater(
        service.requestTopupRefund(
          session: session,
          loadId: '9007199254740993',
        ),
        throwsFormatException,
      );
      expect(requests, hasLength(1));
    });
  }
  test('rejects oversized or non-list pages', () async {
    response = List.generate(101, (_) => topupJson());
    await expectLater(
      service.listRefundableTopups(session: session),
      throwsFormatException,
    );
    response = {'data': []};
    await expectLater(
      service.listTopupRefunds(session: session),
      throwsFormatException,
    );
  });
  test('nested foreign-customer operation is rejected', () async {
    response = [
      topupJson(
        reason: 'already_requested',
        refund: refundJson(customer: customerB),
      ),
    ];
    await expectLater(
      service.listRefundableTopups(session: session),
      throwsFormatException,
    );
  });
  test('PT409 is preserved without retrying mutation', () async {
    status = 409;
    response = {'code': 'PT409', 'message': 'refund_window_closed'};
    await expectLater(
      service.requestTopupRefund(session: session, loadId: '1'),
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', 'PT409')),
    );
    expect(requests, hasLength(1));
  });
  test('late response after A-B-A cannot be accepted', () async {
    final gate = Completer<void>();
    delayResponse = gate.future;
    response = refundJson();
    final pending = expectLater(
      service.requestTopupRefund(session: session, loadId: '9007199254740993'),
      throwsStateError,
    );
    while (requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await client.auth.setInitialSession(
      jsonEncode(refundSession(id: customerB).toJson()),
    );
    await client.auth.setInitialSession(jsonEncode(session.toJson()));
    gate.complete();
    await pending;
    expect(requests.single.bearer, 'Bearer ${session.accessToken}');
  });
  test('A bearer survives real SDK awaited refresh and B sign-in', () async {
    final refreshing = Completer<void>();
    final release = Completer<void>();
    var authCalls = 0;
    authResponse = (request) async {
      await utf8.decoder.bind(request).join();
      authCalls++;
      final password = request.uri.queryParameters['grant_type'] == 'password';
      if (!password) {
        refreshing.complete();
        await release.future;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          refundSession(id: password ? customerB : customerA).toJson(),
        ),
      );
      await request.response.close();
    };
    response = refundJson();
    client.beforeRpc = () {
      unawaited(
        client.auth.setInitialSession(
          jsonEncode(refundSession(seconds: 20).toJson()),
        ),
      );
    };
    final pending = expectLater(
      service.requestTopupRefund(session: session, loadId: '9007199254740993'),
      throwsStateError,
    );
    await refreshing.future.timeout(const Duration(seconds: 2));
    await client.auth.signInWithPassword(
      email: 'b@synthetic.invalid',
      password: 'synthetic-password',
    );
    release.complete();
    await pending;
    expect(authCalls, 2);
    expect(requests, hasLength(1));
    expect(requests.single.bearer, 'Bearer ${session.accessToken}');
    expect(client.auth.currentUser!.id, customerB);
  });
}
