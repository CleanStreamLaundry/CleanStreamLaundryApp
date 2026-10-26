@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clean_stream_laundry_app/logic/models/wallet_ledger_entry.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Client extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

class _Payment extends Mock implements PaymentService {}

void main() {
  late HttpServer server;
  late SupabaseClient transport;
  late SupabaseWalletService service;
  late _Auth auth;
  late List<Uri> requests;
  late List<Map<String, dynamic>> response;
  Future<void>? delayResponse;
  final since = DateTime.utc(2026, 8, 30);

  User user(String id) => User(
    id: id,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '',
  );
  Future<List<WalletLedgerEntry>> page({
    WalletLedgerEntry? before,
    bool rewards = false,
  }) => service.getLedger(
    userId: 'user-a',
    walletAccountId: 'wallet-a',
    since: since,
    before: before,
    rewardsOnly: rewards,
  );

  setUp(() async {
    requests = [];
    response = [];
    delayResponse = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      await delayResponse;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    transport = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-key',
    );
    final client = _Client();
    auth = _Auth();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(user('user-a'));
    when(() => client.from(any())).thenAnswer(
      (call) => transport.from(call.positionalArguments.single as String),
    );
    service = SupabaseWalletService(client: client, paymentService: _Payment());
  });

  tearDown(() async {
    await transport.dispose();
    await server.close(force: true);
  });

  test('one bounded ledger request, no hidden balance lookup', () async {
    await page();
    expect(requests, hasLength(1));
    expect(requests.single.path, '/rest/v1/wallet_ledger_entries');
    final query = requests.single.queryParameters;
    expect(query['wallet_account_id'], 'eq.wallet-a');
    expect(query['created_at'], 'gt.${since.toIso8601String()}');
    expect(query['limit'], '${WalletService.ledgerPageSize + 1}');
    expect(query['order'], 'created_at.desc.nullslast,id.desc.nullslast');
  });

  test(
    'cursor orders equal timestamps by id; rewards retain both filters',
    () async {
      final before = WalletLedgerEntry(
        id: 42,
        entryType: 'load_bonus',
        amountCents: 500,
        paidAmountCents: 0,
        promoAmountCents: 500,
        createdAt: DateTime.utc(2026, 9, 20, 12),
      );
      await page(before: before, rewards: true);
      final filters = requests.single.queryParametersAll['or']!;
      expect(filters, hasLength(2));
      expect(
        filters,
        contains(
          '(created_at.lt.2026-09-20T12:00:00.000Z,'
          'and(created_at.eq.2026-09-20T12:00:00.000Z,id.lt.42))',
        ),
      );
      expect(
        filters,
        contains(
          '(entry_type.eq.load_bonus,'
          'and(amount_cents.gt.0,promo_amount_cents.gt.0))',
        ),
      );
    },
  );

  test('mismatched user never issues an old-wallet request', () async {
    when(() => auth.currentUser).thenReturn(user('user-b'));
    await expectLater(page(), throwsStateError);
    expect(requests, isEmpty);
  });

  test('rejects completion after account change', () async {
    final gate = Completer<void>();
    delayResponse = gate.future;
    final pending = page();
    final rejected = expectLater(pending, throwsStateError);
    while (requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    when(() => auth.currentUser).thenReturn(user('user-b'));
    gate.complete();
    await rejected;
    expect(requests, hasLength(1));
  });

  test('empty wallet account does not issue a ledger query', () async {
    expect(
      await service.getLedger(
        userId: 'user-a',
        walletAccountId: '',
        since: since,
      ),
      isEmpty,
    );
    expect(requests, isEmpty);
  });

  test(
    'financial getBalance stays fresh and queries the signed-in user',
    () async {
      response = [
        {
          'wallet_account_id': 'wallet-a',
          'status': 'active',
          'paid_balance_cents': 1250,
          'promo_balance_cents': 500,
          'total_balance_cents': 1750,
        },
      ];
      expect((await service.getBalance()).totalBalanceCents, 1750);
      response.single['total_balance_cents'] = 2000;
      expect((await service.getBalance()).totalBalanceCents, 2000);
      expect(requests, hasLength(2));
      expect(
        requests.every(
          (uri) =>
              uri.path == '/rest/v1/wallet_balances' &&
              uri.queryParameters['user_id'] == 'eq.user-a',
        ),
        isTrue,
      );
    },
  );
}
