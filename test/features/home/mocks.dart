import 'package:clean_stream_laundry_app/logic/parsing/location_parser.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {
  MockAuthService() {
    when(() => onAuthChange).thenAnswer((_) => const Stream.empty());
  }
}

class MockLocationService extends Mock implements LocationService {}

class MockMachineService extends Mock implements MachineService {}

class MockProfileService extends Mock implements ProfileService {}

class MockLocationParser extends Mock implements LocationParser {}

class MockWalletService extends Mock implements WalletService {}
