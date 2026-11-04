import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MockCortinaVendService extends Mock implements CortinaVendService {}

class MockAuthService extends Mock implements AuthService {}

class MockWalletService extends Mock implements WalletService {}

const dryerQuote = CortinaQuote(
  machineId: 7,
  machineName: 'Dryer 7',
  machineType: 'dryer',
  washerSizeLabel: null,
  amountCents: 150,
  dryerDefaultCents: 150,
  dryerOptions: [
    CortinaDryerOption(minutes: 10, amountCents: 50),
    CortinaDryerOption(minutes: 20, amountCents: 100),
    CortinaDryerOption(minutes: 30, amountCents: 150),
    CortinaDryerOption(minutes: 40, amountCents: 200),
    CortinaDryerOption(minutes: 60, amountCents: 300),
    CortinaDryerOption(minutes: 90, amountCents: 450),
  ],
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      const CortinaVendReference(
        sessionId: 'fallback-session',
        accessToken: 'fallback-token',
      ),
    );
  });

  late MockCortinaVendService vendService;
  late MockAuthService authService;
  late MockWalletService walletService;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    vendService = MockCortinaVendService();
    authService = MockAuthService();
    walletService = MockWalletService();
    when(() => authService.getCurrentUserId).thenReturn(null);
    when(() => authService.authStateChanges).thenAnswer((_) => const Stream.empty());
  });

  CortinaPaymentController controller({
    Future<void> Function(String)? sheet,
  }) => CortinaPaymentController(
    machineToken: 'token-1',
    terminalId: null,
    uniQr: null,
    vendService: vendService,
    authService: authService,
    walletService: walletService,
    pendingStore: CortinaPendingStore(project: 'https://test.invalid'),
    presentPaymentSheet: sheet ?? (_) async {},
    delay: (_) async {},
    pollAttempts: 2,
  );

  test('loads server quote and uses the default dryer amount', () async {
    when(
      () => vendService.quote(
        machineToken: 'token-1',
        terminalId: null,
        uniQr: null,
      ),
    ).thenAnswer((_) async => dryerQuote);

    final subject = controller();
    await subject.init();

    expect(subject.amountCents, 150);
    expect(subject.dryerMinutes, 30);
    expect(subject.price, 1.50);
    verifyNever(() => walletService.getBalance());
  });

  test('dryer selection accepts only configured time products', () async {
    when(
      () => vendService.quote(
        machineToken: 'token-1',
        terminalId: null,
        uniQr: null,
      ),
    ).thenAnswer((_) async => dryerQuote);
    final subject = controller();
    await subject.init();

    subject.setDryerAmount(200);

    expect(subject.amountCents, 200);
    expect(subject.dryerMinutes, 40);

    subject.setDryerAmount(250);
    expect(subject.amountCents, 200);
  });

  test(
    'card payment completes after server verification starts the machine',
    () async {
      when(
        () => vendService.quote(
          machineToken: 'token-1',
          terminalId: null,
          uniQr: null,
        ),
      ).thenAnswer((_) async => dryerQuote);
      when(
        () => vendService.createCardPayment(
          machineToken: 'token-1',
          terminalId: null,
          uniQr: null,
          amountCents: 150,
          clientRequestId: any(named: 'clientRequestId'),
        ),
      ).thenAnswer(
        (_) async => const CortinaCardSession(
          sessionId: 'session-1',
          accessToken: 'access-1',
          clientSecret: 'secret-1',
        ),
      );
      when(
        () => vendService.status(any()),
      ).thenAnswer((_) async => const CortinaVendStatus(status: 'started'));
      when(
        () => vendService.confirmCardPayment(any()),
      ).thenAnswer((_) async {});

      final subject = controller();
      await subject.init();
      final outcome = await subject.payWithCard();

      expect(outcome, CortinaPaymentOutcome.success);
      expect(subject.paymentCompleted, isTrue);
      verify(() => vendService.confirmCardPayment(any())).called(1);

      expect(await subject.payWithCard(), CortinaPaymentOutcome.success);
      verify(
        () => vendService.createCardPayment(
          machineToken: 'token-1',
          terminalId: null,
          uniQr: null,
          amountCents: 150,
          clientRequestId: any(named: 'clientRequestId'),
        ),
      ).called(1);
    },
  );

  test('uncertain card confirmation stays pending without another payment', () async {
    when(
      () => vendService.quote(
        machineToken: 'token-1',
        terminalId: null,
        uniQr: null,
      ),
    ).thenAnswer((_) async => dryerQuote);
    when(
      () => vendService.createCardPayment(
        machineToken: 'token-1',
        terminalId: null,
        uniQr: null,
        amountCents: 150,
        clientRequestId: any(named: 'clientRequestId'),
      ),
    ).thenAnswer(
      (_) async => const CortinaCardSession(
        sessionId: 'session-1',
        accessToken: 'access-1',
        clientSecret: 'secret-1',
      ),
    );
    when(
      () => vendService.confirmCardPayment(any()),
    ).thenThrow(StateError('Stripe has not confirmed this payment'));

    final subject = controller();
    await subject.init();
    final outcome = await subject.payWithCard();

    expect(outcome, CortinaPaymentOutcome.pending);
    expect(subject.errorMessage, CortinaPaymentController.uncertainMessage);
    expect(subject.paymentLocked, isTrue);
    verifyNever(() => vendService.status(any()));
  });

  test('a terminal card result creates a fresh payment on retry', () async {
    final requestIds = <String>[];
    when(
      () => vendService.quote(
        machineToken: 'token-1',
        terminalId: null,
        uniQr: null,
      ),
    ).thenAnswer((_) async => dryerQuote);
    when(
      () => vendService.createCardPayment(
        machineToken: 'token-1',
        terminalId: null,
        uniQr: null,
        amountCents: 150,
        clientRequestId: any(named: 'clientRequestId'),
      ),
    ).thenAnswer((invocation) async {
      requestIds.add(invocation.namedArguments[#clientRequestId] as String);
      return const CortinaCardSession(
        sessionId: 'session-1',
        accessToken: 'access-1',
        clientSecret: 'secret-1',
      );
    });
    when(() => vendService.confirmCardPayment(any())).thenAnswer((_) async {});
    when(
      () => vendService.status(any()),
    ).thenAnswer((_) async => const CortinaVendStatus(status: 'refunded'));

    final subject = controller();
    await subject.init();
    await subject.payWithCard();
    await subject.payWithCard();

    expect(requestIds, hasLength(2));
    expect(requestIds[1], isNot(requestIds[0]));
  });

  test('signed-in users receive their wallet balance', () async {
    when(() => authService.getCurrentUserId).thenReturn('user-1');
    when(
      () => vendService.quote(
        machineToken: 'token-1',
        terminalId: null,
        uniQr: null,
      ),
    ).thenAnswer((_) async => dryerQuote);
    when(() => walletService.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet-1',
        status: 'active',
        paidBalanceCents: 500,
        promoBalanceCents: 100,
        totalBalanceCents: 600,
      ),
    );

    final subject = controller();
    await subject.init();

    expect(subject.walletBalance, 6.00);
  });

  group('uncertain attempt guard', () {
    late List<String> cardRequests;
    late List<String> walletRequests;
    late List<String> sheets;
    late String status;
    late String? failureStage;
    late Object failure;

    setUp(() {
      cardRequests = [];
      walletRequests = [];
      sheets = [];
      status = 'support_required';
      failureStage = null;
      failure = StateError('Transport result unavailable');
      when(() => authService.getCurrentUserId).thenReturn('user-1');
      when(() => walletService.getBalance()).thenAnswer(
        (_) async => const WalletBalance(
          walletAccountId: 'wallet-1', status: 'active',
          paidBalanceCents: 1000, promoBalanceCents: 0, totalBalanceCents: 1000,
        ),
      );
      when(() => vendService.quote(
        machineToken: 'token-1', terminalId: null, uniQr: null,
      )).thenAnswer((_) async => dryerQuote);
      when(() => vendService.createCardPayment(
        machineToken: 'token-1', terminalId: null, uniQr: null,
        amountCents: 150, clientRequestId: any(named: 'clientRequestId'),
      )).thenAnswer((invocation) async {
        cardRequests.add(invocation.namedArguments[#clientRequestId] as String);
        if (failureStage == 'create') throw failure;
        return const CortinaCardSession(
          sessionId: 'session-1', accessToken: 'access-1', clientSecret: 'secret-1',
        );
      });
      when(() => vendService.payWithWallet(
        machineToken: 'token-1', terminalId: null, uniQr: null,
        amountCents: 150, clientRequestId: any(named: 'clientRequestId'),
      )).thenAnswer((invocation) async {
        walletRequests.add(invocation.namedArguments[#clientRequestId] as String);
        if (failureStage == 'create') throw failure;
        return const CortinaVendReference(sessionId: 'session-1', accessToken: 'access-1');
      });
      when(() => vendService.confirmCardPayment(any())).thenAnswer((_) async {
        if (failureStage == 'confirm') throw failure;
      });
      when(() => vendService.status(any())).thenAnswer((_) async {
        if (failureStage == 'status') throw failure;
        return CortinaVendStatus(
          status: status, failureMessage: 'Your payment was returned. Try again.',
        );
      });
    });

    CortinaPaymentController guardedController() => controller(sheet: (secret) async {
      sheets.add(secret);
      if (failureStage == 'sheet') throw failure;
    });

    Future<void> expectBlocked(CortinaPaymentController subject) async {
      expect(subject.paymentLocked, isTrue);
      expect(subject.isProcessing, isFalse);
      expect(subject.paymentCompleted, isFalse);
      expect(subject.errorMessage, CortinaPaymentController.uncertainMessage);
      subject.setDryerAmount(200);
      expect(subject.amountCents, 150);
      final cardCount = cardRequests.length;
      final walletCount = walletRequests.length;
      final sheetCount = sheets.length;
      expect(await subject.payWithCard(), CortinaPaymentOutcome.pending);
      expect(await subject.payWithWallet(), CortinaPaymentOutcome.pending);
      expect(cardRequests, hasLength(cardCount));
      expect(walletRequests, hasLength(walletCount));
      expect(sheets, hasLength(sheetCount));
    }

    for (final card in [true, false]) {
      for (final value in ['payment_pending', 'support_required', 'timed_out', 'unknown', 'failed', 'voided']) {
        test('${card ? 'card' : 'wallet'} $value locks both methods and dryer changes', () async {
          status = value;
          final subject = guardedController();
          addTearDown(subject.dispose);
          await subject.init();
          expect(card ? await subject.payWithCard() : await subject.payWithWallet(), CortinaPaymentOutcome.pending);
          expect(card ? cardRequests : walletRequests, hasLength(1));
          expect(card ? walletRequests : cardRequests, isEmpty);
          await expectBlocked(subject);
        });
      }

      for (final stage in card ? ['create', 'sheet', 'confirm', 'status'] : ['create', 'status']) {
        test('${card ? 'card' : 'wallet'} $stage exception is not proof of an unsent payment', () async {
          failureStage = stage;
          final subject = guardedController();
          addTearDown(subject.dispose);
          await subject.init();
          expect(card ? await subject.payWithCard() : await subject.payWithWallet(), CortinaPaymentOutcome.pending);
          expect(card ? cardRequests : walletRequests, hasLength(1));
          await expectBlocked(subject);
        });
      }
    }

    test('genuine Payment Sheet cancellation unlocks without confirming or polling', () async {
      failureStage = 'sheet';
      failure = StripeException(error: LocalizedErrorMessage(code: FailureCode.Canceled));
      final subject = guardedController();
      addTearDown(subject.dispose);
      await subject.init();
      expect(await subject.payWithCard(), CortinaPaymentOutcome.canceled);
      expect(subject.paymentLocked, isFalse);
      expect(subject.errorMessage, isNull);
      expect(await subject.payWithCard(), CortinaPaymentOutcome.canceled);
      expect(cardRequests, hasLength(2));
      expect(cardRequests[0], cardRequests[1]);
      expect(sheets, hasLength(2));
      verifyNever(() => vendService.confirmCardPayment(any()));
      verifyNever(() => vendService.status(any()));
      subject.setDryerAmount(200);
      expect(subject.amountCents, 200);
    });

    for (final stage in ['create', 'confirm', 'status']) {
      test('a cancellation-shaped exception from $stage is not a Payment Sheet cancellation', () async {
        failureStage = stage;
        failure = StripeException(error: LocalizedErrorMessage(code: FailureCode.Canceled));
        final subject = guardedController();
        addTearDown(subject.dispose);
        await subject.init();
        expect(await subject.payWithCard(), CortinaPaymentOutcome.pending);
        await expectBlocked(subject);
      });
    }
  });

  group('wallet completion', () {
    WalletBalance balance(int cents) => WalletBalance(
      walletAccountId: 'wallet-1',
      status: 'active',
      paidBalanceCents: cents,
      promoBalanceCents: 0,
      totalBalanceCents: cents,
    );

    setUp(() {
      when(() => authService.getCurrentUserId).thenReturn('user-1');
      when(
        () => vendService.quote(
          machineToken: 'token-1',
          terminalId: null,
          uniQr: null,
        ),
      ).thenAnswer((_) async => dryerQuote);
      when(
        () => vendService.payWithWallet(
          machineToken: 'token-1',
          terminalId: null,
          uniQr: null,
          amountCents: 150,
          clientRequestId: any(named: 'clientRequestId'),
        ),
      ).thenAnswer(
        (_) async => const CortinaVendReference(
          sessionId: 'session-1',
          accessToken: 'access-1',
        ),
      );
      when(
        () => walletService.getBalance(),
      ).thenAnswer((_) async => balance(1100));
    });

    test(
      'refreshes the ledger balance and prevents another completed payment',
      () async {
        when(
          () => vendService.status(any()),
        ).thenAnswer((_) async => const CortinaVendStatus(status: 'started'));
        final subject = controller();
        await subject.init();
        when(
          () => walletService.getBalance(),
        ).thenAnswer((_) async => balance(950));

        expect(await subject.payWithWallet(), CortinaPaymentOutcome.success);
        expect(subject.walletBalance, 9.50);
        expect(await subject.payWithWallet(), CortinaPaymentOutcome.success);
        expect(await subject.payWithCard(), CortinaPaymentOutcome.success);
        subject.setDryerAmount(200);
        expect(subject.amountCents, 150);
        verify(
          () => vendService.payWithWallet(
            machineToken: 'token-1',
            terminalId: null,
            uniQr: null,
            amountCents: 150,
            clientRequestId: any(named: 'clientRequestId'),
          ),
        ).called(1);
        verify(() => walletService.getBalance()).called(2);
      },
    );

    for (final status in ['refunded', 'approved', 'support_required']) {
      test('refreshes balance for $status without reporting success', () async {
        when(
          () => vendService.status(any()),
        ).thenAnswer((_) async => CortinaVendStatus(status: status));
        final subject = controller();
        await subject.init();
        when(
          () => walletService.getBalance(),
        ).thenAnswer((_) async => balance(status == 'refunded' ? 1100 : 950));

        final outcome = await subject.payWithWallet();
        expect(
          outcome,
          status == 'refunded'
              ? CortinaPaymentOutcome.refunded
              : CortinaPaymentOutcome.pending,
        );
        expect(subject.walletBalance, status == 'refunded' ? 11 : 9.50);
        expect(subject.paymentCompleted, isFalse);
        verify(() => walletService.getBalance()).called(2);
      });
    }

    test(
      'failed balance refresh does not mask a successful vend or show stale funds',
      () async {
        when(
          () => vendService.status(any()),
        ).thenAnswer((_) async => const CortinaVendStatus(status: 'started'));
        final subject = controller();
        await subject.init();
        when(() => walletService.getBalance()).thenThrow(StateError('Offline'));

        expect(await subject.payWithWallet(), CortinaPaymentOutcome.success);
        expect(subject.paymentCompleted, isTrue);
        expect(subject.walletBalance, isNull);
        expect(subject.errorMessage, isNull);
      },
    );
  });
}
