import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

class SignUpResult {
  final bool success;

  final String? message;

  const SignUpResult._({required this.success, this.message});

  const SignUpResult.success() : this._(success: true, message: null);
  const SignUpResult.snackbar(String msg)
      : this._(success: false, message: msg);

  const SignUpResult.colorOnly() : this._(success: false, message: null);
}

class SignUpController extends ChangeNotifier {
  final AuthService authService;

  SignUpController({AuthService? authService})
      : authService = authService ?? GetIt.instance<AuthService>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();

  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  String passwordLabel = 'Password';
  String confirmPasswordLabel = 'Confirm Password';
  Color iconColor = Colors.blue;
  Color labelColor = Colors.blue;
  bool isLoading = false;

  void disposeControllers() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
  }

  void togglePasswordVisibility() {
    obscurePassword = !obscurePassword;
    notifyListeners();
  }

  void toggleConfirmVisibility() {
    obscureConfirmPassword = !obscureConfirmPassword;
    notifyListeners();
  }

  void changeColorsToRed(String reason) {
    passwordLabel = reason;
    confirmPasswordLabel = reason;
    iconColor = Colors.red;
    labelColor = Colors.red;
    notifyListeners();
  }

  void changeColorsToDefault() {
    passwordLabel = 'Password';
    confirmPasswordLabel = 'Confirm Password';
    iconColor = Colors.blue;
    labelColor = Colors.blue;
    notifyListeners();
  }

  void onPasswordChanged() {
    if (iconColor == Colors.red) changeColorsToDefault();
  }

  void onConfirmChanged() {
    final password = passwordController.text.trim();
    final confirm = confirmController.text.trim();
    if (password != confirm) {
      if (iconColor != Colors.red) changeColorsToRed("Passwords don't match");
    } else {
      changeColorsToDefault();
    }
  }

  Future<SignUpResult> handleSignUp() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirm = confirmController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty) {
      return const SignUpResult.snackbar('Please fill in all fields.');
    }
    if (password != confirm) {
      return const SignUpResult.snackbar('Passwords do not match.');
    }

    isLoading = true;
    notifyListeners();

    try {
      final response = await authService.signUp(email, password, name);

      switch (response) {
        case AuthenticationResponses.success:
          return const SignUpResult.success();
        case AuthenticationResponses.compromisedPassword:
          return const SignUpResult.snackbar(
            'This password was found in a data breach. Choose a different password.',
          );
        case AuthenticationResponses.weakPassword:
          return const SignUpResult.snackbar(
            'This password does not meet security requirements. Choose a stronger password.',
          );
        case AuthenticationResponses.noDigit:
          changeColorsToRed('Please include a digit');
          return const SignUpResult.colorOnly();
        case AuthenticationResponses.lessThanMinLength:
          changeColorsToRed('Password length is too short');
          return const SignUpResult.colorOnly();
        case AuthenticationResponses.noSpecialCharacter:
          changeColorsToRed('Please include a special character');
          return const SignUpResult.colorOnly();
        case AuthenticationResponses.noUppercase:
          changeColorsToRed('Please include an uppercase letter');
          return const SignUpResult.colorOnly();
        case AuthenticationResponses.invalidSpecialCharacter:
          changeColorsToRed('Please use a different special character');
          return const SignUpResult.colorOnly();
        default:
          return const SignUpResult.snackbar('Sign-up failed. Try again.');
      }
    } catch (_) {
      return const SignUpResult.snackbar('Sign-up failed. Try again.');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
