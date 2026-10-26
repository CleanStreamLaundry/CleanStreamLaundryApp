import 'package:clean_stream_laundry_app/services/supabase/supabase_transaction_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'mocks.dart';


void main() {
  late SupabaseMock supabaseMock;
  late QueryBuilderMock queryBuilderMock;
  late FakeFilterBuilder fakeFilterBuilder;
  late SupabaseTransactionService transactionHandler;
  late GoTrueMock supabaseAuth;

  setUp(() {
    final now = DateTime.now().toUtc();
    final fmt = (DateTime d) => d.toIso8601String();

    supabaseMock = SupabaseMock();
    queryBuilderMock = QueryBuilderMock();
    fakeFilterBuilder = FakeFilterBuilder([
      {"id": 1, "amount": 2.75, "description": "machine", "created_at": fmt(now.subtract(Duration(days: 1))),  "requested_refund": true},
      {"id": 2, "amount": 2.75, "description": "machine", "created_at": fmt(now.subtract(Duration(days: 2))),  "requested_refund": false},
      {"id": 3, "amount": 2.75, "description": "machine", "created_at": fmt(now.subtract(Duration(days: 5))),  "requested_refund": true},
      {"id": 4, "amount": 2.75, "description": "machine", "created_at": fmt(now.subtract(Duration(days: 7))),  "requested_refund": false},
      {"id": 5, "amount": 2.75, "description": "machine", "created_at": fmt(now.subtract(Duration(days: 10))), "requested_refund": false},
      {"id": 6, "amount": 2.75, "description": "machine", "created_at": fmt(now.subtract(Duration(days: 13))), "requested_refund": false},
    ]);
    transactionHandler = SupabaseTransactionService(client: supabaseMock);
    supabaseAuth = GoTrueMock();

    when(() => supabaseMock.from('transactions')).thenAnswer((_) => queryBuilderMock);
    when(() => supabaseMock.from('Refunds')).thenAnswer((_) => queryBuilderMock);
    when(() => queryBuilderMock.select(any())).thenAnswer((_) => fakeFilterBuilder);
    when(() => supabaseMock.auth).thenReturn(supabaseAuth);

    final mockUser = User(
      id: '11111111-1111-1111-1111-111111111111',
      aud: 'authenticated',
      role: 'authenticated',
      email: 'testemail@test.com',
      emailConfirmedAt: null,
      phone: '',
      lastSignInAt: '',
      appMetadata: {},
      userMetadata: {},
      identities: [],
      createdAt: '',
      updatedAt: '',
    );

    when(() => supabaseAuth.currentUser).thenReturn(mockUser);

  });

  group('transaction Tests',(){

    test("Get transaction history data",() async {
      final result = await transactionHandler.getTransactionsForUser();
      expect(result.length, 6);
    });

    test("Get refundable transaction history data",() async {
      final result = await transactionHandler.getRefundableTransactionsForUser();
      expect(result.ids.length, 4);
    });

    test("Tests if the user is null",() async{
      when(() => supabaseAuth.currentUser).thenReturn(null);
      final result = await transactionHandler.getTransactionsForUser();
      expect(result.length, 0);
    });

    test("Tests that transaction is recorded properly",() async {
      await transactionHandler.recordTransaction(amount: 27.5, description: "Test transaction", type: "test type");
      verify(() => supabaseMock.from("transactions"));
    });

    test("Tests if logic is correct for recording refunds",() async {
      when(() => supabaseMock.rpc(any(), params: any(named: 'params')))
          .thenAnswer((_) => FakeCreditResponse());

      final amount = await transactionHandler.recordRefundRequest(
          transaction_id: "3",
          description: "Test refund"
      );

      expect(amount, '4');
      verify(() => supabaseMock.auth.currentUser!);
      verifyNever(() => supabaseMock.from("Refunds"));
      verifyNever(() => queryBuilderMock.update(any()));
      verify(() => supabaseMock.rpc('request_legacy_loyalty_credit', params: {
        'target_transaction_id': '3', 'request_description': 'Test refund',
      })).called(1);
    });

  });



}
