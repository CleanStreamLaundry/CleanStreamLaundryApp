import 'controller.dart';
import 'widgets/form_fields.dart';
import 'widgets/info_banner.dart';
import 'package:clean_stream_laundry_app/features/sign_up/widgets/password_hint.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  SignUpPageState createState() => SignUpPageState();
}

class SignUpPageState extends State<SignUpPage> {
  late final SignUpController _controller;
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = SignUpController();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.disposeControllers();
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onSubmit() async {
    try {
      final result = await _controller.handleSignUp();
      if (!mounted) return;

      if (result.success) {
        _showMessage('Account created successfully.');
        context.go(
          '/email-verification',
          extra: _controller.emailController.text.trim(),
        );
        return;
      }

      if (result.message != null) {
        _showMessage(result.message!);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: KeyboardListener(
          focusNode: _focusNode,
          autofocus: kIsWeb,
          onKeyEvent: (keyEvent) {
            if (keyEvent is KeyDownEvent &&
                keyEvent.logicalKey == LogicalKeyboardKey.enter) {
              _onSubmit();
            }
          },
          child: ScrollbarTheme(
            data: ScrollbarThemeData(
              thumbColor: MaterialStateProperty.all(colors.primary),
            ),
            child: Scrollbar(
              controller: _scrollCtrl,
              thumbVisibility: true,
              interactive: true,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/Slogan.png',
                      height: 80,
                      width: 200,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 12),
                    const SignUpInfoBanner(),
                    const SizedBox(height: 16),
                    SignUpFormFields(
                      nameController: _controller.nameController,
                      emailController: _controller.emailController,
                      passwordController: _controller.passwordController,
                      confirmController: _controller.confirmController,
                      passwordLabel: _controller.passwordLabel,
                      confirmLabel: _controller.confirmPasswordLabel,
                      iconColor: _controller.iconColor,
                      labelColor: _controller.labelColor,
                      obscurePassword: _controller.obscurePassword,
                      obscureConfirmPassword:
                          _controller.obscureConfirmPassword,
                      onTogglePassword: _controller.togglePasswordVisibility,
                      onToggleConfirm: _controller.toggleConfirmVisibility,
                      onPasswordChanged: (_) => _controller.onPasswordChanged(),
                      onConfirmChanged: (_) => _controller.onConfirmChanged(),
                    ),
                    SignUpPasswordHint(
                      controller: _controller.passwordController,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _controller.isLoading ? null : _onSubmit,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          backgroundColor: colors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: _controller.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Create Account'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: InkWell(
                        onTap: () => context.go('/login'),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Center(
                            child: Text(
                              'Already have an account? Login',
                              style: TextStyle(
                                letterSpacing: 0,
                                color: colors.brightness == Brightness.dark
                                    ? colors.onSurface
                                    : colors.primary,
                                decoration: TextDecoration.underline,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
