import 'package:clean_stream_laundry_app/features/cortina_payment/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
    vendService = MockCortinaVendService();
    authService = MockAuthService();
    walletService = MockWalletService();
    when(() => authService.getCurrentUserId).thenReturn(null);
  });

  CortinaPaymentController controller() => CortinaPaymentController(
    machineToken: 'token-1',
    terminalId: null,
    uniQr: null,
    vendService: vendService,
    authService: authService,
    walletService: walletService,
    presentPaymentSheet: (_) async {},
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
    },
  );

  test('card payment stops when Stripe confirmation fails', () async {
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

    expect(outcome, CortinaPaymentOutcome.failed);
    expect(subject.errorMessage, 'Stripe has not confirmed this payment');
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
}
