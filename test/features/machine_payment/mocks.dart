import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_communication_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}
class MockMachineService extends Mock implements MachineService {}
class MockProfileService extends Mock implements ProfileService {}
class MockTransactionService extends Mock implements TransactionService {}
class MockWalletService extends Mock implements WalletService {}
class MockMachineCommunicationService extends Mock implements MachineCommunicationService {}
class MockNotificationService extends Mock implements NotificationService {}
class MockPaymentProcessor extends Mock implements PaymentProcessor {}
class FakeAuthService extends Fake implements AuthService {}
