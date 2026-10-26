import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/parsing/password_parser.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

class ResetProtectedController extends ChangeNotifier {
  final AuthService authService;

  ResetProtectedController({AuthService? authService})
      : authService = authService ?? GetIt.instance<AuthService>();

  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();

  bool obscurePassword = true;
  bool obscureConfirm = true;
  bool isLoading = false;
  bool _disposed = false;

  String passwordLabel = 'New Password';
  String confirmLabel = 'Confirm Password';
  Color iconColor = Colors.blue;
  Color labelColor = Colors.blue;

  void disposeController() {
    _disposed = true;
    passwordController.dispose();
    confirmController.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void initColors(Color primary) {
    iconColor = primary;
    labelColor = primary;
    notifyListeners();
  }

  void togglePasswordVisibility() {
    obscurePassword = !obscurePassword;
    notifyListeners();
  }

  void toggleConfirmVisibility() {
    obscureConfirm = !obscureConfirm;
    notifyListeners();
  }

  void changeColorsToRed(String reason) {
    passwordLabel = reason;
    confirmLabel = reason;
    iconColor = Colors.red;
    labelColor = Colors.red;
    notifyListeners();
  }

  void resetColors() {
    passwordLabel = 'New Password';
    confirmLabel = 'Confirm Password';
    iconColor = Colors.blue;
    labelColor = Colors.blue;
    notifyListeners();
  }

  void onPasswordChanged() {
    if (iconColor == Colors.red) resetColors();
  }

  void onConfirmChanged() {
    if (passwordController.text != confirmController.text) {
      changeColorsToRed("Passwords don't match");
    } else {
      resetColors();
    }
  }

  Future<String?> submit() async {
    final password = passwordController.text.trim();
    final confirm = confirmController.text.trim();

    if (password.isEmpty || confirm.isEmpty) {
      return 'Please fill in all fields';
    }

    if (password != confirm) {
      changeColorsToRed("Passwords don't match");
      return 'Passwords don\'t match';
    }

    final requirementError = PasswordParser.process(password);
    if (requirementError != null) {
      changeColorsToRed(requirementError);
      return requirementError;
    }

    isLoading = true;
    notifyListeners();

    try {
      final response = await authService.updatePassword(password);
      if (response == AuthenticationResponses.compromisedPassword) {
        return 'This password was found in a data breach. Choose a different password.';
      }
      if (response == AuthenticationResponses.weakPassword) {
        return 'This password does not meet security requirements. Choose a stronger password.';
      }
      if (response != AuthenticationResponses.success) {
        throw StateError('Failed to reset password');
      }
      return null;
    } finally {
      isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }
}
