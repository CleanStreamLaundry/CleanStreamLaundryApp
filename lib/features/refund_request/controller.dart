import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

class RefundController extends ChangeNotifier {
  final TransactionService transactionService;
  final EdgeFunctionService edgeFunctionService;
  final ProfileService profileService;
  final AuthService authService;

  RefundController({
    TransactionService? transactionService,
    EdgeFunctionService? edgeFunctionService,
    ProfileService? profileService,
    AuthService? authService,
  })  : transactionService =
      transactionService ?? GetIt.instance<TransactionService>(),
        edgeFunctionService =
            edgeFunctionService ?? GetIt.instance<EdgeFunctionService>(),
        profileService = profileService ?? GetIt.instance<ProfileService>(),
        authService = authService ?? GetIt.instance<AuthService>();

  final TextEditingController descriptionController = TextEditingController();

  List<String> recentTransactions = [];
  List<int> recentTransactionIDs = [];

  String? selectedTransaction;
  int? selectedTransactionIndex;

  bool attemptedSubmit = false;
  bool isLoading = false;
  bool isFetchingTransactions = true;

  void disposeController() {
    descriptionController.dispose();
  }

  bool get isFormValid =>
      selectedTransaction != null &&
          descriptionController.text.trim().isNotEmpty;

  Future<void> fetchTransactions() async {
    try {
      final result =
      await transactionService.getRefundableTransactionsForUser();
      final eligible = [
        for (var i = 0; i < result.transactions.length; i++)
          if (!result.transactions[i].contains('added to Loyalty Card')) i,
      ];
      recentTransactions = [for (final i in eligible) result.transactions[i]];
      recentTransactionIDs = [for (final i in eligible) result.ids[i]];
    } catch (e) {
      // silently ignore — page stays usable with empty list
    } finally {
      isFetchingTransactions = false;
      notifyListeners();
    }
  }

  void selectTransaction(String transaction) {
    selectedTransaction = transaction;
    selectedTransactionIndex = recentTransactions.indexOf(transaction);
    notifyListeners();
  }

  String getTransactionID() {
    return recentTransactionIDs[selectedTransactionIndex!].toString();
  }

  Future<bool> submitRefund() async {
    if (isLoading) return false;
    final userId = authService.getCurrentUserId;
    if (userId == null) return false;

    isLoading = true;
    notifyListeners();

    try {
      final transactionId = getTransactionID();
      final description = descriptionController.text;
      final amount = await transactionService.recordRefundRequest(
        transaction_id: transactionId,
        description: description,
      );
      if (amount == null) return false;

      try {
        if (authService.getCurrentUserId != userId) return true;
        final username = await profileService.getUserNameById(userId);
        if (authService.getCurrentUserId != userId) return true;
        await edgeFunctionService.runEdgeFunction(
          name: 'refund-email',
          body: {
            'username': username,
            'user_id': userId,
            'transaction_id': transactionId,
            'amount': amount,
            'description': description,
          },
        );
      } on Exception {
        // The claim is already saved; notification failure must not invite a retry.
      }

      return true;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void markAttemptedSubmit() {
    attemptedSubmit = true;
    notifyListeners();
  }
}
