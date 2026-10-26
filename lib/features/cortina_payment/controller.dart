import 'dart:async';

import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum CortinaPaymentOutcome { success, pending, refunded, failed, canceled }

class CortinaPaymentController extends ChangeNotifier {
  static const uncertainMessage =
      'Payment and machine status are unconfirmed. Please contact Clean Stream support before making another payment.';
  final String? machineToken;
  final String? terminalId;
  final String? uniQr;
  final CortinaVendService vendService;
  final AuthService authService;
  final WalletService walletService;
  final CortinaPendingStore pendingStore;
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
    CortinaPendingStore? pendingStore,
    Future<void> Function(String clientSecret)? presentPaymentSheet,
    Future<void> Function(Duration duration)? delay,
    this.pollAttempts = 50,
  }) : vendService = vendService ?? GetIt.instance<CortinaVendService>(),
       authService = authService ?? GetIt.instance<AuthService>(),
       walletService = walletService ?? GetIt.instance<WalletService>(),
       pendingStore = pendingStore ?? GetIt.instance<CortinaPendingStore>(),
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
  bool _paymentUnresolved = false;
  bool _disposed = false;
  bool _scopeInvalidated = false;
  bool _initialized = false;
  bool _initializing = false;
  String? _accountId;
  String? _scope;
  CortinaPendingPayment? _pending;
  StreamSubscription<AuthState>? _authSubscription;
  CortinaPaymentOutcome? restoredOutcome;
  bool restoredWallet = false;

  bool get isCurrentScope => !_disposed && !_scopeInvalidated &&
      _initialized && authService.getCurrentUserId == _accountId;

  bool get paymentLocked =>
      isLoading || !isCurrentScope || isProcessing ||
      paymentCompleted || _paymentUnresolved;
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
    if (_initializing || isProcessing || _disposed || _scopeInvalidated) return;
    _initializing = true;
    if (!_initialized) {
      _accountId = authService.getCurrentUserId;
      _initialized = true;
      final startingSession = authService.currentSession;
      var firstAuthEvent = true;
      _authSubscription = authService.authStateChanges.listen((state) {
        // Supabase replays its latest event when checkout subscribes.
        final initialSignInReplay = firstAuthEvent &&
            startingSession != null &&
            state.event == AuthChangeEvent.signedIn &&
            state.session?.user.id == _accountId &&
            identical(state.session, startingSession) &&
            identical(authService.currentSession, startingSession);
        firstAuthEvent = false;
        if (initialSignInReplay) return;
        if (state.session?.user.id != _accountId ||
            state.event == AuthChangeEvent.signedOut ||
            state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.passwordRecovery) {
          _scopeInvalidated = true;
          walletBalance = null;
          paymentCompleted = false;
          restoredOutcome = null;
          errorMessage = uncertainMessage;
          _notify();
        }
      });
    }
    isLoading = true;
    errorMessage = null;
    restoredOutcome = null;
    _notify();
    try {
      final currentQuote = await vendService.quote(
        machineToken: machineToken,
        terminalId: terminalId,
        uniQr: uniQr,
      );
      _ensureCurrent();
      quote = currentQuote;
      amountCents = quote!.isDryer
          ? quote!.dryerDefaultCents
          : quote!.amountCents;
      _scope = pendingStore.scope(
        accountId: _accountId,
        machineId: currentQuote.machineId,
      );
      _pending = await pendingStore.read(_scope!);
      _ensureCurrent();
      _paymentUnresolved = _pending != null;
      if (_pending != null) {
        _paymentUnresolved = true;
        amountCents = _pending!.amountCents;
        restoredWallet = _pending!.method == 'wallet';
        var reference = _pending!.reference;
        if (reference == null && _accountId != null) {
          reference = await vendService.recoverPendingPayment(
            clientRequestId: _pending!.requestId,
            machineId: currentQuote.machineId,
          );
          _ensureCurrent();
          await _attach(reference);
          _ensureCurrent();
        }
        final outcome = reference == null
            ? _unconfirmed()
            : await _poll(reference);
        await _settle(outcome);
        _ensureCurrent();
        restoredOutcome = outcome;
      }
      if (isSignedIn) {
        try {
          final WalletBalance balance = await walletService.getBalance();
          _ensureCurrent();
          walletBalance = balance.totalBalance;
        } catch (_) {
          if (isCurrentScope) walletBalance = null;
        }
      }
    } catch (_) {
      _paymentUnresolved = true;
      if (isCurrentScope) {
        _unconfirmed();
        if (_pending != null) restoredOutcome = CortinaPaymentOutcome.pending;
      }
    } finally {
      isLoading = false;
      _initializing = false;
      _notify();
    }
  }

  void setDryerAmount(int cents) {
    if (paymentLocked) return;
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
    return _runPayment('card', () async {
      final session = await vendService.createCardPayment(
        machineToken: machineToken,
        terminalId: terminalId,
        uniQr: uniQr,
        amountCents: amountCents,
        clientRequestId: _pending!.requestId,
      );
      final reference = CortinaVendReference(
        sessionId: session.sessionId,
        accessToken: session.accessToken,
      );
      await _attach(reference);
      _ensureCurrent();
      try {
        await presentPaymentSheet(session.clientSecret);
      } on StripeException catch (error) {
        _ensureCurrent();
        if (error.error.code == FailureCode.Canceled) {
          return CortinaPaymentOutcome.canceled;
        }
        rethrow;
      }
      _ensureCurrent();
      await vendService.confirmCardPayment(reference);
      _ensureCurrent();
      final outcome = await _poll(reference);
      if (outcome != CortinaPaymentOutcome.pending) {
        _cardRequestId = null;
      }
      return outcome;
    });
  }

  Future<CortinaPaymentOutcome> payWithWallet() async {
    if (!isSignedIn) return CortinaPaymentOutcome.failed;
    return _runPayment('wallet', () async {
      try {
        final reference = await vendService.payWithWallet(
          machineToken: machineToken,
          terminalId: terminalId,
          uniQr: uniQr,
          amountCents: amountCents,
          clientRequestId: _pending!.requestId,
        );
        await _attach(reference);
        _ensureCurrent();
        final outcome = await _poll(reference);
        if (outcome != CortinaPaymentOutcome.pending) {
          _walletRequestId = null;
        }
        return outcome;
      } finally {
        // Read the ledger after either a debit or its reversal; never guess it.
        try {
          if (isCurrentScope) {
            final balance = await walletService.getBalance();
            if (isCurrentScope) walletBalance = balance.totalBalance;
          }
        } catch (_) {
          // A balance lookup failure must not turn a successful vend into a failure.
          if (isCurrentScope) walletBalance = null;
        }
      }
    });
  }

  Future<CortinaPaymentOutcome> _runPayment(
    String method,
    Future<CortinaPaymentOutcome> Function() action,
  ) async {
    if (!isCurrentScope) return CortinaPaymentOutcome.pending;
    if (paymentCompleted) return CortinaPaymentOutcome.success;
    if (paymentLocked || quote == null || _scope == null) {
      return CortinaPaymentOutcome.pending;
    }
    _paymentUnresolved = true;
    isProcessing = true;
    errorMessage = null;
    _notify();
    try {
      _pending = CortinaPendingPayment(
        requestId: method == 'wallet'
            ? (_walletRequestId ??= const Uuid().v4())
            : (_cardRequestId ??= const Uuid().v4()),
        method: method,
        amountCents: amountCents,
      );
      // A timeout cannot prove that the subsequent financial request was unsent.
      await pendingStore.claim(_scope!, _pending!);
      _ensureCurrent();
      final outcome = await action();
      _ensureCurrent();
      await _settle(outcome);
      return outcome;
    } catch (_) {
      return _unconfirmed();
    } finally {
      isProcessing = false;
      _notify();
    }
  }

  Future<CortinaPaymentOutcome> _poll(CortinaVendReference reference) async {
    for (var attempt = 0; attempt < pollAttempts; attempt++) {
      _ensureCurrent();
      final status = await vendService.status(reference);
      _ensureCurrent();
      vendStatus = status.status;
      _notify();
      if (status.isSuccessful) {
        return CortinaPaymentOutcome.success;
      }
      if (status.status == 'refunded') {
        errorMessage = status.failureMessage;
        return CortinaPaymentOutcome.refunded;
      }
      if (!const {
        'payment_pending',
        'paid',
        'starting',
        'awaiting_sale',
        'approved',
      }.contains(status.status)) {
        return _unconfirmed();
      }
      await delay(const Duration(seconds: 1));
    }
    return _unconfirmed();
  }

  CortinaPaymentOutcome _unconfirmed() {
    if (isCurrentScope) errorMessage = uncertainMessage;
    return CortinaPaymentOutcome.pending;
  }

  Future<void> _attach(CortinaVendReference reference) async {
    // Save a late response to its original scope even if that screen has closed.
    // It must never authorize another action or update a different account UI.
    await pendingStore.attach(_scope!, _pending!.requestId, reference);
  }

  Future<void> _settle(CortinaPaymentOutcome outcome) async {
    _ensureCurrent();
    if (outcome != CortinaPaymentOutcome.success &&
        outcome != CortinaPaymentOutcome.refunded &&
        outcome != CortinaPaymentOutcome.canceled) {
      return;
    }
    await pendingStore.clear(_scope!, _pending!.requestId);
    _ensureCurrent();
    _pending = null;
    _paymentUnresolved = false;
    paymentCompleted = outcome == CortinaPaymentOutcome.success;
  }

  void _ensureCurrent() {
    if (!isCurrentScope) throw StateError('Payment scope changed');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
