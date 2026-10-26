import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:get_it/get_it.dart';

class PaymentProcessor {
  final PaymentService _paymentService = GetIt.instance<PaymentService>();
  final TransactionService _transactionService =
      GetIt.instance<TransactionService>();

  Future<PaymentResult> processPayment(
    double amount,
    String description, {
    Map<String, dynamic>? consent,
  }) async {
    try {
      final purpose = description == "Loyalty Card"
          ? PaymentPurpose.walletLoad
          : PaymentPurpose.directMachinePayment;
      final result = await _paymentService.makePayment(
        amount,
        purpose: purpose,
        consent: consent,
      );

      if (result == PaymentResult.success &&
          purpose == PaymentPurpose.directMachinePayment) {
        _transactionService.recordTransaction(
          amount: amount,
          description: description,
          type: "Laundry",
        );
      }

      return result;
    } on StripeException {
      return PaymentResult.canceled;
    } catch (_) {
      return PaymentResult.failed;
    }
  }
}
