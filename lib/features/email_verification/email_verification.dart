import 'package:clean_stream_laundry_app/features/email_verification/controller.dart';
import 'package:clean_stream_laundry_app/features/verify_code/widgets/code_field.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmailVerificationPage extends StatefulWidget {
  final String? email;

  const EmailVerificationPage({super.key, this.email});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  late final EmailVerificationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = EmailVerificationController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _resolveEmail() {
    final fromRoute = widget.email?.trim();
    if (fromRoute != null && fromRoute.isNotEmpty) {
      return fromRoute;
    }

    final fromSession = _controller.currentEmail?.trim();
    if (fromSession != null && fromSession.isNotEmpty) {
      return fromSession;
    }

    return null;
  }

  Future<void> _onVerifyPressed() async {
    final email = _resolveEmail();
    if (email == null) {
      _showMessage('Missing account email. Please log in and try again.');
      return;
    }

    setState(() {});
    final result = await _controller.verifyEmailCode(email);
    if (!mounted) return;

    setState(() {});
    if (result == EmailVerifyResult.success) {
      _showMessage('Email verified successfully!');
      context.go('/homePage');
    }
  }

  Future<void> _onResendPressed() async {
    final email = _resolveEmail();
    if (email == null) {
      _showMessage('Missing account email. Please log in and try again.');
      return;
    }

    setState(() {});
    final result = await _controller.resendVerificationEmail(email);
    if (!mounted) return;

    setState(() {});
    switch (result) {
      case EmailResendResult.success:
        _showMessage('Verification code sent! Check your email.');
        break;
      case EmailResendResult.failed:
        _showMessage('Failed to send verification code.');
        break;
      case EmailResendResult.error:
        _showMessage('Error sending verification code.');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final email = _resolveEmail();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(20) * 2 + 16,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: scheme.primaryGradient),
        ),
        foregroundColor: Colors.white,
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
        title: const Text('Verify Email', maxLines: 2, softWrap: true),
        leading: IconButton(
          tooltip: 'Back to Login',
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Icon(
                Icons.mark_email_read_outlined,
                size: 40,
                color: scheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Verify your email',
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
                      fontWeight: FontWeight.w600,
                      color: scheme.fontInverted,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Enter the 6-digit verification code we sent to your email address.',
                style:
                    Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.fontSecondary,
                      letterSpacing: 0,
                    ) ??
                    TextStyle(letterSpacing: 0, color: scheme.fontSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                email ?? 'your email',
                style: TextStyle(
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: scheme.fontInverted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              VerificationCodeField(
                controller: _controller.codeController,
                error: _controller.error,
                onChanged: (_) {
                  _controller.clearError();
                  setState(() {});
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _controller.isLoading ? null : _onVerifyPressed,
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
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _controller.isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify Email'),
                ),
              ),
              const SizedBox(height: 16),
              if (_controller.error != null)
                Text(
                  _controller.error!,
                  style: TextStyle(
                    letterSpacing: 0,
                    color: scheme.brightness == Brightness.dark
                        ? scheme.fontInverted
                        : scheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  textStyle: const TextStyle(letterSpacing: 0, fontSize: 14),
                ),
                onPressed: _controller.isLoading ? null : _onResendPressed,
                child: Text(
                  'Resend code',
                  style: TextStyle(
                    letterSpacing: 0,
                    color: scheme.brightness == Brightness.dark
                        ? scheme.fontInverted
                        : scheme.primary,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  textStyle: const TextStyle(letterSpacing: 0, fontSize: 14),
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
    );
  }
}
