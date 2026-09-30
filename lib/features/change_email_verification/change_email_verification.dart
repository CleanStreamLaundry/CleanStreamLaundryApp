import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'widgets/resend_verification.dart';

class ChangeEmailVerificationPage extends StatefulWidget {
  const ChangeEmailVerificationPage({super.key});

  @override
  State<ChangeEmailVerificationPage> createState() =>
      _ChangeEmailVerificationPageState();
}

class _ChangeEmailVerificationPageState
    extends State<ChangeEmailVerificationPage> {
  late final ChangeEmailVerificationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChangeEmailVerificationController();
  }

  void _refresh() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.email, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 24),
              Text(
                'Please verify your new email address',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.fontInverted,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Check your new email\'s inbox and click the verification link.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.fontSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ResendVerificationWidget(
                controller: _controller,
                onStateChange: _refresh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
