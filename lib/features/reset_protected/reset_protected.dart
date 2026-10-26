import 'controller.dart';
import 'widgets/password_field.dart';
import 'widgets/password_requirements.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ResetProtectedPage extends StatefulWidget {
  const ResetProtectedPage({super.key});

  @override
  State<ResetProtectedPage> createState() => _ResetProtectedPageState();
}

class _ResetProtectedPageState extends State<ResetProtectedPage> {
  late final ResetProtectedController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ResetProtectedController();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.initColors(Theme.of(context).colorScheme.primary);
  }

  @override
  void dispose() {
    _controller.disposeController();
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onSubmitPressed() async {
    try {
      final error = await _controller.submit();

      if (!mounted) return;

      if (error != null) {
        _showMessage(error);
        return;
      }

      _showMessage('Password reset successful');
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to reset password');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Image.asset(
                    'assets/Logo.png',
                    height: 250,
                    width: 250,
                    fit: BoxFit.contain,
                    key: const Key('app_logo'),
                  ),
                  Text(
                    'Reset Password',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your new password below',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      letterSpacing: 0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  PasswordRequirementsHint(
                    controller: _controller.passwordController,
                  ),
                  PasswordField(
                    controller: _controller.passwordController,
                    label: _controller.passwordLabel,
                    obscureText: _controller.obscurePassword,
                    onToggleVisibility: _controller.togglePasswordVisibility,
                    onChanged: (_) => _controller.onPasswordChanged(),
                    iconColor: _controller.iconColor,
                    labelColor: _controller.labelColor,
                  ),
                  const SizedBox(height: 16),
                  PasswordField(
                    controller: _controller.confirmController,
                    label: _controller.confirmLabel,
                    visibilityLabel: 'confirmation password',
                    obscureText: _controller.obscureConfirm,
                    onToggleVisibility: _controller.toggleConfirmVisibility,
                    onChanged: (_) => _controller.onConfirmChanged(),
                    iconColor: _controller.iconColor,
                    labelColor: _controller.labelColor,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _controller.isLoading
                          ? null
                          : _onSubmitPressed,
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
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _controller.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Reset Password',
                              style: TextStyle(letterSpacing: 0, fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
