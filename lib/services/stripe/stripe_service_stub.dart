import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/logic/exceptions/platform_exception.dart';

class StripeService implements PaymentService {
  @override
  Future<PaymentResult> makePayment(
    double amount, {
    PaymentPurpose purpose = PaymentPurpose.directMachinePayment,
    Map<String, dynamic>? consent,
  }) async {
    print("StripeService is not supported on this platform.");
    throw PlatformException("StripeService is not supported on this platform.");
  }
}
