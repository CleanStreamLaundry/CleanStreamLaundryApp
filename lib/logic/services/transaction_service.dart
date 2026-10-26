abstract class TransactionService {
  Future<void> recordTransaction({required double amount, required String description, required String type,});
  Future<List<Map<String, dynamic>>> getTransactionsForUser();
  Future<({List<String> transactions, List<int> ids})> getRefundableTransactionsForUser();
  Future<String?> recordRefundRequest({required String transaction_id, required String description,});
}
