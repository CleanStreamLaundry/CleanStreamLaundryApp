import 'package:clean_stream_laundry_app/logic/parsing/transaction_parser.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseTransactionService extends TransactionService {
  late final SupabaseClient _client;

  SupabaseTransactionService({required SupabaseClient client}) {
    _client = client;
  }

  @override
  Future<List<Map<String, dynamic>>> getTransactionsForUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final response = await _client
        .from('transactions')
        .select('id, amount, description, created_at, type')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<({List<String> transactions, List<int> ids})>
  getRefundableTransactionsForUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return (transactions: <String>[], ids: <int>[]);

    final response = await _client
        .from('transactions')
        .select('id, amount, description, created_at, cortina_status')
        .eq('user_id', user.id)
        .neq('requested_refund', true)
        .order('created_at', ascending: false);

    final transactions = <String>[];
    final ids = <int>[];
    for (final row in List<Map<String, dynamic>>.from(response).take(100)) {
      if (row['cortina_status'] != null && row['cortina_status'] != 'started') {
        continue;
      }
      final text = TransactionParser.formatTransaction(row, 'refundHistory');
      final id = TransactionParser.getTransactionIDs(row);
      if (text.isEmpty || text.contains('added to Loyalty Card') || id < 0) {
        continue;
      }
      transactions.add(text);
      ids.add(id);
    }

    return (transactions: transactions, ids: ids);
  }

  @override
  Future<void> recordTransaction({
    required double amount,
    required String description,
    required String type,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }

    await _client.from('transactions').insert({
      'user_id': user.id,
      'amount': amount,
      'description': description,
      'type': type,
    });
  }

  @override
  Future<String?> recordRefundRequest({
    required String transaction_id,
    required String description,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }

    final data = await _client
        .from('transactions')
        .select('amount, cortina_vend_session_id')
        .eq('id', transaction_id)
        .eq('user_id', user.id)
        .single();

    if (data['cortina_vend_session_id'] != null) {
      final result = await _client.rpc(
        'request_cortina_loyalty_credit',
        params: {
          'target_transaction_id': int.parse(transaction_id),
          'request_description': description,
        },
      );
      return (result as Map<String, dynamic>)['amount'].toString();
    }

    await _client
        .from('transactions')
        .update({'requested_refund': true})
        .eq('id', transaction_id)
        .select();

    final amount = data['amount'].toString();

    await _client.from('Refunds').insert({
      'user_id': user.id,
      'transaction_id': transaction_id,
      'description': description,
      'amount': amount,
    });

    await _client.rpc(
      'increment_user_refund_attempts',
      params: {'uid': user.id},
    );

    return amount;
  }

}
