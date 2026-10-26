import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:get_it/get_it.dart';

class PaymentIntentConfig {
  final String clientSecret;
  final String paymentIntentId;

  const PaymentIntentConfig({
    required this.clientSecret,
    required this.paymentIntentId,
  });
}

class StripeService implements PaymentService {
  final edgeFunctionService = GetIt.instance<EdgeFunctionService>();

  final _stripeInstance = GetIt.instance<Stripe>();
  bool _paymentInProgress = false;

  @override
  Future<PaymentResult> makePayment(
    double amount, {
    PaymentPurpose purpose = PaymentPurpose.directMachinePayment,
    Map<String, dynamic>? consent,
  }) async {
    if (_paymentInProgress) {
      throw StateError("A payment is already in progress");
    }

    PaymentIntentConfig? paymentIntent;
    _paymentInProgress = true;

    try {
      paymentIntent = await createPaymentIntent(amount, "usd", purpose, consent);
      if (paymentIntent == null) {
        throw StripeConfigException("Failed to create payment intent");
      }

      await _stripeInstance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntent.clientSecret,
          merchantDisplayName: "Clean Stream Laundry Solutions",
          appearance: PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: Color(0xFF2073A9),
              background: CupertinoColors.systemBackground,
              componentBackground: CupertinoColors.secondarySystemBackground,
              componentBorder: CupertinoColors.separator,
              componentText: CupertinoColors.label,
              placeholderText: CupertinoColors.separator,
            ),
            shapes: const PaymentSheetShape(borderRadius: 20),
            primaryButton: PaymentSheetPrimaryButtonAppearance(
              colors: PaymentSheetPrimaryButtonTheme(
                light: PaymentSheetPrimaryButtonThemeColors(
                  background: Color(0xFF2073A9),
                  text: CupertinoColors.white,
                ),
              ),
              shapes: const PaymentSheetPrimaryButtonShape(blurRadius: 20),
            ),
          ),
          // Commented out for testing until we get a merchant id from Apple Developer
          //applePay: const PaymentSheetApplePay(merchantCountryCode: 'US'),
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'US',
            currencyCode: 'USD',
          ),
        ),
      );
      await _stripeInstance.presentPaymentSheet();
      return await verifyPaymentIntent(paymentIntent.paymentIntentId);
    } on StripeException catch (e) {
      debugPrint(
        "Stripe PaymentSheet error: "
        "code=${e.error.code}, "
        "stripeErrorCode=${e.error.stripeErrorCode}, "
        "message=${e.error.localizedMessage ?? e.error.message}",
      );
      if (e.error.code == FailureCode.Canceled) {
        if (paymentIntent != null) {
          final verifiedResult = await verifyPaymentIntent(
            paymentIntent.paymentIntentId,
          );
          if (verifiedResult == PaymentResult.success ||
              verifiedResult == PaymentResult.pending) {
            return verifiedResult;
          }
        }
        return PaymentResult.canceled;
      }
      if (paymentIntent != null) {
        return await verifyPaymentIntent(paymentIntent.paymentIntentId);
      }
      rethrow;
    } catch (e) {
      debugPrint("payment error: $e");
      if (paymentIntent != null) {
        return await verifyPaymentIntent(paymentIntent.paymentIntentId);
      }
      rethrow;
    } finally {
      _paymentInProgress = false;
    }
  }

  @protected
  Future<PaymentIntentConfig?> createPaymentIntent(
    double amount,
    String currency, [
    PaymentPurpose purpose = PaymentPurpose.directMachinePayment,
    Map<String, dynamic>? consent,
  ]) async {
    try {
      final response = await edgeFunctionService.runEdgeFunction(
        name: 'paymentIntent',
        body: {
          'amount': convertDollarsToCents(amount),
          'currency': currency,
          'purpose': purpose.name,
          'consent': ?consent,
        },
      );

      final data = response?.data;
      if (data != null &&
          data['clientSecret'] != null &&
          data['paymentIntentId'] != null) {
        return PaymentIntentConfig(
          clientSecret: data["clientSecret"] as String,
          paymentIntentId: data["paymentIntentId"] as String,
        );
      }

      final keys = data is Map ? data.keys.join(', ') : data.runtimeType;
      debugPrint(
        "paymentIntent response missing required fields "
        "(status=${response?.status}, keys=$keys)",
      );
      return null;
    } catch (e) {
      debugPrint("paymentIntent request error: $e");
      return null;
    }
  }

  @protected
  Future<PaymentResult> verifyPaymentIntent(String paymentIntentId) async {
    try {
      final response = await edgeFunctionService.runEdgeFunction(
        name: 'paymentIntentStatus',
        body: {'paymentIntentId': paymentIntentId},
      );
      final data = response?.data;

      switch (data == null ? null : data['status']) {
        case 'succeeded':
          return PaymentResult.success;
        case 'processing':
          return PaymentResult.pending;
        case 'canceled':
          return PaymentResult.canceled;
        case 'failed':
        case 'unknown':
        default:
          return PaymentResult.failed;
      }
    } catch (e) {
      debugPrint("payment verification error: $e");
      return PaymentResult.failed;
    }
  }

  @protected
  int convertDollarsToCents(double amount) {
    return (amount * 100).round();
  }
}
