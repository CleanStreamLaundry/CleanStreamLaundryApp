import 'dart:async';

import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Vend extends Mock implements CortinaVendService {}
class _Auth extends Mock implements AuthService {}
class _Wallet extends Mock implements WalletService {}
class _Store extends Mock implements CortinaPendingStore {}

const requestId = '00000000-0000-4000-8000-000000000007';
const reference = CortinaVendReference(
  sessionId: '00000000-0000-4000-8000-000000000008', accessToken: requestId,
);
const quote = CortinaQuote(
  machineId: 7, machineName: 'Dryer 7', machineType: 'dryer', washerSizeLabel: null,
  amountCents: 150, dryerDefaultCents: 150,
  dryerOptions: [CortinaDryerOption(minutes: 30, amountCents: 150)],
);

void main() {
  setUpAll(() => registerFallbackValue(reference));
  late _Vend vend;
  late _Auth auth;
  late _Wallet wallet;
  late CortinaPendingStore store;
  late StreamController<AuthState> events;
  late List<CortinaPaymentController> subjects;
  late List<String> calls;
  late String scope;
  late String status;
  String? account;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    vend = _Vend(); auth = _Auth(); wallet = _Wallet();
    store = CortinaPendingStore(project: 'https://test.invalid');
    account = 'owner'; scope = store.scope(accountId: account, machineId: 7);
    calls = []; subjects = []; status = 'started';
    events = StreamController<AuthState>.broadcast(sync: true);
    when(() => auth.getCurrentUserId).thenAnswer((_) => account);
    when(() => auth.authStateChanges).thenAnswer((_) => events.stream);
    when(() => vend.quote(machineToken: 'qr', terminalId: null, uniQr: null))
      .thenAnswer((_) async => quote);
    when(() => wallet.getBalance()).thenAnswer((_) async => const WalletBalance(
      walletAccountId: 'wallet', status: 'active', paidBalanceCents: 1000,
      promoBalanceCents: 0, totalBalanceCents: 1000,
    ));
    when(() => vend.recoverPendingPayment(
      clientRequestId: any(named: 'clientRequestId'), machineId: 7,
    )).thenAnswer((invocation) async {
      calls.add('lookup');
      final id = invocation.namedArguments[#clientRequestId] as String;
      expect((await store.read(scope))?.requestId, id);
      return CortinaVendReference(sessionId: reference.sessionId, accessToken: id);
    });
    when(() => vend.status(any())).thenAnswer((invocation) async {
      calls.add('status');
      final saved = await store.read(scope);
      final checked = invocation.positionalArguments.single as CortinaVendReference;
      expect(saved?.reference?.sessionId, checked.sessionId);
      expect(saved?.reference?.accessToken, checked.accessToken);
      return CortinaVendStatus(status: status);
    });
  });

  tearDown(() async {
    for (final subject in subjects) { subject.dispose(); }
    await events.close();
  });

  CortinaPaymentController controller({CortinaPendingStore? storage}) {
    final result = CortinaPaymentController(
      machineToken: 'qr', terminalId: null, uniQr: null, vendService: vend,
      authService: auth, walletService: wallet, pendingStore: storage ?? store,
      presentPaymentSheet: (_) async { calls.add('sheet'); },
      pollAttempts: 1, delay: (_) async {},
    );
    subjects.add(result); return result;
  }

  Future<void> seed({String method = 'card', bool bound = false}) => store.claim(scope,
    CortinaPendingPayment(requestId: requestId, method: method, amountCents: 150,
      reference: bound ? reference : null));

  void noFinancialCalls() {
    verifyNever(() => vend.createCardPayment(
      machineToken: any(named: 'machineToken'), terminalId: null, uniQr: null,
      amountCents: any(named: 'amountCents'), clientRequestId: any(named: 'clientRequestId'),
    ));
    verifyNever(() => vend.payWithWallet(
      machineToken: any(named: 'machineToken'), terminalId: null, uniQr: null,
      amountCents: any(named: 'amountCents'), clientRequestId: any(named: 'clientRequestId'),
    ));
    verifyNever(() => vend.confirmCardPayment(any()));
    expect(calls, isNot(contains('sheet')));
  }

  for (final method in ['card', 'wallet']) {
    test('owned unbound $method marker resumes, persists reference, then observes terminal state', () async {
      await seed(method: method);
      final subject = controller(); await subject.init();
      expect(calls, ['lookup', 'status']);
      expect(subject.restoredOutcome, CortinaPaymentOutcome.success);
      expect(subject.paymentCompleted, isTrue);
      expect(await store.read(scope), isNull);
      noFinancialCalls();
    });
  }

  test('unbound guest marker remains support-only without owner lookup', () async {
    account = null; scope = store.scope(accountId: null, machineId: 7);
    await seed(); final subject = controller(); await subject.init();
    expect(subject.restoredOutcome, CortinaPaymentOutcome.pending);
    expect(subject.paymentLocked, isTrue);
    expect((await store.read(scope))?.reference, isNull);
    expect(calls, isEmpty);
    verifyNever(() => vend.recoverPendingPayment(clientRequestId: any(named: 'clientRequestId'), machineId: 7));
    noFinancialCalls();
  });

  for (final code in [400, 401, 403, 404, 503]) {
    test('owner lookup $code never unlocks or discards a possibly dispatched attempt', () async {
      await seed();
      when(() => vend.recoverPendingPayment(clientRequestId: requestId, machineId: 7))
        .thenThrow(StateError('lookup $code'));
      final subject = controller(); await subject.init();
      expect(subject.restoredOutcome, CortinaPaymentOutcome.pending);
      expect(subject.paymentLocked, isTrue);
      expect(await subject.payWithCard(), CortinaPaymentOutcome.pending);
      expect(await subject.payWithWallet(), CortinaPaymentOutcome.pending);
      expect((await store.read(scope))?.requestId, requestId);
      expect((await store.read(scope))?.reference, isNull);
      expect(calls, isEmpty);
      noFinancialCalls();
    });
  }

  test('A to B to A during owner lookup rejects stale reference and terminal display', () async {
    await seed();
    final response = Completer<CortinaVendReference>();
    when(() => vend.recoverPendingPayment(clientRequestId: requestId, machineId: 7))
      .thenAnswer((_) => response.future);
    final subject = controller(); final init = subject.init();
    await untilCalled(() => vend.recoverPendingPayment(clientRequestId: requestId, machineId: 7));
    account = 'other'; events.add(AuthState(AuthChangeEvent.signedOut, null));
    account = 'owner'; response.complete(reference); await init;
    expect(subject.restoredOutcome, isNull);
    expect(subject.paymentCompleted, isFalse);
    expect(subject.paymentLocked, isTrue);
    expect((await store.read(scope))?.reference, isNull);
    expect(calls, isEmpty); noFinancialCalls();
  });

  test('disposed owner lookup does not attach or poll a late response', () async {
    await seed();
    final response = Completer<CortinaVendReference>();
    when(() => vend.recoverPendingPayment(clientRequestId: requestId, machineId: 7))
      .thenAnswer((_) => response.future);
    final subject = controller(); final init = subject.init();
    await untilCalled(() => vend.recoverPendingPayment(clientRequestId: requestId, machineId: 7));
    subject.dispose(); subjects.remove(subject);
    response.complete(reference); await init;
    expect((await store.read(scope))?.reference, isNull);
    expect(calls, isEmpty); noFinancialCalls();
  });

  test('recovered-reference storage failure prevents polling and leaves both methods locked', () async {
    await seed();
    final failing = _Store();
    when(() => failing.scope(accountId: 'owner', machineId: 7)).thenReturn(scope);
    when(() => failing.read(scope)).thenAnswer((_) => store.read(scope));
    when(() => failing.attach(scope, requestId, any())).thenThrow(StateError('secure store unavailable'));
    final subject = controller(storage: failing); await subject.init();
    expect(subject.restoredOutcome, CortinaPaymentOutcome.pending);
    expect(subject.paymentLocked, isTrue);
    expect(calls, ['lookup']);
    expect((await store.read(scope))?.reference, isNull); noFinancialCalls();
  });

  test('already-bound reference skips owner lookup and uses existing status', () async {
    await seed(bound: true);
    final subject = controller(); await subject.init();
    expect(subject.restoredOutcome, CortinaPaymentOutcome.success);
    expect(calls, ['status']);
    verifyNever(() => vend.recoverPendingPayment(clientRequestId: any(named: 'clientRequestId'), machineId: 7));
    noFinancialCalls();
  });

  test('actual lost create response recovers after restart without a second create or sheet', () async {
    when(() => vend.createCardPayment(
      machineToken: 'qr', terminalId: null, uniQr: null, amountCents: 150,
      clientRequestId: any(named: 'clientRequestId'),
    )).thenThrow(StateError('response lost after dispatch'));
    final first = controller(); await first.init();
    expect(await first.payWithCard(), CortinaPaymentOutcome.pending);
    final original = await store.read(scope);
    expect(original, isNotNull); expect(original?.reference, isNull);
    first.dispose(); subjects.remove(first);
    final restarted = controller(); await restarted.init();
    expect(restarted.restoredOutcome, CortinaPaymentOutcome.success);
    expect(calls, ['lookup', 'status']);
    expect(await store.read(scope), isNull);
    verify(() => vend.createCardPayment(
      machineToken: 'qr', terminalId: null, uniQr: null, amountCents: 150,
      clientRequestId: original!.requestId,
    )).called(1);
    verifyNever(() => vend.confirmCardPayment(any()));
  });

  test('404 stays locked but a later reopened lookup can observe the committed attempt', () async {
    await seed();
    when(() => vend.recoverPendingPayment(clientRequestId: requestId, machineId: 7))
      .thenThrow(StateError('lookup 404'));
    final first = controller(); await first.init();
    expect(first.paymentLocked, isTrue);
    first.dispose(); subjects.remove(first);
    when(() => vend.recoverPendingPayment(clientRequestId: requestId, machineId: 7))
      .thenAnswer((_) async { calls.add('lookup'); return reference; });
    status = 'refunded';
    final reopened = controller(); await reopened.init();
    expect(reopened.restoredOutcome, CortinaPaymentOutcome.refunded);
    expect(await store.read(scope), isNull);
    expect(calls, ['lookup', 'status']); noFinancialCalls();
  });
}
