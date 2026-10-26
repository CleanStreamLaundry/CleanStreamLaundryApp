import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/parsing/machine_parser.dart';
import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_communication_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

enum PaymentOutcome { success, machineError, failed, canceled, pending }

class PaymentController extends ChangeNotifier {
  final AuthService authService;
  final MachineService machineService;
  final ProfileService profileService;
  final TransactionService transactionService;
  final WalletService walletService;
  final MachineCommunicationService machineCommunicator;
  final NotificationService notificationService;
  final PaymentProcessor paymentProcessor;

  final String machineId;

  PaymentController({
    required this.machineId,
    AuthService? authService,
    MachineService? machineService,
    ProfileService? profileService,
    TransactionService? transactionService,
    WalletService? walletService,
    MachineCommunicationService? machineCommunicator,
    NotificationService? notificationService,
    PaymentProcessor? paymentProcessor,
  }) : authService = authService ?? GetIt.instance<AuthService>(),
       machineService = machineService ?? GetIt.instance<MachineService>(),
       profileService = profileService ?? GetIt.instance<ProfileService>(),
       transactionService =
           transactionService ?? GetIt.instance<TransactionService>(),
       walletService = walletService ?? GetIt.instance<WalletService>(),
       machineCommunicator =
           machineCommunicator ?? GetIt.instance<MachineCommunicationService>(),
       notificationService =
           notificationService ?? GetIt.instance<NotificationService>(),
       paymentProcessor =
           paymentProcessor ?? GetIt.instance<PaymentProcessor>();

  bool isLoading = true;
  bool paymentCompleted = false;

  double? price;
  String? machineName;
  double? userBalance;

  double _basePrice = 0;
  double _addedWasherCost = 0;
  int dryerMinutes = 5;

  bool get isDryer =>
      machineName != null && machineName!.toLowerCase().contains('dryer');

  Future<void> init() async {
    final data = await machineService.getMachineById(machineId);
    final userId = authService.getCurrentUserId;

    if (userId == null) {
      isLoading = false;
      notifyListeners();
      return;
    }

    final balance = await walletService.getBalance();

    if (data != null) {
      _basePrice = (data['Price'] as num).toDouble();
      machineName = data['Name'] as String?;
      userBalance = balance.totalBalance;
      price = _basePrice;
    } else {
      userBalance = 0;
      machineName = 'Unknown';
      price = 0;
    }

    isLoading = false;
    notifyListeners();
  }

  void onDryerChanged(double newPrice, int minutes) {
    price = newPrice;
    dryerMinutes = minutes;
    notifyListeners();
  }

  void onWasherCycleChanged(double addedCost) {
    _addedWasherCost = addedCost;
    price = _basePrice + _addedWasherCost;
    notifyListeners();
  }

  Future<void> makeNotification(String name) async {
    await notificationService.scheduleEarlyMachineNotification(
      id: 1,
      machineTime: isDryer
          ? Duration(minutes: dryerMinutes)
          : const Duration(minutes: 5, seconds: 5),
      machineName: name,
    );
  }

  Future<PaymentOutcome> processDirectPayment() async {
    final result = await paymentProcessor.processPayment(
      price!,
      MachineFormatter.formatMachineType(machineName.toString()),
    );

    if (result == PaymentResult.pending) return PaymentOutcome.pending;

    if (result != PaymentResult.success) {
      return result == PaymentResult.canceled
          ? PaymentOutcome.canceled
          : PaymentOutcome.failed;
    }

    final deviceAuthorized = await machineCommunicator.wakeDevice(machineId);

    if (deviceAuthorized) {
      paymentCompleted = true;
      await makeNotification(machineName.toString());
      notifyListeners();
      return PaymentOutcome.success;
    } else {
      return PaymentOutcome.machineError;
    }
  }

  Future<PaymentOutcome> processLoyaltyPayment() async {
    final machineIdNumber = int.tryParse(machineId);
    if (machineIdNumber == null) {
      return PaymentOutcome.failed;
    }

    final updatedBalance = userBalance! - price!;
    userBalance = updatedBalance;
    notifyListeners();

    final deviceAuthorized = await machineCommunicator.wakeDevice(machineId);

    if (!deviceAuthorized) {
      userBalance = userBalance! + price!;
      notifyListeners();
      return PaymentOutcome.machineError;
    }

    try {
      await walletService.redeemForMachine(
        machineId: machineIdNumber,
        amountCents: (price! * 100).round(),
        note:
            'Loyalty payment on ${MachineFormatter.formatMachineType(machineName.toString())}',
      );
    } catch (_) {
      userBalance = userBalance! + price!;
      notifyListeners();
      return PaymentOutcome.failed;
    }

    paymentCompleted = true;
    notifyListeners();

    await transactionService.recordTransaction(
      amount: price!,
      description:
          'Loyalty payment on ${MachineFormatter.formatMachineType(machineName.toString())}',
      type: 'laundry',
    );

    await makeNotification(machineName.toString());

    return PaymentOutcome.success;
  }
}
