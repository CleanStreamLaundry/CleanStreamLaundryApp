import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

class LoginController extends ChangeNotifier {
  final AuthService authService;

  LoginController({AuthService? authService})
    : authService = authService ?? GetIt.instance<AuthService>();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  bool obscurePassword = true;
  bool googleSignInPending = false;
  bool appleSignInPending = false;
  bool _disposed = false;

  String passwordLabel = 'Password';
  String emailLabel = 'Email';
  Color iconColor = Colors.blue;
  Color enabledBorderColor = Colors.grey;
  Color focusedBorderColor = Colors.blue;
  Color labelColor = Colors.blue;

  void disposeController() {
    _disposed = true;
    if (googleSignInPending) authService.cancelGoogleSignIn();
    if (appleSignInPending) authService.cancelAppleSignIn();
    emailController.dispose();
    passwordController.dispose();
    scrollController.dispose();
  }

  Future<void> handleGoogleSignIn(BuildContext context) async {
    if (googleSignInPending || appleSignInPending) return;
    googleSignInPending = true;
    notifyListeners();
    try {
      final signedIn = await authService.googleSignIn();
      if (signedIn &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        context.go('/homePage');
      }
    } catch (_) {
      if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google sign-in could not finish. Please try again.'),
          ),
        );
      }
    } finally {
      googleSignInPending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> handleAppleSignIn(BuildContext context) async {
    if (appleSignInPending || googleSignInPending || _disposed) return;
    appleSignInPending = true;
    notifyListeners();
    try {
      final signedIn = await authService.appleSignIn();
      if (signedIn &&
          !_disposed &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        context.go('/homePage');
      }
    } catch (_) {
      if (!_disposed &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Apple sign-in could not finish. Please try again.'),
          ),
        );
      }
    } finally {
      appleSignInPending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> handleLogin(
    BuildContext context,
    void Function(String) showMessage,
  ) async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      showMessage('Please fill in both fields.');
      return;
    }

    showMessage('Logging in as $email...');
    final response = await authService.login(email, password);
    if (!context.mounted) return;

    if (response == AuthenticationResponses.success) {
      showMessage('Logged in as $email');
      context.go('/homePage');
    } else if (response == AuthenticationResponses.emailNotVerified) {
      context.go('/email-verification', extra: email);
    } else {
      setErrorColors();
    }
  }

  void setErrorColors() {
    passwordLabel = 'Invalid Password or Email';
    emailLabel = 'Invalid Password or Email';
    iconColor = Colors.red;
    enabledBorderColor = Colors.red;
    focusedBorderColor = Colors.red;
    labelColor = Colors.red;
    notifyListeners();
  }

  void togglePasswordVisibility() {
    obscurePassword = !obscurePassword;
    notifyListeners();
  }
}
