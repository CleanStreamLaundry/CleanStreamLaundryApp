import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class VerificationError extends StatelessWidget {
  const VerificationError({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFFB3261E),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.close, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Please resend verification again at another time.',
          textAlign: TextAlign.center,
          style: TextStyle(
            letterSpacing: 0,
            fontSize: 16,
            color: Theme.of(context).colorScheme.fontInverted,
          ),
        ),
      ],
    );
  }
}
