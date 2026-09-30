import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class DangerZoneSection extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onDeletePressed;
  final bool needsStatusCheck;
  final String? message;

  const DangerZoneSection({
    super.key,
    required this.isSaving,
    required this.onDeletePressed,
    this.needsStatusCheck = false,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final dangerTextColor = isDark
        ? colorScheme.fontInverted
        : colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Danger Zone',
                  style: TextStyle(
                    color: dangerTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Request account deletion with a 30-day recovery window. Account access will be restricted until you sign in again and explicitly restore it before the deadline. Financial records and your Loyalty Card balance are not erased by this request.',
            style: TextStyle(
              color: isDark
                  ? colorScheme.fontSecondary
                  : colorScheme.fontSecondary.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(liveRegion: true, child: Text(message!)),
            ),
          OutlinedButton(
            onPressed: isSaving ? null : onDeletePressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.red,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(needsStatusCheck ? Icons.refresh : Icons.delete_outline, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          needsStatusCheck ? 'Check Account Status' : 'Delete Account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: dangerTextColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
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
