import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ErrorView extends StatelessWidget {
  final String error;

  const ErrorView({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 80),
        const SizedBox(height: 20),
        Text(
          'Authentication Failed',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          error,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 26),
        ElevatedButton.icon(
          onPressed: () => context.go('/login'),
          icon: const Icon(Icons.login),
          label: const Text('Return to Login'),
          style: ElevatedButton.styleFrom(
            foregroundColor: colorScheme.brightness == Brightness.dark
                ? colorScheme.onSurface
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }
}
