import 'package:clean_stream_laundry_app/features/machine_payment/machine_payment.dart';
import 'package:clean_stream_laundry_app/features/machine_payment/widgets/payment_buttons.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_communication_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

class _PaymentMock extends Mock implements PaymentService {}

class _VendMock extends Mock implements CortinaVendService {}

class _EdgeMock extends Mock implements EdgeFunctionService {}

// Reused by the actual-router regression to verify zero service interactions.
class LegacyPaymentMocks {
  final auth = MockAuthService();
  final machines = MockMachineService();
  final profile = MockProfileService();
  final transactions = MockTransactionService();
  final wallet = MockWalletService();
  final machine = MockMachineCommunicationService();
  final notifications = MockNotificationService();
  final processor = MockPaymentProcessor();
  final payments = _PaymentMock();
  final vend = _VendMock();
  final edge = _EdgeMock();

  LegacyPaymentMocks() {
    GetIt.I.registerSingleton<AuthService>(auth);
    GetIt.I.registerSingleton<MachineService>(machines);
    GetIt.I.registerSingleton<ProfileService>(profile);
    GetIt.I.registerSingleton<TransactionService>(transactions);
    GetIt.I.registerSingleton<WalletService>(wallet);
    GetIt.I.registerSingleton<MachineCommunicationService>(machine);
    GetIt.I.registerSingleton<NotificationService>(notifications);
    GetIt.I.registerSingleton<PaymentProcessor>(processor);
    GetIt.I.registerSingleton<PaymentService>(payments);
    GetIt.I.registerSingleton<CortinaVendService>(vend);
    GetIt.I.registerSingleton<EdgeFunctionService>(edge);
    when(() => auth.getCurrentUserId).thenReturn('current-user');
    when(
      () => machines.getMachineById(any()),
    ).thenAnswer((_) async => {'Name': 'Washer01', 'Price': 2.75});
    when(() => wallet.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet-current',
        status: 'active',
        paidBalanceCents: 1250,
        promoBalanceCents: 0,
        totalBalanceCents: 1250,
      ),
    );
  }

  void expectNoCalls() {
    for (final mock in <Mock>[
      auth,
      machines,
      profile,
      transactions,
      wallet,
      machine,
      notifications,
      processor,
      payments,
      vend,
      edge,
    ]) {
      verifyZeroInteractions(mock);
    }
  }
}

void main() {
  late LegacyPaymentMocks services;

  setUp(() async {
    await GetIt.I.reset();
    services = LegacyPaymentMocks();
  });
  tearDown(() => GetIt.I.reset());

  Future<GoRouter> open(WidgetTester tester, String machineId) async {
    final router = GoRouter(
      initialLocation: '/payment',
      routes: [
        GoRoute(
          path: '/payment',
          builder: (_, _) => MachinePayment(machineId: machineId),
        ),
        GoRoute(
          path: '/homePage',
          builder: (_, _) => const Scaffold(body: Text('Home destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  for (final machineId in [
    '',
    '123',
    'public-token+private',
    '4434331126150568',
  ]) {
    testWidgets('legacy page is inert for identifier "$machineId"', (
      tester,
    ) async {
      final router = await open(tester, machineId);
      expect(find.text('Payment link unavailable'), findsOneWidget);
      expect(find.byType(PaymentButtons), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Pay \$2.75'), findsNothing);
      if (machineId.isNotEmpty) {
        expect(find.textContaining(machineId), findsNothing);
      }
      services.expectNoCalls();
      await tester.pump(const Duration(minutes: 3));
      expect(router.routerDelegate.currentConfiguration.uri.path, '/payment');
      services.expectNoCalls();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('previous payment guidance makes no financial or vend claims', (
    tester,
  ) async {
    await open(tester, '123');
    expect(
      find.text(
        'If you already attempted a payment, contact Clean Stream support before '
        'paying again. Its status cannot be confirmed here.',
      ),
      findsOneWidget,
    );
    for (final claim in [
      'Payment Failed',
      'Payment Successful!',
      'Machine Ready!',
      'refund',
    ]) {
      expect(find.textContaining(claim), findsNothing);
    }
    services.expectNoCalls();
  });

  testWidgets('Back to Home is deliberate navigation without a payment', (
    tester,
  ) async {
    final router = await open(tester, '123');
    await tester.tap(find.text('Back to Home'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/homePage');
    expect(find.text('Home destination'), findsOneWidget);
    services.expectNoCalls();
  });

  testWidgets('page can mount without registering any payment dependencies', (
    tester,
  ) async {
    await GetIt.I.reset();
    await open(tester, '123');
    expect(find.text('Payment link unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('unavailable content fits ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, '123');
      expect(find.text('Back to Home').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      services.expectNoCalls();
    });
  }
}
