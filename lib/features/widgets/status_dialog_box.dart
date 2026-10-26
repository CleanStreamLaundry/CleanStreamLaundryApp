import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

Future<void> statusDialog(
  BuildContext context, {
  required String title,
  required String message,
  required bool isSuccess,
}) {
  return showDialog(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Theme.of(dialogContext).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  (isSuccess
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error)
                      .withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSuccess ? Icons.check_circle : Icons.error,
              color: isSuccess
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF8DCDF4)
                        : Theme.of(context).colorScheme.primary)
                  : Theme.of(context).colorScheme.error,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.fontInverted,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Theme.of(context).colorScheme.fontInverted,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
