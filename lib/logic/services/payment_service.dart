import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';

enum PaymentPurpose { directMachinePayment, walletLoad }

abstract class PaymentService {
  Future<PaymentResult> makePayment(
    double amount, {
    PaymentPurpose purpose = PaymentPurpose.directMachinePayment,
    Map<String, dynamic>? consent,
  });
}
