import 'package:clean_stream_laundry_app/features/login/controller.dart';
import 'package:clean_stream_laundry_app/features/login/widgets/links.dart';
import 'package:clean_stream_laundry_app/features/login/widgets/form_fields.dart';
import 'package:clean_stream_laundry_app/features/login/widgets/social_sign_in_buttons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  late final LoginController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = LoginController();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.disposeController();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: kIsWeb,
        onKeyEvent: (keyEvent) {
          if (keyEvent is KeyDownEvent &&
              keyEvent.logicalKey == LogicalKeyboardKey.enter) {
            _controller.handleLogin(context, _showMessage);
          }
        },
        child: ScrollbarTheme(
          data: ScrollbarThemeData(
            thumbColor: WidgetStateProperty.all(Colors.blue),
          ),
          child: Scrollbar(
            controller: _controller.scrollController,
            interactive: true,
            thickness: 6,
            radius: const Radius.circular(8),
            child: SingleChildScrollView(
              controller: _controller.scrollController,
              padding: const EdgeInsets.fromLTRB(24.0, 60.0, 24.0, 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/splash-logo.png',
                    height: 300,
                    width: 300,
                    key: const Key('app_logo'),
                  ),
                  FormFields(controller: _controller),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () =>
                          _controller.handleLogin(context, _showMessage),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Log In'),
                    ),
                  ),
                  SocialSignInButtons(controller: _controller),
                  const LoginLinks(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
