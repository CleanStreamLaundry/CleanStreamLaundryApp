import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/features/machine_payment/machine_payment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../features/machine_payment/machine_payment_test.dart'
    show LegacyPaymentMocks;

void main() {
  late LegacyPaymentMocks services;
  late GoRouter router;

  setUp(() async {
    await GetIt.I.reset();
    services = LegacyPaymentMocks();
    router = RouterService().createRouter(services.auth);
  });
  tearDown(() async {
    router.dispose();
    await GetIt.I.reset();
  });

  Future<void> open(WidgetTester tester, String location) async {
    router.go(location);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byType(MachinePayment), findsOneWidget);
    expect(find.text('Payment link unavailable'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri, Uri.parse(location));
    services.expectNoCalls();
    expect(tester.takeException(), isNull);
  }

  for (final location in [
    '/paymentPage',
    '/paymentPage?machineId=',
    '/paymentPage?machineId=123',
    '/paymentPage?machineId=public-token%2Bprivate',
    '/paymentPage?machineId=4434331126150568',
    '/paymentPage?machineId=123&session_id=cs_previous&paymentIntentId=pi_previous',
  ]) {
    testWidgets('actual legacy route cannot create a payment: $location', (
      tester,
    ) async {
      await open(tester, location);
      expect(find.textContaining('cs_previous'), findsNothing);
      expect(find.textContaining('pi_previous'), findsNothing);
      await tester.pump(const Duration(minutes: 3));
      expect(
        router.routerDelegate.currentConfiguration.uri,
        Uri.parse(location),
      );
      services.expectNoCalls();
    });
  }

  testWidgets('repeated entry and identifier changes stay inert', (
    tester,
  ) async {
    for (final id in [
      '123',
      'public-token',
      '4434331126150568',
      '123',
      '123',
    ]) {
      await open(tester, '/paymentPage?machineId=$id');
      expect(find.textContaining(id), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    services.expectNoCalls();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'signed-out route is unavailable without identity or payment reads',
    (tester) async {
      when(() => services.auth.getCurrentUserId).thenReturn(null);
      await open(tester, '/paymentPage?machineId=123');
      services.expectNoCalls();
    },
  );
}
