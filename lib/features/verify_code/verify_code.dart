import 'controller.dart';
import 'widgets/code_field.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CodeVerificationPage extends StatefulWidget {
  final String email;

  const CodeVerificationPage({super.key, required this.email});

  @override
  State<CodeVerificationPage> createState() => _CodeVerificationPageState();
}

class _CodeVerificationPageState extends State<CodeVerificationPage> {
  late final CodeVerificationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CodeVerificationController();
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

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onVerifyPressed() async {
    final result = await _controller.verifyCode(widget.email);
    if (!mounted) return;

    if (result == VerifyResult.success) {
      context.go('/reset-protected');
    }
  }

  Future<void> _onResendPressed() async {
    final result = await _controller.sendResetEmail(widget.email);
    if (!mounted) return;

    switch (result) {
      case ResendResult.success:
        _showMessage('Password reset email sent! Check your email.');
        break;
      case ResendResult.failed:
        _showMessage('Failed to send reset email.');
        break;
      case ResendResult.error:
        _showMessage('Error sending reset email.');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
        title: const Text('Verify Code', maxLines: 2, softWrap: true),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Text(
                'Enter Verification Code',
                style: TextStyle(
                  letterSpacing: 0,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.fontInverted,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a 6-digit code to',
                style: TextStyle(
                  letterSpacing: 0,
                  color: scheme.fontInverted.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                widget.email,
                style: TextStyle(
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: scheme.fontInverted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              VerificationCodeField(
                controller: _controller.codeController,
                error: _controller.error,
                onChanged: (_) => _controller.clearError(),
              ),
              const SizedBox(height: 16),
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
                      : const Text('Verify'),
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
                ),
              const SizedBox(height: 16),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  textStyle: const TextStyle(letterSpacing: 0, fontSize: 14),
                ),
                onPressed: _onResendPressed,
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
            ],
          ),
        ),
      ),
    );
  }
}
