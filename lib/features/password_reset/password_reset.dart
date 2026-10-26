import 'package:clean_stream_laundry_app/features/password_reset/controller.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({super.key});

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  late final PasswordResetController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PasswordResetController();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.disposeController();
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onSendPressed() async {
    try {
      final response = await _controller.sendResetEmail();

      if (!mounted) return;

      if (response == null) return;

      if (response == AuthenticationResponses.success) {
        _showMessage('Password reset email sent! Check your email.');
        context.go(
          '/verify-code',
          extra: _controller.emailController.text.trim(),
        );
      } else {
        _showMessage('Failed to send reset email.');
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(20) * 2 + 16,
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: scheme.primaryGradient),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, color: scheme.secondary),
        ),
        title: const Text('Reset Password', maxLines: 2, softWrap: true),
        leading: IconButton(
          tooltip: 'Back to Login',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              child: Form(
                key: _controller.formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.lock_reset, size: 64, color: scheme.primary),
                    const SizedBox(height: 24),
                    Text(
                      'Forgot your password?',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 20,
                            letterSpacing: 0,
                            color: scheme.fontInverted,
                          ) ??
                          TextStyle(
                            letterSpacing: 0,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: scheme.fontInverted,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Enter your email address and we\'ll send you a 6-digit reset code.',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                            letterSpacing: 0,
                            color: scheme.fontSecondary,
                          ) ??
                          TextStyle(
                            letterSpacing: 0,
                            color: scheme.fontSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _controller.emailController,
                      style: TextStyle(
                        letterSpacing: 0,
                        color: scheme.fontInverted,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintMaxLines: 3,
                        errorMaxLines: 3,
                        errorStyle: TextStyle(
                          letterSpacing: 0,
                          color: scheme.brightness == Brightness.dark
                              ? scheme.fontInverted
                              : scheme.error,
                        ),
                        labelText: 'Email',
                        labelStyle: TextStyle(
                          letterSpacing: 0,
                          color: scheme.brightness == Brightness.dark
                              ? scheme.fontInverted
                              : scheme.primary,
                        ),
                        hintText: 'Enter your email address',
                        hintStyle: TextStyle(
                          letterSpacing: 0,
                          color: scheme.fontInverted.withOpacity(0.6),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: scheme.primary,
                            width: 2.0,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: scheme.fontSecondary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: scheme.surface,
                        prefixIcon: Icon(Icons.email, color: scheme.primary),
                      ),
                      validator: _controller.validateEmail,
                      enabled: !_controller.isLoading,
                    ),
                    const SizedBox(height: 24),
                    _controller.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _onSendPressed,
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
                                backgroundColor: scheme.primary,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Send Reset Code'),
                            ),
                          ),
                    const SizedBox(height: 16),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        textStyle: const TextStyle(
                          letterSpacing: 0,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: _controller.isLoading
                          ? null
                          : () => context.go('/login'),
                      child: Text(
                        'Back to Login',
                        style: TextStyle(
                          letterSpacing: 0,
                          color: scheme.brightness == Brightness.dark
                              ? scheme.fontInverted
                              : scheme.primary,
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
