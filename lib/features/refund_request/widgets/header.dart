import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  const Header({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.secondary, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            color: colorScheme.brightness == Brightness.dark
                ? Colors.white
                : colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submit a Refund Request',
                  style: TextStyle(
                    letterSpacing: 0,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.fontInverted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a transaction and describe your issue. '
                  'Our team will review it shortly.',
                  style: TextStyle(
                    letterSpacing: 0,
                    fontSize: 13,
                    color: colorScheme.fontSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
