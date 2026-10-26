import 'dart:async';

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
import 'package:supabase_flutter/supabase_flutter.dart';

class _Vend extends Mock implements CortinaVendService {}
class _Auth extends Mock implements AuthService {}
class _Wallet extends Mock implements WalletService {}
class _Store extends Mock implements CortinaPendingStore {}

const _reference = CortinaVendReference(sessionId: 'session', accessToken: 'capability');
const _quote = CortinaQuote(
  machineId: 7, machineName: 'Dryer 7', machineType: 'dryer',
  washerSizeLabel: null, amountCents: 150, dryerDefaultCents: 150,
  dryerOptions: [
    CortinaDryerOption(minutes: 30, amountCents: 150),
    CortinaDryerOption(minutes: 40, amountCents: 200),
  ],
);

void main() {
  setUpAll(() {
    registerFallbackValue(_reference);
    registerFallbackValue(const CortinaPendingPayment(
      requestId: 'fallback', method: 'card', amountCents: 150,
    ));
  });

  late _Vend vend;
  late _Auth auth;
  late _Wallet wallet;
  late CortinaPendingStore store;
  late StreamController<AuthState> authEvents;
  late List<CortinaPaymentController> subjects;
  late List<String> calls;
  String? account;
  late String serverStatus;
  late String scope;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    vend = _Vend(); auth = _Auth(); wallet = _Wallet();
    authEvents = StreamController<AuthState>.broadcast(sync: true);
    store = CortinaPendingStore(project: 'https://test.invalid');
    scope = store.scope(accountId: 'owner', machineId: 7);
    subjects = []; calls = []; account = 'owner'; serverStatus = 'support_required';
    when(() => auth.getCurrentUserId).thenAnswer((_) => account);
    when(() => auth.authStateChanges).thenAnswer((_) => authEvents.stream);
    when(() => vend.recoverPendingPayment(
      clientRequestId: any(named: 'clientRequestId'), machineId: any(named: 'machineId'),
    )).thenThrow(StateError('Recovery unavailable'));
    when(() => vend.quote(
      machineToken: any(named: 'machineToken'), terminalId: null, uniQr: null,
    )).thenAnswer((_) async => _quote);
    when(() => wallet.getBalance()).thenAnswer((_) async => const WalletBalance(
      walletAccountId: 'wallet', status: 'active', paidBalanceCents: 1000,
      promoBalanceCents: 0, totalBalanceCents: 1000,
    ));
    when(() => vend.createCardPayment(
      machineToken: any(named: 'machineToken'), terminalId: null, uniQr: null,
      amountCents: any(named: 'amountCents'), clientRequestId: any(named: 'clientRequestId'),
    )).thenAnswer((_) async {
      calls.add('create');
      expect((await store.read(scope))?.reference, isNull);
      expect(await store.read(scope), isNotNull);
      return const CortinaCardSession(
        sessionId: 'session', accessToken: 'capability', clientSecret: 'not-persisted',
      );
    });
    when(() => vend.payWithWallet(
      machineToken: any(named: 'machineToken'), terminalId: null, uniQr: null,
      amountCents: any(named: 'amountCents'), clientRequestId: any(named: 'clientRequestId'),
    )).thenAnswer((_) async {
      calls.add('wallet');
      expect(await store.read(scope), isNotNull);
      return _reference;
    });
    when(() => vend.confirmCardPayment(any())).thenAnswer((_) async {
      calls.add('confirm');
    });
    when(() => vend.status(any())).thenAnswer((invocation) async {
      calls.add('status');
      final ref = invocation.positionalArguments.single as CortinaVendReference;
      expect(ref.sessionId, _reference.sessionId);
      expect(ref.accessToken, _reference.accessToken);
      return CortinaVendStatus(status: serverStatus);
    });
  });

  tearDown(() async {
    for (final subject in subjects) { subject.dispose(); }
    await authEvents.close();
  });

  CortinaPaymentController controller({
    CortinaPendingStore? storage,
    String token = 'qr',
    Future<void> Function(String)? sheet,
  }) {
    final subject = CortinaPaymentController(
      machineToken: token, terminalId: null, uniQr: null,
      vendService: vend, authService: auth, walletService: wallet,
      pendingStore: storage ?? store, pollAttempts: 1, delay: (_) async {},
      presentPaymentSheet: sheet ?? (_) async {
        calls.add('sheet');
        expect((await store.read(scope))?.reference?.sessionId, 'session');
      },
    );
    subjects.add(subject);
    return subject;
  }

  Future<void> seed({String method = 'card', bool bound = true, String? key}) async {
    await store.claim(key ?? scope, CortinaPendingPayment(
      requestId: 'original-request', method: method, amountCents: 200,
      reference: bound ? _reference : null,
    ));
  }

  for (final method in ['card', 'wallet']) {
    test('$method persists before dispatch and recovers only status after recreation', () async {
      final first = controller();
      await first.init();
      first.setDryerAmount(200);
      expect(method == 'card' ? await first.payWithCard() : await first.payWithWallet(),
        CortinaPaymentOutcome.pending);
      final before = await store.read(scope);
      expect(before?.amountCents, 200);
      expect(before?.method, method);
      first.dispose(); subjects.remove(first);
      calls.clear();
      // A new adapter/controller reads the saved secure platform values.
      final restarted = controller(storage: CortinaPendingStore(project: 'https://test.invalid'));
      await restarted.init();
      expect(calls, ['status']);
      expect(restarted.restoredOutcome, CortinaPaymentOutcome.pending);
      expect(restarted.paymentLocked, isTrue);
      expect(restarted.amountCents, 200);
      restarted.setDryerAmount(150);
      expect(restarted.amountCents, 200);
      expect(await restarted.payWithCard(), CortinaPaymentOutcome.pending);
      expect(await restarted.payWithWallet(), CortinaPaymentOutcome.pending);
      expect(calls, ['status']);
      expect((await store.read(scope))?.requestId, before?.requestId);
      final raw = (await const FlutterSecureStorage().read(key: scope))!;
      expect(raw, isNot(contains('not-persisted')));
      expect(raw, isNot(contains('clientSecret')));
    });

    test('$method lost create response survives restart without replay', () async {
      await seed(method: method, bound: false);
      final restarted = controller();
      await restarted.init();
      expect(restarted.restoredOutcome, CortinaPaymentOutcome.pending);
      expect(restarted.errorMessage, CortinaPaymentController.uncertainMessage);
      expect(await restarted.payWithCard(), CortinaPaymentOutcome.pending);
      expect(await restarted.payWithWallet(), CortinaPaymentOutcome.pending);
      expect(calls, isEmpty);
      expect((await store.read(scope))?.requestId, 'original-request');
    });

    for (final terminal in ['started', 'refunded']) {
      test('$method restored $terminal clears only its checkpoint', () async {
        await seed(method: method);
        final otherScope = store.scope(accountId: 'owner', machineId: 8);
        await seed(key: otherScope);
        serverStatus = terminal;
        final restarted = controller();
        await restarted.init();
        expect(restarted.restoredOutcome, terminal == 'started'
          ? CortinaPaymentOutcome.success : CortinaPaymentOutcome.refunded);
        expect(restarted.paymentCompleted, terminal == 'started');
        expect(await store.read(scope), isNull);
        expect(await store.read(otherScope), isNotNull);
        expect(calls, ['status']);
      });
    }
  }

  for (final status in ['payment_pending', 'timed_out', 'failed', 'unknown']) {
    test('restored $status remains unconfirmed and retained', () async {
      await seed(); serverStatus = status;
      final subject = controller(); await subject.init();
      expect(subject.restoredOutcome, CortinaPaymentOutcome.pending);
      expect(subject.paymentLocked, isTrue);
      expect(subject.paymentCompleted, isFalse);
      expect(await store.read(scope), isNotNull);
      expect(calls, ['status']);
    });
  }

  test('status transport failure retains the original reference', () async {
    await seed();
    when(() => vend.status(any())).thenThrow(StateError('offline'));
    final subject = controller(); await subject.init();
    expect(subject.restoredOutcome, CortinaPaymentOutcome.pending);
    expect(subject.paymentLocked, isTrue);
    expect((await store.read(scope))?.reference?.sessionId, 'session');
    expect(calls, isEmpty);
  });

  test('restart while Payment Sheet is unresolved observes without presenting again', () async {
    final enteredSheet = Completer<void>();
    final sheetResult = Completer<void>();
    final first = controller(sheet: (_) async {
      enteredSheet.complete();
      await sheetResult.future;
    });
    await first.init();
    final payment = first.payWithCard();
    await enteredSheet.future;
    expect((await store.read(scope))?.reference?.sessionId, 'session');
    first.dispose(); subjects.remove(first);
    calls.clear();
    final restarted = controller(); await restarted.init();
    expect(calls, ['status']);
    expect(restarted.paymentLocked, isTrue);
    sheetResult.complete();
    expect(await payment, CortinaPaymentOutcome.pending);
    expect(calls, ['status']);
    expect(await store.read(scope), isNotNull);
  });

  test('different account and guest do not read or clear the owner checkpoint', () async {
    await seed();
    for (final user in ['other', null]) {
      account = user;
      final subject = controller(); await subject.init();
      expect(subject.restoredOutcome, isNull);
      expect(subject.paymentLocked, isFalse);
      expect(await store.read(scope), isNotNull);
    }
    expect(calls, isEmpty);
  });

  test('different project and machine do not reuse a saved reference', () async {
    await seed();
    final otherProject = controller(storage: CortinaPendingStore(project: 'https://other.invalid'));
    await otherProject.init();
    expect(otherProject.restoredOutcome, isNull);
    when(() => vend.quote(machineToken: 'other-machine', terminalId: null, uniQr: null))
      .thenAnswer((_) async => const CortinaQuote(
        machineId: 8, machineName: 'Other location', machineType: 'washer',
        washerSizeLabel: null, amountCents: 400, dryerDefaultCents: 150, dryerOptions: [],
      ));
    final otherMachine = controller(token: 'other-machine'); await otherMachine.init();
    expect(otherMachine.restoredOutcome, isNull);
    expect(calls, isEmpty);
    expect(await store.read(scope), isNotNull);
  });

  test('another QR for the same quoted machine cannot bypass the lock', () async {
    await seed();
    final subject = controller(token: 'alias-qr'); await subject.init();
    expect(subject.paymentLocked, isTrue);
    expect(calls, ['status']);
  });

  test('A to B to A while status waits cannot settle or show old payment', () async {
    await seed();
    final response = Completer<CortinaVendStatus>();
    when(() => vend.status(any())).thenAnswer((_) => response.future);
    final subject = controller();
    final init = subject.init();
    await untilCalled(() => vend.status(any()));
    account = 'other';
    authEvents.add(AuthState(AuthChangeEvent.signedOut, null));
    account = 'owner';
    response.complete(const CortinaVendStatus(status: 'started'));
    await init;
    expect(subject.restoredOutcome, isNull);
    expect(subject.paymentCompleted, isFalse);
    expect(subject.paymentLocked, isTrue);
    expect(await store.read(scope), isNotNull);
  });

  test('disposal during status cannot publish success or clear recovery', () async {
    await seed();
    final response = Completer<CortinaVendStatus>();
    when(() => vend.status(any())).thenAnswer((_) => response.future);
    final subject = controller(); final init = subject.init();
    await untilCalled(() => vend.status(any()));
    subject.dispose(); subjects.remove(subject);
    response.complete(const CortinaVendStatus(status: 'started')); await init;
    expect(subject.paymentCompleted, isFalse);
    expect(await store.read(scope), isNotNull);
  });

  test('late card create response is saved for its owner but never presents a sheet', () async {
    final response = Completer<CortinaCardSession>();
    when(() => vend.createCardPayment(
      machineToken: 'qr', terminalId: null, uniQr: null, amountCents: 150,
      clientRequestId: any(named: 'clientRequestId'),
    )).thenAnswer((_) => response.future);
    final subject = controller(); await subject.init();
    final payment = subject.payWithCard();
    await untilCalled(() => vend.createCardPayment(
      machineToken: 'qr', terminalId: null, uniQr: null, amountCents: 150,
      clientRequestId: any(named: 'clientRequestId'),
    ));
    account = 'other'; authEvents.add(AuthState(AuthChangeEvent.signedOut, null));
    response.complete(const CortinaCardSession(
      sessionId: 'session', accessToken: 'capability', clientSecret: 'not-persisted',
    ));
    expect(await payment, CortinaPaymentOutcome.pending);
    expect((await store.read(scope))?.reference?.sessionId, 'session');
    expect(calls, isEmpty);
    expect(await store.read(store.scope(accountId: 'other', machineId: 7)), isNull);
  });

  for (final stage in ['claim', 'attach', 'clear']) {
    test('$stage storage failure fails closed without continuing payment', () async {
      final failing = _Store();
      when(() => failing.scope(accountId: 'owner', machineId: 7)).thenReturn(scope);
      when(() => failing.read(scope)).thenAnswer((_) => store.read(scope));
      when(() => failing.claim(scope, any())).thenAnswer((invocation) async {
        if (stage == 'claim') throw StateError('write failed');
        await store.claim(scope, invocation.positionalArguments[1] as CortinaPendingPayment);
      });
      when(() => failing.attach(scope, any(), any())).thenAnswer((invocation) async {
        if (stage == 'attach') throw StateError('write failed');
        await store.attach(scope, invocation.positionalArguments[1] as String, _reference);
      });
      when(() => failing.clear(scope, any())).thenThrow(StateError('write failed'));
      serverStatus = 'started';
      final subject = controller(storage: failing); await subject.init();
      expect(await subject.payWithCard(), CortinaPaymentOutcome.pending);
      expect(subject.paymentCompleted, isFalse);
      expect(subject.paymentLocked, isTrue);
      expect(calls, stage == 'claim' ? <String>[] : stage == 'attach'
        ? ['create'] : ['create', 'sheet', 'confirm', 'status']);
      expect(await subject.payWithWallet(), CortinaPaymentOutcome.pending);
      if (stage != 'claim') expect(await store.read(scope), isNotNull);
    });
  }

  test('corrupt stored record is retained and blocks both methods', () async {
    const storage = FlutterSecureStorage();
    await storage.write(key: scope, value: '{invalid');
    final subject = controller(); await subject.init();
    expect(subject.paymentLocked, isTrue);
    expect(subject.errorMessage, CortinaPaymentController.uncertainMessage);
    expect(await subject.payWithCard(), CortinaPaymentOutcome.pending);
    expect(await subject.payWithWallet(), CortinaPaymentOutcome.pending);
    expect(await storage.read(key: scope), '{invalid');
    expect(calls, isEmpty);
  });
}
