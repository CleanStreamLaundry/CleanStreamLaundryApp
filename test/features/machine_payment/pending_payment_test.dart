import 'package:clean_stream_laundry_app/features/machine_payment/controller.dart';
import 'package:clean_stream_laundry_app/features/machine_payment/machine_payment.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
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

class PendingWalletMock extends Mock implements WalletService {}

class PendingPaymentMock extends Mock implements PaymentService {}

void main() {
  late MockMachineCommunicationService machine;
  late MockTransactionService transactions;
  late PendingWalletMock wallet;
  late MockProfileService profile;
  late MockNotificationService notifications;

  setUp(() async {
    await GetIt.instance.reset();
    machine = MockMachineCommunicationService();
    transactions = MockTransactionService();
    wallet = PendingWalletMock();
    profile = MockProfileService();
    notifications = MockNotificationService();
    final auth = MockAuthService();
    final machines = MockMachineService();
    final payments = PendingPaymentMock();
    when(() => auth.getCurrentUserId).thenReturn('user-current');
    when(
      () => machines.getMachineById('123'),
    ).thenAnswer((_) async => {'Name': 'Washer01', 'Price': 2.75});
    when(() => wallet.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet-current',
        status: 'active',
        paidBalanceCents: 1000,
        promoBalanceCents: 0,
        totalBalanceCents: 1000,
      ),
    );
    when(
      () => payments.makePayment(
        2.75,
        purpose: PaymentPurpose.directMachinePayment,
      ),
    ).thenAnswer((_) async => PaymentResult.pending);
    GetIt.instance.registerSingleton<AuthService>(auth);
    GetIt.instance.registerSingleton<MachineService>(machines);
    GetIt.instance.registerSingleton<ProfileService>(profile);
    GetIt.instance.registerSingleton<TransactionService>(transactions);
    GetIt.instance.registerSingleton<WalletService>(wallet);
    GetIt.instance.registerSingleton<MachineCommunicationService>(machine);
    GetIt.instance.registerSingleton<NotificationService>(notifications);
    GetIt.instance.registerSingleton<PaymentService>(payments);
    GetIt.instance.registerSingleton<PaymentProcessor>(PaymentProcessor());
  });

  tearDown(() => GetIt.instance.reset());

  void expectNoPaymentSideEffects() {
    verifyZeroInteractions(machine);
    verifyZeroInteractions(transactions);
    verifyZeroInteractions(profile);
    verifyZeroInteractions(notifications);
    verifyNever(
      () => wallet.redeemForMachine(
        machineId: any(named: 'machineId'),
        amountCents: any(named: 'amountCents'),
        note: any(named: 'note'),
      ),
    );
  }

  test(
    'pending passes through real processor without vending or recording success',
    () async {
      final controller = PaymentController(machineId: '123');
      await controller.init();
      expect(await controller.processDirectPayment(), PaymentOutcome.pending);
      expect(controller.paymentCompleted, isFalse);
      expect(controller.userBalance, 10);
      expectNoPaymentSideEffects();
      controller.dispose();
    },
  );

  testWidgets(
    'legacy entry preserves uncertainty without starting another payment',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/payment',
        routes: [
          GoRoute(
            path: '/payment',
            builder: (_, _) => const MachinePayment(machineId: '123'),
          ),
          GoRoute(path: '/homePage', builder: (_, _) => const Scaffold()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Payment link unavailable'), findsOneWidget);
      expect(
        find.textContaining('contact Clean Stream support before paying again.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Its status cannot be confirmed here.'),
        findsOneWidget,
      );
      expect(find.text('Pay \$2.75'), findsNothing);
      expect(find.text('Payment Failed'), findsNothing);
      expect(find.text('Payment Processed! Machine Ready!'), findsNothing);
      expect(find.textContaining('refund'), findsNothing);
      expectNoPaymentSideEffects();
      verifyZeroInteractions(
        GetIt.instance<PaymentService>() as PendingPaymentMock,
      );
      verifyZeroInteractions(wallet);
      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();
      expectNoPaymentSideEffects();
      verifyZeroInteractions(
        GetIt.instance<PaymentService>() as PendingPaymentMock,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
