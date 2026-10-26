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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.email,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Divider(
                  color: Theme.of(context).colorScheme.secondary,
                  thickness: 3,
                  height: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  'Please verify your new email address',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    letterSpacing: 0,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.fontInverted,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Check your new email\'s inbox and click the verification link.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    letterSpacing: 0,
                    fontSize: 14,
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
      ),
    );
  }
}
