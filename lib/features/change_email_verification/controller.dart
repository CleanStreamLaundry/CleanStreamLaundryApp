import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:get_it/get_it.dart';

class ChangeEmailVerificationController {
  final AuthService _authService = GetIt.instance<AuthService>();

  bool resent = false;
  bool isLoading = false;
  AuthenticationResponses? lastResponse;

  /// Resends verification email
  Future<void> resendVerification() async {
    if (resent) return;

    isLoading = true;
    lastResponse = await _authService.resendVerification();
    isLoading = false;

    if (lastResponse == AuthenticationResponses.success) {
      resent = true;
    }
  }
}
