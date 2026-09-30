import 'dart:async';

import 'package:clean_stream_laundry_app/services/supabase/supabase_transaction_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mocks.dart';

class FakeCreditResponse extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  FakeCreditResponse({this.error});

  final Object? error;

  @override
  Future<U> then<U>(
    FutureOr<U> Function(dynamic) onValue, {
    Function? onError,
  }) {
    final response = error == null
        ? Future<dynamic>.value({
            'amount': 4,
            'refund_id': 9,
            'status': 'pending',
          })
        : Future<dynamic>.error(error!);
    return response.then(onValue, onError: onError);
  }
}

void main() {
  late SupabaseMock client;
  late GoTrueMock auth;
  late QueryBuilderMock query;
  late SupabaseTransactionService service;

  Map<String, dynamic> payment(int id, String description, {String? status}) =>
      {
        'id': id,
        'amount': 4,
        'description': description,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'requested_refund': false,
        'cortina_status': status,
      };

  setUp(() {
    client = SupabaseMock();
    auth = GoTrueMock();
    query = QueryBuilderMock();
    service = SupabaseTransactionService(client: client);
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'customer',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
      ),
    );
    when(() => client.from('transactions')).thenAnswer((_) => query);
    when(() => query.select(any())).thenAnswer(
      (_) => FakeFilterBuilder([
        {'amount': 99, 'cortina_vend_session_id': 'vend-session'},
      ]),
    );
    when(
      () => client.rpc(any(), params: any(named: 'params')),
    ).thenAnswer((_) => FakeCreditResponse());
  });

  test(
    'uses the atomic RPC and its amount without direct refund writes',
    () async {
      final amount = await service.recordRefundRequest(
        transaction_id: '7',
        description: 'Washer did not finish',
      );

      expect(amount, '4');
      verify(
        () => client.rpc(
          'request_cortina_loyalty_credit',
          params: {
            'target_transaction_id': 7,
            'request_description': 'Washer did not finish',
          },
        ),
      ).called(1);
      verifyNever(() => query.update(any()));
      verifyNever(() => client.from('Refunds'));
      verifyNever(
        () => client.rpc(
          'increment_user_refund_attempts',
          params: any(named: 'params'),
        ),
      );
    },
  );

  test('server rejection is not reported as a successful request', () async {
    when(() => client.rpc(any(), params: any(named: 'params'))).thenAnswer(
      (_) => FakeCreditResponse(
        error: const PostgrestException(message: 'Vend is not eligible'),
      ),
    );
    await expectLater(
      service.recordRefundRequest(transaction_id: '7', description: 'Issue'),
      throwsA(isA<PostgrestException>()),
    );
    verifyNever(() => query.update(any()));
    verifyNever(() => client.from('Refunds'));
  });

  test(
    'filters reversed vends and wallet loads without misaligning IDs',
    () async {
      when(() => query.select(any())).thenAnswer(
        (_) => FakeFilterBuilder([
          payment(1, 'Loyalty Card'),
          payment(2, 'Loyalty payment on Washer - Washer 1', status: 'started'),
          payment(
            3,
            'Loyalty payment on Washer - Washer 1',
            status: 'refunded',
          ),
          payment(4, 'Legacy washer'),
          {
            ...payment(5, 'Old washer'),
            'created_at': DateTime.now()
                .subtract(const Duration(days: 15))
                .toIso8601String(),
          },
          {
            ...payment(6, 'Requested washer', status: 'started'),
            'requested_refund': true,
          },
        ]),
      );
      final result = await service.getRefundableTransactionsForUser();
      expect(result.ids, [2, 4]);
      expect(result.transactions, hasLength(2));
      expect(result.transactions[0], contains('Loyalty payment on Washer'));
      expect(result.transactions[1], contains('Legacy washer'));
    },
  );

  test('signed-out customers cannot read or request credits', () async {
    when(() => auth.currentUser).thenReturn(null);
    final result = await service.getRefundableTransactionsForUser();
    expect(result.ids, isEmpty);
    expect(result.transactions, isEmpty);
    expect(
      await service.recordRefundRequest(
        transaction_id: '7',
        description: 'Issue',
      ),
      isNull,
    );
    verifyNever(() => client.from(any()));
    verifyNever(() => client.rpc(any(), params: any(named: 'params')));
  });
}
