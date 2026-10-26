import 'dart:async';
import 'dart:html' as html;

import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

class StripeService implements PaymentService {
  final edgeFunctionService = GetIt.instance<EdgeFunctionService>();
  final _authService = GetIt.instance<AuthService>();
  bool _paymentInProgress = false;

  @protected
  html.WindowBase? openCheckout(String url) => html.window.open(url, '_blank');

  @override
  Future<PaymentResult> makePayment(
    double amount, {
    PaymentPurpose purpose = PaymentPurpose.directMachinePayment,
    Map<String, dynamic>? consent,
  }) async {
    if (_paymentInProgress) return PaymentResult.pending;
    final userId = _authService.getCurrentUserId;
    if (userId == null || !amount.isFinite || amount <= 0) {
      return PaymentResult.pending;
    }
    final amountCents = (amount * 100).toInt();
    final expectedPurpose = purpose == PaymentPurpose.walletLoad
        ? 'wallet_load'
        : 'direct_machine_payment';
    _paymentInProgress = true;

    const budget = Duration(minutes: 2);
    final elapsed = Stopwatch()..start();
    final stopped = Completer<void>();
    void stop() {
      if (!stopped.isCompleted) stopped.complete();
    }

    final deadline = Timer(budget, stop);
    Timer? closeTimer;
    Timer? pollTimer;
    StreamSubscription<bool>? authSubscription;
    StreamSubscription<html.Event>? pageSubscription;
    html.WindowBase? portal;

    bool active() =>
        !stopped.isCompleted &&
        elapsed.elapsed < budget &&
        _authService.getCurrentUserId == userId &&
        (portal == null || portal.closed == false);

    // EdgeFunctionService cannot abort transport. Stop waiting, then discard late
    // completion; never start another request after closure or the same deadline.
    Future<T?> untilStopped<T>(Future<T> future) =>
        Future.any<T?>([future, stopped.future.then<T?>((_) => null)]);

    try {
      authSubscription = _authService.onAuthChange.listen((signedIn) {
        if (!signedIn || _authService.getCurrentUserId != userId) stop();
      }, onError: (Object error) => stop());
      pageSubscription = html.window.onPageHide.listen((_) => stop());

      final response = await untilStopped(
        edgeFunctionService.runEdgeFunction(
          name: 'createCheckoutSession',
          body: {
            'amount': amountCents,
            'purpose': purpose.name,
            'consent': ?consent,
          },
        ),
      );
      if (!active() || response == null || response.status != 200) {
        return PaymentResult.pending;
      }
      final checkout = response.data;
      if (checkout is! Map) return PaymentResult.pending;
      final url = checkout['url'];
      final sessionId = checkout['session_id'];
      if (url is! String ||
          url.isEmpty ||
          sessionId is! String ||
          sessionId.isEmpty) {
        return PaymentResult.pending;
      }

      portal = openCheckout(url);
      if (portal == null || !active()) return PaymentResult.pending;
      closeTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        try {
          if (!active()) stop();
        } catch (_) {
          stop();
        }
      });

      var delaySeconds = 2;
      while (active()) {
        final ready = Completer<void>();
        pollTimer = Timer(Duration(seconds: delaySeconds), ready.complete);
        await untilStopped(ready.future);
        if (!active()) return PaymentResult.pending;

        final response = await untilStopped(
          edgeFunctionService.runEdgeFunction(
            name: 'checkPaymentResult',
            body: {'session_id': sessionId},
          ),
        );
        if (!active() || response == null || response.status != 200) {
          return PaymentResult.pending;
        }
        final data = response.data;
        if (data is! Map ||
            data['session_id'] != sessionId ||
            data['purpose'] != expectedPurpose ||
            data['amountCents'] is! int ||
            data['amountCents'] != amountCents ||
            data['currency'] != 'usd' ||
            data['walletLoadRecorded'] is! bool ||
            !const [
              'paid',
              'unpaid',
              'no_payment_required',
            ].contains(data['status'])) {
          return PaymentResult.pending;
        }
        final intentId = data['paymentIntentId'];
        if (intentId != null && (intentId is! String || intentId.isEmpty)) {
          return PaymentResult.pending;
        }

        switch (data['paymentStatus']) {
          case 'succeeded':
            return data['status'] == 'paid' &&
                    intentId is String &&
                    intentId.isNotEmpty &&
                    (purpose != PaymentPurpose.walletLoad ||
                        data['walletLoadRecorded'] == true)
                ? PaymentResult.success
                : PaymentResult.pending;
          case 'canceled':
            return data['status'] == 'unpaid' &&
                    data['walletLoadRecorded'] == false
                ? PaymentResult.canceled
                : PaymentResult.pending;
          case 'processing':
            if (delaySeconds < 5) delaySeconds += 1;
          default:
            return PaymentResult.pending;
        }
      }
      return PaymentResult.pending;
    } catch (_) {
      return PaymentResult.pending;
    } finally {
      stop();
      deadline.cancel();
      closeTimer?.cancel();
      pollTimer?.cancel();
      elapsed.stop();
      try {
        portal?.close();
      } catch (_) {
        // Losing access to the popup does not settle the payment.
      }
      await authSubscription?.cancel();
      await pageSubscription?.cancel();
      _paymentInProgress = false;
    }
  }
}
