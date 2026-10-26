@TestOn('browser')
library;

import 'dart:async';
import 'dart:html' as html;

import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/services/stripe/stripe_service_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockAuth extends Mock implements AuthService {}

class MockEdge extends Mock implements EdgeFunctionService {}

class Popup extends Fake implements html.WindowBase {
  @override
  bool closed = false;
  int closeCalls = 0;

  @override
  void close() {
    closed = true;
    closeCalls += 1;
  }
}

class BrowserStripe extends StripeService {
  html.WindowBase? popup = Popup();
  bool useRealPopup = false;
  final openedUrls = <String>[];

  @override
  html.WindowBase? openCheckout(String url) {
    openedUrls.add(url);
    if (useRealPopup) popup = super.openCheckout(url);
    return popup;
  }
}

// DOM listener cancellation uses browser futures outside Flutter's fake clock.
Future<T> finishPayment<T>(WidgetTester tester, Future<T> payment) async {
  await tester.runAsync(() async {});
  await tester.pump();
  return payment;
}

void main() {
  late MockAuth auth;
  late MockEdge edge;
  late StreamController<bool> authEvents;
  late BrowserStripe subject;
  String? userId;
  var statusCalls = 0;

  Map<String, dynamic> status({
    String paymentStatus = 'succeeded',
    String legacyStatus = 'paid',
    String purpose = 'direct_machine_payment',
    bool walletReady = false,
  }) => {
    'session_id': 'cs_current',
    'status': legacyStatus,
    'paymentStatus': paymentStatus,
    'paymentIntentId': 'pi_current',
    'purpose': purpose,
    'amountCents': 275,
    'currency': 'usd',
    'walletLoadRecorded': walletReady,
  };

  void respond(Object? data, {int code = 200}) {
    when(
      () => edge.runEdgeFunction(
        name: 'checkPaymentResult',
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async {
      statusCalls += 1;
      return FunctionResponse(status: code, data: data);
    });
  }

  setUp(() async {
    await GetIt.instance.reset();
    auth = MockAuth();
    edge = MockEdge();
    authEvents = StreamController<bool>.broadcast(sync: true);
    userId = 'user-current';
    statusCalls = 0;
    when(() => auth.getCurrentUserId).thenAnswer((_) => userId);
    when(() => auth.onAuthChange).thenAnswer((_) => authEvents.stream);
    GetIt.instance.registerSingleton<AuthService>(auth);
    GetIt.instance.registerSingleton<EdgeFunctionService>(edge);
    when(
      () => edge.runEdgeFunction(
        name: 'createCheckoutSession',
        body: any(named: 'body'),
      ),
    ).thenAnswer(
      (_) async => FunctionResponse(
        status: 200,
        data: {'url': 'about:blank', 'session_id': 'cs_current'},
      ),
    );
    respond(status());
    subject = BrowserStripe();
  });

  tearDown(() async {
    expect(authEvents.hasListener, isFalse);
    await authEvents.close();
    await GetIt.instance.reset();
  });

  testWidgets('confirmed session succeeds with exact request payloads', (
    tester,
  ) async {
    final payment = subject.makePayment(2.75);
    await tester.pump();
    expect(subject.openedUrls, ['about:blank']);
    await tester.pump(const Duration(seconds: 2));
    expect(statusCalls, 1);
    expect(subject.popup!.closed, isTrue);
    expect(authEvents.hasListener, isFalse);
    expect(await finishPayment(tester, payment), PaymentResult.success);
    verify(
      () => edge.runEdgeFunction(
        name: 'createCheckoutSession',
        body: {'amount': 275, 'purpose': 'directMachinePayment'},
      ),
    ).called(1);
    verify(
      () => edge.runEdgeFunction(
        name: 'checkPaymentResult',
        body: {'session_id': 'cs_current'},
      ),
    ).called(1);
    expect((subject.popup as Popup).closeCalls, 1);
    await tester.pump(const Duration(minutes: 3));
    expect(statusCalls, 1);
  });

  for (final ready in [false, true]) {
    testWidgets('wallet success requires recorded ledger: $ready', (
      tester,
    ) async {
      respond(status(purpose: 'wallet_load', walletReady: ready));
      final payment = subject.makePayment(
        2.75,
        purpose: PaymentPurpose.walletLoad,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(
        await finishPayment(tester, payment),
        ready ? PaymentResult.success : PaymentResult.pending,
      );
      verify(
        () => edge.runEdgeFunction(
          name: 'createCheckoutSession',
          body: {'amount': 275, 'purpose': 'walletLoad'},
        ),
      ).called(1);
    });
  }

  for (final entry in <String, Object?>{
    'session_id': 'cs_other',
    'purpose': 'wallet_load',
    'amountCents': 276,
    'currency': 'eur',
    'paymentIntentId': null,
    'walletLoadRecorded': 'true',
    'paymentStatus': 'unknown',
    'status': 'unpaid',
  }.entries) {
    testWidgets('mismatched or unconfirmed ${entry.key} stays pending', (
      tester,
    ) async {
      respond({...status(), entry.key: entry.value});
      final payment = subject.makePayment(2.75);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(await finishPayment(tester, payment), PaymentResult.pending);
      await tester.pump(const Duration(minutes: 3));
      expect(statusCalls, 1);
    });
  }

  for (final data in [
    null,
    'paid',
    {'status': 'paid'},
    {...status(), 'amountCents': 275.5},
  ]) {
    testWidgets('malformed or legacy-only status stays pending: $data', (
      tester,
    ) async {
      respond(data);
      final payment = subject.makePayment(2.75);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(await finishPayment(tester, payment), PaymentResult.pending);
    });
  }

  testWidgets('only authoritative unpaid cancellation returns canceled', (
    tester,
  ) async {
    respond(status(paymentStatus: 'canceled', legacyStatus: 'unpaid'));
    final payment = subject.makePayment(2.75);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await finishPayment(tester, payment), PaymentResult.canceled);
  });

  testWidgets('paid cancellation contradiction stays pending', (tester) async {
    respond(status(paymentStatus: 'canceled'));
    final payment = subject.makePayment(2.75);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await finishPayment(tester, payment), PaymentResult.pending);
  });

  testWidgets('processing backs off 2, 3, 4, 5 seconds and stays capped', (
    tester,
  ) async {
    respond(status(paymentStatus: 'processing', legacyStatus: 'unpaid'));
    final payment = subject.makePayment(2.75);
    await tester.pump();
    for (final delay in [2, 3, 4, 5, 5]) {
      final before = statusCalls;
      await tester.pump(Duration(seconds: delay - 1));
      expect(statusCalls, before);
      await tester.pump(const Duration(seconds: 1));
      expect(statusCalls, before + 1);
    }
    respond(status());
    await tester.pump(const Duration(seconds: 5));
    expect(await finishPayment(tester, payment), PaymentResult.success);
  });

  testWidgets(
    'slow requests never overlap and duplicate launches are guarded',
    (tester) async {
      final reply = Completer<FunctionResponse?>();
      when(
        () => edge.runEdgeFunction(
          name: 'checkPaymentResult',
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) {
        statusCalls += 1;
        return reply.future;
      });
      final payment = subject.makePayment(2.75);
      expect(await subject.makePayment(2.75), PaymentResult.pending);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(await subject.makePayment(2.75), PaymentResult.pending);
      await tester.pump(const Duration(seconds: 20));
      expect(statusCalls, 1);
      expect(subject.openedUrls, hasLength(1));
      reply.complete(FunctionResponse(status: 200, data: status()));
      await tester.pump();
      expect(await finishPayment(tester, payment), PaymentResult.success);
    },
  );

  testWidgets('in-flight request ends at absolute two-minute deadline', (
    tester,
  ) async {
    final reply = Completer<FunctionResponse?>();
    when(
      () => edge.runEdgeFunction(
        name: 'checkPaymentResult',
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) {
      statusCalls += 1;
      return reply.future;
    });
    PaymentResult? result;
    final payment = subject.makePayment(2.75).then((value) => result = value);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 117));
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(await finishPayment(tester, payment), PaymentResult.pending);
    reply.complete(FunctionResponse(status: 200, data: status()));
    await tester.pump(const Duration(minutes: 3));
    expect(result, PaymentResult.pending);
    expect(statusCalls, 1);
  });

  testWidgets(
    'creation time counts against same deadline; late URL never opens',
    (tester) async {
      final reply = Completer<FunctionResponse?>();
      when(
        () => edge.runEdgeFunction(
          name: 'createCheckoutSession',
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) => reply.future);
      final payment = subject.makePayment(2.75);
      await tester.pump(const Duration(minutes: 2));
      expect(await finishPayment(tester, payment), PaymentResult.pending);
      reply.complete(
        FunctionResponse(
          status: 200,
          data: {'url': 'about:blank', 'session_id': 'cs_late'},
        ),
      );
      await tester.pump();
      expect(subject.openedUrls, isEmpty);
      expect(statusCalls, 0);
    },
  );

  testWidgets('processing cannot restart the deadline', (tester) async {
    respond(status(paymentStatus: 'processing', legacyStatus: 'unpaid'));
    final payment = subject.makePayment(2.75);
    await tester.pump();
    for (var second = 0; second < 120; second += 1) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(await finishPayment(tester, payment), PaymentResult.pending);
    final callsAtDeadline = statusCalls;
    expect(callsAtDeadline, inInclusiveRange(1, 26));
    await tester.pump(const Duration(minutes: 3));
    expect(statusCalls, callsAtDeadline);
  });

  testWidgets(
    'popup closes during request: pending, no late success or leaked error',
    (tester) async {
      final reply = Completer<FunctionResponse?>();
      when(
        () => edge.runEdgeFunction(
          name: 'checkPaymentResult',
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) {
        statusCalls += 1;
        return reply.future;
      });
      final payment = subject.makePayment(2.75);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      (subject.popup as Popup).closed = true;
      await tester.pump(const Duration(milliseconds: 200));
      expect(await finishPayment(tester, payment), PaymentResult.pending);
      reply.completeError(StateError('late transport failure'));
      await tester.pump(const Duration(minutes: 3));
      expect(statusCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closure beats a successful reply before the close timer fires', (
    tester,
  ) async {
    final reply = Completer<FunctionResponse?>();
    when(
      () => edge.runEdgeFunction(
        name: 'checkPaymentResult',
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) => reply.future);
    final payment = subject.makePayment(2.75);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    (subject.popup as Popup).closed = true;
    reply.complete(FunctionResponse(status: 200, data: status()));
    await tester.pump();
    expect(await finishPayment(tester, payment), PaymentResult.pending);
  });

  testWidgets('blocked popup stays pending without polling', (tester) async {
    subject.popup = null;
    final payment = subject.makePayment(2.75);
    await tester.pump();
    expect(await finishPayment(tester, payment), PaymentResult.pending);
    expect(statusCalls, 0);
  });

  for (final nextUser in <String?>[null, 'other-user']) {
    testWidgets('auth change to $nextUser stops active checkout', (
      tester,
    ) async {
      final payment = subject.makePayment(2.75);
      await tester.pump();
      userId = nextUser;
      authEvents.add(nextUser != null);
      await tester.pump();
      expect(await finishPayment(tester, payment), PaymentResult.pending);
      await tester.pump(const Duration(minutes: 3));
      expect(statusCalls, 0);
    });
  }

  testWidgets('same-user token refresh does not stop checkout', (tester) async {
    final payment = subject.makePayment(2.75);
    await tester.pump();
    authEvents.add(true);
    await tester.pump(const Duration(seconds: 2));
    expect(await finishPayment(tester, payment), PaymentResult.success);
  });

  testWidgets(
    'user changed during request rejects late success without auth event',
    (tester) async {
      final reply = Completer<FunctionResponse?>();
      when(
        () => edge.runEdgeFunction(
          name: 'checkPaymentResult',
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) => reply.future);
      final payment = subject.makePayment(2.75);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      userId = 'other-user';
      reply.complete(FunctionResponse(status: 200, data: status()));
      await tester.pump();
      expect(await finishPayment(tester, payment), PaymentResult.pending);
    },
  );

  testWidgets(
    'logout then same-user login cannot revive the captured checkout',
    (tester) async {
      final payment = subject.makePayment(2.75);
      await tester.pump();
      authEvents.add(false);
      authEvents.add(true);
      await tester.pump();
      expect(await finishPayment(tester, payment), PaymentResult.pending);
      await tester.pump(const Duration(minutes: 3));
      expect(statusCalls, 0);
    },
  );

  testWidgets('missing Checkout session never opens a popup or polls', (
    tester,
  ) async {
    when(
      () => edge.runEdgeFunction(
        name: 'createCheckoutSession',
        body: any(named: 'body'),
      ),
    ).thenAnswer(
      (_) async => FunctionResponse(status: 200, data: {'url': 'about:blank'}),
    );
    final payment = subject.makePayment(2.75);
    await tester.pump();
    expect(await finishPayment(tester, payment), PaymentResult.pending);
    expect(subject.openedUrls, isEmpty);
    expect(statusCalls, 0);
  });

  testWidgets('null Edge response stays pending', (tester) async {
    when(
      () => edge.runEdgeFunction(
        name: 'checkPaymentResult',
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => null);
    final payment = subject.makePayment(2.75);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await finishPayment(tester, payment), PaymentResult.pending);
  });

  testWidgets('browser pagehide cleans up active checkout', (tester) async {
    final payment = subject.makePayment(2.75);
    await tester.pump();
    html.window.dispatchEvent(html.Event('pagehide'));
    await tester.pump();
    expect(await finishPayment(tester, payment), PaymentResult.pending);
    await tester.pump(const Duration(minutes: 3));
    expect(statusCalls, 0);
  });

  testWidgets('real browser popup closure stays pending', (tester) async {
    subject.useRealPopup = true;
    final payment = subject.makePayment(2.75);
    await tester.pump();
    expect(subject.popup, isNotNull);
    expect(subject.popup!.closed, isFalse);
    subject.popup!.close();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 200));
    expect(await finishPayment(tester, payment), PaymentResult.pending);
    expect(statusCalls, 0);
  });

  testWidgets('HTTP error preserves pending and releases duplicate guard', (
    tester,
  ) async {
    respond(status(), code: 403);
    final payment = subject.makePayment(2.75);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await finishPayment(tester, payment), PaymentResult.pending);
    subject.popup = Popup();
    respond(status());
    final nextPayment = subject.makePayment(2.75);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await finishPayment(tester, nextPayment), PaymentResult.success);
    expect(subject.openedUrls, hasLength(2));
  });

  testWidgets('network exception stays pending', (tester) async {
    when(
      () => edge.runEdgeFunction(
        name: 'checkPaymentResult',
        body: any(named: 'body'),
      ),
    ).thenThrow(StateError('network unavailable'));
    final payment = subject.makePayment(2.75);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await finishPayment(tester, payment), PaymentResult.pending);
  });

  testWidgets('signed-out caller cannot create checkout', (tester) async {
    userId = null;
    expect(await subject.makePayment(2.75), PaymentResult.pending);
    verifyNever(
      () => edge.runEdgeFunction(
        name: any(named: 'name'),
        body: any(named: 'body'),
      ),
    );
  });
}
