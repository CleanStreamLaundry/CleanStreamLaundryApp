import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/features/change_email_verification/controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  test('constructs with AuthService alone without consuming callbacks', () {
    final controller = ChangeEmailVerificationController();

    expect(controller.resent, isFalse);
    expect(controller.isLoading, isFalse);
    expect(controller.lastResponse, isNull);
    verifyZeroInteractions(mockAuthService);
  });

  group('resendVerification', () {
    test('resend verification is called', () async {
      when(() => mockAuthService.resendVerification())
          .thenAnswer((_) async => AuthenticationResponses.success);

      final controller = ChangeEmailVerificationController();
      await controller.resendVerification();

      verify(() => mockAuthService.resendVerification()).called(1);
    });

    test('sets resent to true on success', () async {
      when(() => mockAuthService.resendVerification())
          .thenAnswer((_) async => AuthenticationResponses.success);

      final controller = ChangeEmailVerificationController();
      await controller.resendVerification();

      expect(controller.resent, isTrue);
      expect(controller.lastResponse, equals(AuthenticationResponses.success));
    });

    test('sets lastResponse on failure and does not set resent', () async {
      when(() => mockAuthService.resendVerification())
          .thenAnswer((_) async => AuthenticationResponses.error);

      final controller = ChangeEmailVerificationController();
      await controller.resendVerification();

      expect(controller.resent, isFalse);
      expect(controller.lastResponse, equals(AuthenticationResponses.error));
    });

    test('does not call resend again when already resent', () async {
      when(() => mockAuthService.resendVerification())
          .thenAnswer((_) async => AuthenticationResponses.success);

      final controller = ChangeEmailVerificationController();
      await controller.resendVerification();
      await controller.resendVerification();

      verify(() => mockAuthService.resendVerification()).called(1);
    });
  });
}
