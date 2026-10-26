import 'dart:async';

import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/services/stripe/stripe_service_mobile.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get_it/get_it.dart';
import 'mocks.dart';

class TestableStripeService extends StripeService {
  Future<PaymentIntentConfig?> createIntent(
    double amount,
    String currency, [
    PaymentPurpose purpose = PaymentPurpose.directMachinePayment,
    Map<String, dynamic>? consent,
  ]) {
    return super.createPaymentIntent(amount, currency, purpose, consent);
  }

  int cents(double amount) => super.convertDollarsToCents(amount);
}

void main() {
  late MockStripe mockStripe;
  late MockEdgeFunctionService mockEdgeFunctionService;
  late TestableStripeService stripeService;
  final getIt = GetIt.instance;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(FakeSetupPaymentSheetParameters());
  });

  setUp(() {
    getIt.reset();
    mockEdgeFunctionService = MockEdgeFunctionService();
    mockStripe = MockStripe();

    getIt.registerSingleton<EdgeFunctionService>(mockEdgeFunctionService);
    getIt.registerSingleton<Stripe>(mockStripe);

    stripeService = TestableStripeService();
  });

  tearDown(() {
    getIt.reset();
  });

  void mockCreatePaymentIntent({String? clientSecret = 'testSecret'}) {
    when(
      () => mockEdgeFunctionService.runEdgeFunction(
        name: 'paymentIntent',
        body: any(named: 'body'),
      ),
    ).thenAnswer(
      (_) async => FunctionResponse(
        status: 200,
        data: {
          if (clientSecret != null) 'clientSecret': clientSecret,
          'paymentIntentId': 'pi_test',
        },
      ),
    );
  }

  void mockVerifyPaymentIntent(String status) {
    when(
      () => mockEdgeFunctionService.runEdgeFunction(
        name: 'paymentIntentStatus',
        body: {'paymentIntentId': 'pi_test'},
      ),
    ).thenAnswer(
      (_) async => FunctionResponse(status: 200, data: {'status': status}),
    );
  }

  group("StripeService Tests", () {
    test('wallet load carries acknowledgement into the server request', () async {
      mockCreatePaymentIntent();
      const consent = {'context_id': 'synthetic-context', 'acknowledged': true};
      await stripeService.createIntent(25, 'usd', PaymentPurpose.walletLoad, consent);
      verify(() => mockEdgeFunctionService.runEdgeFunction(
        name: 'paymentIntent',
        body: {'amount': 2500, 'currency': 'usd', 'purpose': 'walletLoad', 'consent': consent},
      )).called(1);
    });
    group("makePayment", () {
      test(
        "throws StripeConfigException when no client secret is found",
        () async {
          when(
            () => mockEdgeFunctionService.runEdgeFunction(
              name: any(named: "name"),
              body: any(named: "body"),
            ),
          ).thenAnswer((_) async => null);

          await expectLater(
            stripeService.makePayment(2.60),
            throwsA(isA<StripeConfigException>()),
          );

          verify(
            () => mockEdgeFunctionService.runEdgeFunction(
              name: 'paymentIntent',
              body: {
                'amount': 260,
                'currency': 'usd',
                'purpose': PaymentPurpose.directMachinePayment.name,
              },
            ),
          ).called(1);
        },
      );

      test(
        "returns success when PaymentSheet succeeds and verification succeeds",
        () async {
          mockCreatePaymentIntent();
          mockVerifyPaymentIntent('succeeded');

          when(
            () => mockStripe.initPaymentSheet(
              paymentSheetParameters: any(named: "paymentSheetParameters"),
            ),
          ).thenAnswer((_) async => null);

          when(
            () => mockStripe.presentPaymentSheet(),
          ).thenAnswer((_) async => null);

          final result = await stripeService.makePayment(2.60);

          expect(result, PaymentResult.success);
          verify(
            () => mockStripe.initPaymentSheet(
              paymentSheetParameters: any(named: "paymentSheetParameters"),
            ),
          ).called(1);
          verify(() => mockStripe.presentPaymentSheet()).called(1);
          verify(
            () => mockEdgeFunctionService.runEdgeFunction(
              name: 'paymentIntentStatus',
              body: {'paymentIntentId': 'pi_test'},
            ),
          ).called(1);
        },
      );

      test(
        "returns success when PaymentSheet throws but verification succeeded",
        () async {
          mockCreatePaymentIntent();
          mockVerifyPaymentIntent('succeeded');

          when(
            () => mockStripe.initPaymentSheet(
              paymentSheetParameters: any(named: "paymentSheetParameters"),
            ),
          ).thenAnswer((_) async => null);
          when(() => mockStripe.presentPaymentSheet()).thenThrow(
            StripeException(
              error: LocalizedErrorMessage(code: FailureCode.Failed),
            ),
          );

          final result = await stripeService.makePayment(10.0);

          expect(result, PaymentResult.success);
        },
      );

      test(
        "returns pending when PaymentSheet throws and verification is processing",
        () async {
          mockCreatePaymentIntent();
          mockVerifyPaymentIntent('processing');

          when(
            () => mockStripe.initPaymentSheet(
              paymentSheetParameters: any(named: "paymentSheetParameters"),
            ),
          ).thenAnswer((_) async => null);
          when(() => mockStripe.presentPaymentSheet()).thenThrow(
            StripeException(
              error: LocalizedErrorMessage(code: FailureCode.Failed),
            ),
          );

          final result = await stripeService.makePayment(10.0);

          expect(result, PaymentResult.pending);
        },
      );

      test(
        "returns canceled when PaymentSheet is explicitly canceled",
        () async {
          mockCreatePaymentIntent();
          mockVerifyPaymentIntent('canceled');

          when(
            () => mockStripe.initPaymentSheet(
              paymentSheetParameters: any(named: "paymentSheetParameters"),
            ),
          ).thenAnswer((_) async => null);
          when(() => mockStripe.presentPaymentSheet()).thenThrow(
            StripeException(
              error: LocalizedErrorMessage(code: FailureCode.Canceled),
            ),
          );

          final result = await stripeService.makePayment(10.0);

          expect(result, PaymentResult.canceled);
          verify(
            () => mockEdgeFunctionService.runEdgeFunction(
              name: 'paymentIntentStatus',
              body: {'paymentIntentId': 'pi_test'},
            ),
          ).called(1);
        },
      );

      test(
        "returns success when PaymentSheet reports canceled but verification succeeded",
        () async {
          mockCreatePaymentIntent();
          mockVerifyPaymentIntent('succeeded');

          when(
            () => mockStripe.initPaymentSheet(
              paymentSheetParameters: any(named: "paymentSheetParameters"),
            ),
          ).thenAnswer((_) async => null);
          when(() => mockStripe.presentPaymentSheet()).thenThrow(
            StripeException(
              error: LocalizedErrorMessage(code: FailureCode.Canceled),
            ),
          );

          final result = await stripeService.makePayment(10.0);

          expect(result, PaymentResult.success);
        },
      );

      test("returns failed when verification fails", () async {
        mockCreatePaymentIntent();
        mockVerifyPaymentIntent('failed');

        when(
          () => mockStripe.initPaymentSheet(
            paymentSheetParameters: any(named: "paymentSheetParameters"),
          ),
        ).thenAnswer((_) async => null);
        when(
          () => mockStripe.presentPaymentSheet(),
        ).thenAnswer((_) async => null);

        final result = await stripeService.makePayment(10.0);

        expect(result, PaymentResult.failed);
      });

      test("blocks duplicate concurrent PaymentSheet launches", () async {
        mockCreatePaymentIntent();
        mockVerifyPaymentIntent('succeeded');

        final releaseInit = Completer<PaymentSheetPaymentOption?>();
        when(
          () => mockStripe.initPaymentSheet(
            paymentSheetParameters: any(named: "paymentSheetParameters"),
          ),
        ).thenAnswer((_) => releaseInit.future);
        when(
          () => mockStripe.presentPaymentSheet(),
        ).thenAnswer((_) async => null);

        final firstPayment = stripeService.makePayment(10.0);

        await expectLater(
          stripeService.makePayment(10.0),
          throwsA(isA<StateError>()),
        );

        releaseInit.complete(null);
        expect(await firstPayment, PaymentResult.success);
      });

      for (final (scenario, sheetError) in <(String, Object?)>[
        ('normal payment', null),
        (
          'StripeException fallback',
          StripeException(
            error: LocalizedErrorMessage(code: FailureCode.Failed),
          ),
        ),
        ('generic error fallback', Exception('PaymentSheet error')),
      ]) {
        for (final (status, expectedResult) in [
          ('succeeded', PaymentResult.success),
          ('processing', PaymentResult.pending),
          (null, PaymentResult.failed),
        ]) {
          test(
            'holds guard: $scenario, ${status ?? 'verification error'}',
            () async {
              mockCreatePaymentIntent();
              final verificationStarted = Completer<void>();
              final releaseVerification = Completer<FunctionResponse?>();
              final verificationError = Exception(
                'Verification request failed',
              );
              final verifiedResponse = FunctionResponse(
                status: 200,
                data: {'status': status},
              );
              when(
                () => mockEdgeFunctionService.runEdgeFunction(
                  name: 'paymentIntentStatus',
                  body: {'paymentIntentId': 'pi_test'},
                ),
              ).thenAnswer((_) {
                if (!verificationStarted.isCompleted) {
                  verificationStarted.complete();
                  return releaseVerification.future;
                }
                if (status == null) return Future.error(verificationError);
                return Future.value(verifiedResponse);
              });
              when(
                () => mockStripe.initPaymentSheet(
                  paymentSheetParameters: any(named: 'paymentSheetParameters'),
                ),
              ).thenAnswer((_) async => null);
              when(() => mockStripe.presentPaymentSheet()).thenAnswer((
                _,
              ) async {
                if (sheetError != null) throw sheetError;
                return null;
              });

              var firstPaymentSettled = false;
              final firstPayment = stripeService.makePayment(10.0).whenComplete(
                () {
                  firstPaymentSettled = true;
                },
              );
              await verificationStarted.future;

              try {
                await expectLater(
                  stripeService.makePayment(10.0),
                  throwsA(isA<StateError>()),
                );
                expect(firstPaymentSettled, isFalse);
                verify(
                  () => mockEdgeFunctionService.runEdgeFunction(
                    name: 'paymentIntent',
                    body: any(named: 'body'),
                  ),
                ).called(1);
                verify(
                  () => mockStripe.initPaymentSheet(
                    paymentSheetParameters: any(
                      named: 'paymentSheetParameters',
                    ),
                  ),
                ).called(1);
                verify(() => mockStripe.presentPaymentSheet()).called(1);
                verify(
                  () => mockEdgeFunctionService.runEdgeFunction(
                    name: 'paymentIntentStatus',
                    body: {'paymentIntentId': 'pi_test'},
                  ),
                ).called(1);
                verifyNoMoreInteractions(mockEdgeFunctionService);
                verifyNoMoreInteractions(mockStripe);
              } finally {
                if (status == null) {
                  releaseVerification.completeError(verificationError);
                } else {
                  releaseVerification.complete(verifiedResponse);
                }
                expect(await firstPayment, expectedResult);
              }

              expect(firstPaymentSettled, isTrue);
              expect(await stripeService.makePayment(10.0), expectedResult);
              verify(
                () => mockEdgeFunctionService.runEdgeFunction(
                  name: 'paymentIntent',
                  body: any(named: 'body'),
                ),
              ).called(1);
              verify(
                () => mockStripe.initPaymentSheet(
                  paymentSheetParameters: any(named: 'paymentSheetParameters'),
                ),
              ).called(1);
              verify(() => mockStripe.presentPaymentSheet()).called(1);
              verify(
                () => mockEdgeFunctionService.runEdgeFunction(
                  name: 'paymentIntentStatus',
                  body: {'paymentIntentId': 'pi_test'},
                ),
              ).called(1);
              verifyNoMoreInteractions(mockEdgeFunctionService);
              verifyNoMoreInteractions(mockStripe);
            },
          );
        }
      }
    });

    group("createPaymentIntent", () {
      test(
        'custom wallet amount preserves cents in the Edge request',
        () async {
          mockCreatePaymentIntent();
          await stripeService.createIntent(
            4.35,
            'usd',
            PaymentPurpose.walletLoad,
          );
          verify(
            () => mockEdgeFunctionService.runEdgeFunction(
              name: 'paymentIntent',
              body: {
                'amount': 435,
                'currency': 'usd',
                'purpose': PaymentPurpose.walletLoad.name,
              },
            ),
          ).called(1);
        },
      );

      test("returns PaymentIntent config when successful", () async {
        mockCreatePaymentIntent(clientSecret: "testSecret123");

        final result = await stripeService.createIntent(25.70, "usd");

        expect(result?.clientSecret, "testSecret123");
        expect(result?.paymentIntentId, "pi_test");
        verify(
          () => mockEdgeFunctionService.runEdgeFunction(
            name: 'paymentIntent',
            body: {
              'amount': 2570,
              'currency': 'usd',
              'purpose': PaymentPurpose.directMachinePayment.name,
            },
          ),
        ).called(1);
      });

      test("returns null when response is null", () async {
        when(
          () => mockEdgeFunctionService.runEdgeFunction(
            name: any(named: "name"),
            body: any(named: "body"),
          ),
        ).thenAnswer((_) async => null);

        final result = await stripeService.createIntent(25.70, "usd");

        expect(result, null);
      });

      test("returns null when response data is null", () async {
        when(
          () => mockEdgeFunctionService.runEdgeFunction(
            name: any(named: "name"),
            body: any(named: "body"),
          ),
        ).thenAnswer((_) async => FunctionResponse(status: 200, data: null));

        final result = await stripeService.createIntent(25.70, "usd");

        expect(result, null);
      });

      test("returns null when clientSecret is not in response", () async {
        when(
          () => mockEdgeFunctionService.runEdgeFunction(
            name: any(named: "name"),
            body: any(named: "body"),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            status: 200,
            data: {"paymentIntentId": "pi_test"},
          ),
        );

        final result = await stripeService.createIntent(25.70, "usd");

        expect(result, null);
      });

      test("returns null when paymentIntentId is not in response", () async {
        when(
          () => mockEdgeFunctionService.runEdgeFunction(
            name: any(named: "name"),
            body: any(named: "body"),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            status: 200,
            data: {"clientSecret": "testSecret"},
          ),
        );

        final result = await stripeService.createIntent(25.70, "usd");

        expect(result, null);
      });

      test("returns null when exception is thrown", () async {
        when(
          () => mockEdgeFunctionService.runEdgeFunction(
            name: any(named: "name"),
            body: any(named: "body"),
          ),
        ).thenThrow(Exception("Network error"));

        final result = await stripeService.createIntent(25.70, "usd");

        expect(result, null);
      });
    });

    group("convertDollarsToCents", () {
      test("converts dollars to cents correctly", () {
        expect(stripeService.cents(2.75), 275);
      });

      test("handles zero amount", () {
        expect(stripeService.cents(0), 0);
      });

      test("handles whole dollar amounts", () {
        expect(stripeService.cents(10.00), 1000);
      });

      test("handles large amounts", () {
        expect(stripeService.cents(1234.56), 123456);
      });

      test("handles small decimal amounts", () {
        expect(stripeService.cents(0.01), 1);
      });

      test('preserves every allowed whole-cent wallet amount', () {
        for (var cents = 100; cents <= 50000; cents++) {
          expect(stripeService.cents(cents / 100), cents);
        }
      });

      test("rounds fractional cents to the nearest cent", () {
        expect(stripeService.cents(1.999), 200);
      });
    });
  });
}
