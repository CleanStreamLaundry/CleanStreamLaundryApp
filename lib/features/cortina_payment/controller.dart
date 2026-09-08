import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

enum CortinaPaymentOutcome { success, pending, refunded, failed, canceled }

class CortinaPaymentController extends ChangeNotifier {
  final String? machineToken;
  final String? terminalId;
  final String? uniQr;
  final CortinaVendService vendService;
  final AuthService authService;
  final WalletService walletService;
  final Future<void> Function(String clientSecret) presentPaymentSheet;
  final Future<void> Function(Duration duration) delay;
  final int pollAttempts;

  CortinaPaymentController({
    required this.machineToken,
    required this.terminalId,
    required this.uniQr,
    CortinaVendService? vendService,
    AuthService? authService,
    WalletService? walletService,
    Future<void> Function(String clientSecret)? presentPaymentSheet,
    Future<void> Function(Duration duration)? delay,
    this.pollAttempts = 50,
  }) : vendService = vendService ?? GetIt.instance<CortinaVendService>(),
       authService = authService ?? GetIt.instance<AuthService>(),
       walletService = walletService ?? GetIt.instance<WalletService>(),
       presentPaymentSheet = presentPaymentSheet ?? _showPaymentSheet,
       delay = delay ?? ((duration) => Future<void>.delayed(duration));

  CortinaQuote? quote;
  int amountCents = 0;
  double? walletBalance;
  bool isLoading = true;
  bool isProcessing = false;
  bool paymentCompleted = false;
  String? errorMessage;
  String? vendStatus;
  String? _cardRequestId;
  String? _walletRequestId;

  bool get isDryer => quote?.isDryer ?? false;
  bool get isSignedIn => authService.getCurrentUserId != null;
  double get price => amountCents / 100;
  int get dryerMinutes {
    for (final option in quote?.dryerOptions ?? const <CortinaDryerOption>[]) {
      if (option.amountCents == amountCents) return option.minutes;
    }
    return 0;
  }

  static Future<void> _showPaymentSheet(String clientSecret) async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'Clean Stream Laundry Solutions',
        googlePay: const PaymentSheetGooglePay(
          merchantCountryCode: 'US',
          currencyCode: 'USD',
        ),
      ),
    );
    await Stripe.instance.presentPaymentSheet();
  }

  Future<void> init() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      quote = await vendService.quote(
        machineToken: machineToken,
        terminalId: terminalId,
        uniQr: uniQr,
      );
      amountCents = quote!.isDryer
          ? quote!.dryerDefaultCents
          : quote!.amountCents;
      if (isSignedIn) {
        final WalletBalance balance = await walletService.getBalance();
        walletBalance = balance.totalBalance;
      }
    } catch (error) {
      errorMessage = _message(error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void setDryerAmount(int cents) {
    final currentQuote = quote;
    if (currentQuote == null || !currentQuote.isDryer) return;
    if (!currentQuote.dryerOptions.any(
      (option) => option.amountCents == cents,
    )) {
      return;
    }
    amountCents = cents;
    _cardRequestId = null;
    _walletRequestId = null;
    notifyListeners();
  }

  Future<CortinaPaymentOutcome> payWithCard() async {
    return _runPayment(() async {
      final session = await vendService.createCardPayment(
        machineToken: machineToken,
        terminalId: terminalId,
        uniQr: uniQr,
        amountCents: amountCents,
        clientRequestId: _cardRequestId ??= const Uuid().v4(),
      );
      await presentPaymentSheet(session.clientSecret);
      final reference = CortinaVendReference(
        sessionId: session.sessionId,
        accessToken: session.accessToken,
      );
      await vendService.confirmCardPayment(reference);
      return _poll(reference);
    });
  }

  Future<CortinaPaymentOutcome> payWithWallet() async {
    if (!isSignedIn) return CortinaPaymentOutcome.failed;
    return _runPayment(() async {
      final reference = await vendService.payWithWallet(
        machineToken: machineToken,
        terminalId: terminalId,
        uniQr: uniQr,
        amountCents: amountCents,
        clientRequestId: _walletRequestId ??= const Uuid().v4(),
      );
      return _poll(reference);
    });
  }

  Future<CortinaPaymentOutcome> _runPayment(
    Future<CortinaPaymentOutcome> Function() action,
  ) async {
    if (isProcessing) return CortinaPaymentOutcome.pending;
    isProcessing = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await action();
    } on StripeException catch (error) {
      if (error.error.code == FailureCode.Canceled) {
        return CortinaPaymentOutcome.canceled;
      }
      errorMessage = _message(error);
      return CortinaPaymentOutcome.failed;
    } catch (error) {
      errorMessage = _message(error);
      return CortinaPaymentOutcome.failed;
    } finally {
      isProcessing = false;
      notifyListeners();
    }
  }

  Future<CortinaPaymentOutcome> _poll(CortinaVendReference reference) async {
    for (var attempt = 0; attempt < pollAttempts; attempt++) {
      final status = await vendService.status(reference);
      vendStatus = status.status;
      notifyListeners();
      if (status.isSuccessful) {
        paymentCompleted = true;
        notifyListeners();
        return CortinaPaymentOutcome.success;
      }
      if (status.isTerminalFailure) {
        errorMessage = status.failureMessage;
        return status.status == 'refunded'
            ? CortinaPaymentOutcome.refunded
            : CortinaPaymentOutcome.failed;
      }
      await delay(const Duration(seconds: 1));
    }
    return CortinaPaymentOutcome.pending;
  }

  String _message(Object error) {
    final text = error.toString();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }
}
