import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class _Vend extends Mock implements CortinaVendService {}

class _Auth extends Mock implements AuthService {}

class _Wallet extends Mock implements WalletService {}

const _quote = CortinaQuote(
  machineId: 7,
  machineName: 'Dryer 7',
  machineType: 'dryer',
  washerSizeLabel: null,
  amountCents: 150,
  dryerDefaultCents: 150,
  dryerOptions: [CortinaDryerOption(minutes: 30, amountCents: 150)],
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

  late _Vend vend;
  late _Auth auth;
  late _Wallet wallet;
  late CortinaPaymentController subject;
  late List<String> cardRequests;
  late List<String> walletRequests;
  late List<String> sheets;
  late List<CortinaVendReference> checkedReferences;
  late String serverStatus;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    vend = _Vend();
    auth = _Auth();
    wallet = _Wallet();
    cardRequests = [];
    walletRequests = [];
    sheets = [];
    checkedReferences = [];
    serverStatus = 'support_required';
    when(() => auth.getCurrentUserId).thenReturn('user-1');
    when(() => auth.authStateChanges).thenAnswer((_) => const Stream.empty());
    when(() => wallet.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet-1',
        status: 'active',
        paidBalanceCents: 1000,
        promoBalanceCents: 0,
        totalBalanceCents: 1000,
      ),
    );
    when(
      () => vend.quote(
        machineToken: 'machine-token',
        terminalId: null,
        uniQr: null,
      ),
    ).thenAnswer((_) async => _quote);
    when(
      () => vend.createCardPayment(
        machineToken: 'machine-token',
        terminalId: null,
        uniQr: null,
        amountCents: 150,
        clientRequestId: any(named: 'clientRequestId'),
      ),
    ).thenAnswer((invocation) async {
      cardRequests.add(invocation.namedArguments[#clientRequestId] as String);
      return CortinaCardSession(
        sessionId: 'card-${cardRequests.length}',
        accessToken: 'card-access',
        clientSecret: 'card-secret',
      );
    });
    when(
      () => vend.payWithWallet(
        machineToken: 'machine-token',
        terminalId: null,
        uniQr: null,
        amountCents: 150,
        clientRequestId: any(named: 'clientRequestId'),
      ),
    ).thenAnswer((invocation) async {
      walletRequests.add(invocation.namedArguments[#clientRequestId] as String);
      return CortinaVendReference(
        sessionId: 'wallet-${walletRequests.length}',
        accessToken: 'wallet-access',
      );
    });
    when(() => vend.confirmCardPayment(any())).thenAnswer((_) async {});
    when(() => vend.status(any())).thenAnswer((invocation) async {
      checkedReferences.add(
        invocation.positionalArguments.single as CortinaVendReference,
      );
      return CortinaVendStatus(status: serverStatus);
    });
    subject = CortinaPaymentController(
      machineToken: 'machine-token',
      terminalId: null,
      uniQr: null,
      vendService: vend,
      authService: auth,
      walletService: wallet,
      pendingStore: CortinaPendingStore(project: 'https://test.invalid'),
      presentPaymentSheet: (secret) async { sheets.add(secret); },
      delay: (_) async {},
      pollAttempts: 1,
    );
  });

  tearDown(() => subject.dispose());

  for (final card in [true, false]) {
    final method = card ? 'card' : 'wallet';

    test('$method support-required cannot create a new payment on retry', () async {
      await subject.init();
      final first = card ? await subject.payWithCard() : await subject.payWithWallet();
      expect(first, isNot(CortinaPaymentOutcome.success));
      expect(first, isNot(CortinaPaymentOutcome.refunded));
      final retry = card ? await subject.payWithCard() : await subject.payWithWallet();
      expect(retry, isNot(CortinaPaymentOutcome.success));
      expect(retry, isNot(CortinaPaymentOutcome.refunded));
      expect(card ? cardRequests : walletRequests, hasLength(1));
      expect(card ? walletRequests : cardRequests, isEmpty);
      expect(sheets, hasLength(card ? 1 : 0));
      expect(checkedReferences.map((r) => r.sessionId).toSet(), {card ? 'card-1' : 'wallet-1'});
    });

    test('$method pending session blocks a new payment through the other method', () async {
      serverStatus = 'approved';
      await subject.init();
      final first = card ? await subject.payWithCard() : await subject.payWithWallet();
      expect(first, CortinaPaymentOutcome.pending);
      final second = card ? await subject.payWithWallet() : await subject.payWithCard();
      expect(second, isNot(CortinaPaymentOutcome.success));
      expect(second, isNot(CortinaPaymentOutcome.refunded));
      expect(card ? cardRequests : walletRequests, hasLength(1));
      expect(card ? walletRequests : cardRequests, isEmpty);
      expect(sheets, hasLength(card ? 1 : 0));
      expect(checkedReferences.map((r) => r.sessionId).toSet(), {card ? 'card-1' : 'wallet-1'});
    });

    test('$method confirmed refund preserves the existing fresh retry contract', () async {
      serverStatus = 'refunded';
      await subject.init();
      final first = card ? await subject.payWithCard() : await subject.payWithWallet();
      final second = card ? await subject.payWithCard() : await subject.payWithWallet();
      expect(first, CortinaPaymentOutcome.refunded);
      expect(second, CortinaPaymentOutcome.refunded);
      final requests = card ? cardRequests : walletRequests;
      expect(requests, hasLength(2));
      expect(requests[1], isNot(requests[0]));
      expect(card ? walletRequests : cardRequests, isEmpty);
      expect(sheets, hasLength(card ? 2 : 0));
    });
  }
}
