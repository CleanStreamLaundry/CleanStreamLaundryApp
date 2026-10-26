import 'dart:async';

import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/services/stripe/stripe_service_mobile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mocks.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.stripe/payments', JSONMethodCodec());
  final calls = <MethodCall>[];
  late MockEdgeFunctionService edge;
  late StripeService service;
  Object? sheetResult;
  Object? initResult;
  late Completer<void> verificationStarted;
  Completer<FunctionResponse?>? verification;
  String? status;

  setUp(() async {
    await GetIt.instance.reset();
    calls.clear();
    sheetResult = <String, dynamic>{};
    initResult = <String, dynamic>{};
    status = 'succeeded';
    verification = null;
    verificationStarted = Completer<void>();
    edge = MockEdgeFunctionService();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'initialise':
          return null;
        case 'initPaymentSheet':
          return initResult;
        case 'presentPaymentSheet':
          return sheetResult;
        default:
          fail('Unexpected SDK method: ${call.method}');
      }
    });
    // Dummy key and intent are confined to the fake channel and Edge transport.
    Stripe.publishableKey = 'pk_test_channel_contract_only';
    Stripe.instance.markNeedsSettings();
    GetIt.instance.registerSingleton<Stripe>(Stripe.instance);
    GetIt.instance.registerSingleton<EdgeFunctionService>(edge);
    when(
      () => edge.runEdgeFunction(
        name: 'paymentIntent',
        body: any(named: 'body'),
      ),
    ).thenAnswer(
      (_) async => FunctionResponse(
        status: 200,
        data: {
          'clientSecret': 'pi_contract_secret_fake',
          'paymentIntentId': 'pi_contract',
        },
      ),
    );
    when(
      () => edge.runEdgeFunction(
        name: 'paymentIntentStatus',
        body: {'paymentIntentId': 'pi_contract'},
      ),
    ).thenAnswer((_) {
      if (!verificationStarted.isCompleted) verificationStarted.complete();
      return verification?.future ??
          Future.value(FunctionResponse(status: 200, data: {'status': status}));
    });
    service = StripeService();
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await GetIt.instance.reset();
  });

  test(
    'real SDK serializes the existing sheet and verifies the server intent',
    () async {
      expect(
        await service.makePayment(2.75, purpose: PaymentPurpose.walletLoad),
        PaymentResult.success,
      );
      expect(calls.map((call) => call.method), [
        'initialise',
        'initPaymentSheet',
        'presentPaymentSheet',
      ]);
      final params = (calls[1].arguments as Map)['params'] as Map;
      expect(params['paymentIntentClientSecret'], 'pi_contract_secret_fake');
      expect(params['merchantDisplayName'], 'Clean Stream Laundry Solutions');
      expect(params['googlePay']['merchantCountryCode'], 'US');
      expect(params['googlePay']['currencyCode'], 'USD');
      expect(params['customFlow'], isFalse);
      expect(params['intentConfiguration'], isNull);
      expect(params['appearance']['shapes']['borderRadius'], 20.0);
      expect(calls[2].arguments, {'params': {}, 'options': {}});
      verify(
        () => edge.runEdgeFunction(
          name: 'paymentIntent',
          body: {'amount': 275, 'currency': 'usd', 'purpose': 'walletLoad'},
        ),
      ).called(1);
      verify(
        () => edge.runEdgeFunction(
          name: 'paymentIntentStatus',
          body: {'paymentIntentId': 'pi_contract'},
        ),
      ).called(1);
      verifyNoMoreInteractions(edge);
    },
  );

  for (final entry in [
    ('processing', PaymentResult.pending),
    ('failed', PaymentResult.failed),
    ('unknown', PaymentResult.failed),
    (null, PaymentResult.failed),
  ]) {
    test(
      'native completion does not override server status ${entry.$1}',
      () async {
        status = entry.$1;
        expect(await service.makePayment(2.75), entry.$2);
      },
    );
  }

  for (final entry in [
    ('Canceled', 'canceled', PaymentResult.canceled),
    ('Canceled', 'failed', PaymentResult.canceled),
    ('Canceled', 'succeeded', PaymentResult.success),
    ('Canceled', 'processing', PaymentResult.pending),
    ('Failed', 'processing', PaymentResult.pending),
  ]) {
    test(
      'native ${entry.$1} with server ${entry.$2} follows the result contract',
      () async {
        sheetResult = {
          'error': {'code': entry.$1, 'message': 'Fake native result'},
        };
        status = entry.$2;
        expect(await service.makePayment(2.75), entry.$3);
        verify(
          () => edge.runEdgeFunction(
            name: 'paymentIntentStatus',
            body: {'paymentIntentId': 'pi_contract'},
          ),
        ).called(1);
      },
    );
  }

  test(
    'SDK initialization error verifies without presenting or recreating intent',
    () async {
      initResult = {
        'error': {'code': 'Failed', 'message': 'Fake initialization error'},
      };
      status = 'processing';
      expect(await service.makePayment(2.75), PaymentResult.pending);
      expect(calls.map((call) => call.method), [
        'initialise',
        'initPaymentSheet',
      ]);
      verify(
        () => edge.runEdgeFunction(
          name: 'paymentIntent',
          body: any(named: 'body'),
        ),
      ).called(1);
    },
  );

  test(
    'real SDK completion retains duplicate guard until server verification',
    () async {
      verification = Completer<FunctionResponse?>();
      final first = service.makePayment(2.75);
      await verificationStarted.future;
      try {
        await expectLater(service.makePayment(2.75), throwsStateError);
        expect(
          calls.where((call) => call.method == 'presentPaymentSheet'),
          hasLength(1),
        );
        verify(
          () => edge.runEdgeFunction(
            name: 'paymentIntent',
            body: any(named: 'body'),
          ),
        ).called(1);
      } finally {
        verification!.complete(
          FunctionResponse(status: 200, data: {'status': 'processing'}),
        );
      }
      expect(await first, PaymentResult.pending);
    },
  );
}
