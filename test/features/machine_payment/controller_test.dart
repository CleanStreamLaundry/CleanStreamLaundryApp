import 'package:clean_stream_laundry_app/features/machine_payment/controller.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;
  late MockMachineService mockMachineService;
  late MockProfileService mockProfileService;
  late MockTransactionService mockTransactionService;
  late MockWalletService mockWalletService;
  late MockMachineCommunicationService mockMachineCommunicator;
  late MockNotificationService mockNotificationService;
  late MockPaymentProcessor mockPaymentProcessor;

  setUpAll(() {
    registerFallbackValue(FakeAuthService());
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() {
    mockAuthService = MockAuthService();
    mockMachineService = MockMachineService();
    mockProfileService = MockProfileService();
    mockTransactionService = MockTransactionService();
    mockWalletService = MockWalletService();
    mockMachineCommunicator = MockMachineCommunicationService();
    mockNotificationService = MockNotificationService();
    mockPaymentProcessor = MockPaymentProcessor();

    when(() => mockWalletService.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet123',
        status: 'active',
        paidBalanceCents: 800,
        promoBalanceCents: 200,
        totalBalanceCents: 1000,
      ),
    );

    when(() => mockNotificationService.scheduleEarlyMachineNotification(
      id: any(named: 'id'),
      machineTime: any(named: 'machineTime'),
      machineName: any(named: 'machineName'),
    )).thenAnswer((_) async {});
  });

  PaymentController buildController({String machineId = '123'}) =>
      PaymentController(
        machineId: machineId,
        authService: mockAuthService,
        machineService: mockMachineService,
        profileService: mockProfileService,
        transactionService: mockTransactionService,
        walletService: mockWalletService,
        machineCommunicator: mockMachineCommunicator,
        notificationService: mockNotificationService,
        paymentProcessor: mockPaymentProcessor,
      );

  // ---------------------------------------------------------------------------
  // init
  // ---------------------------------------------------------------------------

  group('init', () {
    test('sets machineName, price, userBalance on success', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(() => mockMachineService.getMachineById('123'))
          .thenAnswer((_) async => {'Name': 'Washer01', 'Price': 3.50});

      final controller = buildController();
      await controller.init();

      expect(controller.machineName, 'Washer01');
      expect(controller.price, 3.50);
      expect(controller.userBalance, 10.0);
      verify(() => mockWalletService.getBalance()).called(1);
      verifyNever(() => mockProfileService.getUserBalanceById(any()));
      expect(controller.isLoading, isFalse);
    });

    test('sets defaults when machine data is null', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(() => mockMachineService.getMachineById(any()))
          .thenAnswer((_) async => null);

      final controller = buildController();
      await controller.init();

      expect(controller.machineName, 'Unknown');
      expect(controller.price, 0.0);
      expect(controller.userBalance, 0.0);
    });

    test('returns early without fetching balance when userId is null',
            () async {
          when(() => mockAuthService.getCurrentUserId).thenReturn(null);
          when(() => mockMachineService.getMachineById(any()))
              .thenAnswer((_) async => {'Name': 'Washer01', 'Price': 3.50});

          final controller = buildController();
          await controller.init();

          verifyNever(() => mockProfileService.getUserBalanceById(any()));
          verifyNever(() => mockWalletService.getBalance());
          expect(controller.isLoading, isFalse);
        });

    test('notifies listeners when loading completes', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(() => mockMachineService.getMachineById(any()))
          .thenAnswer((_) async => {'Name': 'Washer01', 'Price': 3.50});

      final controller = buildController();
      var notified = false;
      controller.addListener(() => notified = true);

      await controller.init();

      expect(notified, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // isDryer
  // ---------------------------------------------------------------------------

  group('isDryer', () {
    test('returns true when machineName contains dryer', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(() => mockMachineService.getMachineById(any()))
          .thenAnswer((_) async => {'Name': 'Dryer01', 'Price': 1.50});

      final controller = buildController();
      await controller.init();

      expect(controller.isDryer, isTrue);
    });

    test('returns false when machineName contains washer', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(() => mockMachineService.getMachineById(any()))
          .thenAnswer((_) async => {'Name': 'Washer01', 'Price': 3.50});

      final controller = buildController();
      await controller.init();

      expect(controller.isDryer, isFalse);
    });

    test('returns false when machineName is null', () {
      final controller = buildController();
      expect(controller.isDryer, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // onDryerChanged / onWasherCycleChanged
  // ---------------------------------------------------------------------------

  group('Controls', () {
    test('onDryerChanged updates price and dryerMinutes', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(() => mockMachineService.getMachineById(any()))
          .thenAnswer((_) async => {'Name': 'Dryer01', 'Price': 1.50});

      final controller = buildController();
      await controller.init();

      controller.onDryerChanged(3.00, 60);

      expect(controller.price, 3.00);
      expect(controller.dryerMinutes, 60);
    });

    test('onWasherCycleChanged updates price by adding to base price',
            () async {
          when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
          when(() => mockMachineService.getMachineById(any()))
              .thenAnswer((_) async => {'Name': 'Washer01', 'Price': 3.50});

          final controller = buildController();
          await controller.init();

          controller.onWasherCycleChanged(0.50);

          expect(controller.price, closeTo(4.00, 0.001));
        });

    test('onDryerChanged notifies listeners', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(() => mockMachineService.getMachineById(any()))
          .thenAnswer((_) async => {'Name': 'Dryer01', 'Price': 1.50});

      final controller = buildController();
      await controller.init();

      var notified = false;
      controller.addListener(() => notified = true);

      controller.onDryerChanged(2.00, 40);

      expect(notified, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // processDirectPayment
  // ---------------------------------------------------------------------------

  group('processDirectPayment', () {
    setUp(() async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(() => mockMachineService.getMachineById(any()))
          .thenAnswer((_) async => {'Name': 'Dryer01', 'Price': 1.50});
    });

    test('returns success and sets paymentCompleted when everything succeeds',
            () async {
          when(() => mockPaymentProcessor.processPayment(any(), any()))
              .thenAnswer((_) async => PaymentResult.success);
          when(() => mockMachineCommunicator.wakeDevice(any()))
              .thenAnswer((_) async => true);

          final controller = buildController();
          await controller.init();

          final result = await controller.processDirectPayment();

          expect(result, PaymentOutcome.success);
          expect(controller.paymentCompleted, isTrue);
        });

    test('returns machineError when device fails to wake', () async {
      when(() => mockPaymentProcessor.processPayment(any(), any()))
          .thenAnswer((_) async => PaymentResult.success);
      when(() => mockMachineCommunicator.wakeDevice(any()))
          .thenAnswer((_) async => false);

      final controller = buildController();
      await controller.init();

      final result = await controller.processDirectPayment();

      expect(result, PaymentOutcome.machineError);
      expect(controller.paymentCompleted, isFalse);
    });

    test('returns failed when payment processor fails', () async {
      when(() => mockPaymentProcessor.processPayment(any(), any()))
          .thenAnswer((_) async => PaymentResult.failed);

      final controller = buildController();
      await controller.init();

      final result = await controller.processDirectPayment();

      expect(result, PaymentOutcome.failed);
      verifyNever(() => mockMachineCommunicator.wakeDevice(any()));
    });

    test('returns canceled when payment is canceled', () async {
      when(() => mockPaymentProcessor.processPayment(any(), any()))
          .thenAnswer((_) async => PaymentResult.canceled);

      final controller = buildController();
      await controller.init();

      final result = await controller.processDirectPayment();

      expect(result, PaymentOutcome.canceled);
    });

    test('schedules notification on success', () async {
      when(() => mockPaymentProcessor.processPayment(any(), any()))
          .thenAnswer((_) async => PaymentResult.success);
      when(() => mockMachineCommunicator.wakeDevice(any()))
          .thenAnswer((_) async => true);

      final controller = buildController();
      await controller.init();

      await controller.processDirectPayment();

      verify(() => mockNotificationService.scheduleEarlyMachineNotification(
        id: 1,
        machineTime: any(named: 'machineTime'),
        machineName: any(named: 'machineName'),
      )).called(1);
    });

    test('does not schedule notification when machine fails to wake',
            () async {
          when(() => mockPaymentProcessor.processPayment(any(), any()))
              .thenAnswer((_) async => PaymentResult.success);
          when(() => mockMachineCommunicator.wakeDevice(any()))
              .thenAnswer((_) async => false);

          final controller = buildController();
          await controller.init();

          await controller.processDirectPayment();

          verifyNever(() => mockNotificationService.scheduleEarlyMachineNotification(
            id: any(named: 'id'),
            machineTime: any(named: 'machineTime'),
            machineName: any(named: 'machineName'),
          ));
        });
  });

  // ---------------------------------------------------------------------------
  // processLoyaltyPayment
  // ---------------------------------------------------------------------------

  group('processLoyaltyPayment', () {
    setUp(() async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(() => mockMachineService.getMachineById(any()))
          .thenAnswer((_) async => {'Name': 'Dryer01', 'Price': 1.50});
      when(() => mockWalletService.redeemForMachine(
        machineId: any(named: 'machineId'),
        amountCents: any(named: 'amountCents'),
        note: any(named: 'note'),
      )).thenAnswer((_) async => <String, dynamic>{});
      when(() => mockTransactionService.recordTransaction(
        amount: any(named: 'amount'),
        description: any(named: 'description'),
        type: any(named: 'type'),
      ))
          .thenAnswer((_) async {});
    });

    test('returns success and sets paymentCompleted', () async {
      when(() => mockMachineCommunicator.wakeDevice(any()))
          .thenAnswer((_) async => true);

      final controller = buildController();
      await controller.init();

      final result = await controller.processLoyaltyPayment();

      expect(result, PaymentOutcome.success);
      expect(controller.paymentCompleted, isTrue);
    });

    test('redeems wallet cents and records the transaction on success', () async {
      when(() => mockMachineCommunicator.wakeDevice(any()))
          .thenAnswer((_) async => true);

      final controller = buildController();
      await controller.init();

      await controller.processLoyaltyPayment();

      expect(controller.userBalance, 8.5);
      verify(() => mockWalletService.redeemForMachine(
        machineId: 123,
        amountCents: 150,
        note: 'Loyalty payment on Dryer01',
      )).called(1);
      verifyNever(() => mockProfileService.updateBalanceById(any(), any()));
      verify(() => mockTransactionService.recordTransaction(
        amount: 1.50,
        description: any(named: 'description'),
        type: 'laundry',
      ))
          .called(1);
    });

    test('returns machineError, restores balance and does not redeem when device fails',
            () async {
          when(() => mockMachineCommunicator.wakeDevice(any()))
              .thenAnswer((_) async => false);

          final controller = buildController();
          await controller.init();

          final result = await controller.processLoyaltyPayment();

          expect(result, PaymentOutcome.machineError);
          expect(controller.paymentCompleted, isFalse);
          expect(controller.userBalance, 10.0);
          verifyNever(() => mockWalletService.redeemForMachine(
            machineId: any(named: 'machineId'),
            amountCents: any(named: 'amountCents'),
            note: any(named: 'note'),
          ));
          verifyNever(() => mockProfileService.updateBalanceById(any(), any()));
          verifyNever(() => mockTransactionService.recordTransaction(
            amount: any(named: 'amount'),
            description: any(named: 'description'),
            type: any(named: 'type'),
          ));
        });

    test('schedules notification on success', () async {
      when(() => mockMachineCommunicator.wakeDevice(any()))
          .thenAnswer((_) async => true);

      final controller = buildController();
      await controller.init();

      await controller.processLoyaltyPayment();

      verify(() => mockNotificationService.scheduleEarlyMachineNotification(
        id: 1,
        machineTime: any(named: 'machineTime'),
        machineName: any(named: 'machineName'),
      )).called(1);
    });

    test('does not schedule notification when machine fails', () async {
      when(() => mockMachineCommunicator.wakeDevice(any()))
          .thenAnswer((_) async => false);

      final controller = buildController();
      await controller.init();

      await controller.processLoyaltyPayment();

      verifyNever(() => mockNotificationService.scheduleEarlyMachineNotification(
        id: any(named: 'id'),
        machineTime: any(named: 'machineTime'),
        machineName: any(named: 'machineName'),
      ));
    });
  });
}
