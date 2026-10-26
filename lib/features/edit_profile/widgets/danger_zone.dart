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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        letterSpacing: 0,
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
                'Review your remaining credit, recovery period and loyalty terms before confirming deletion. You must explicitly restore your account before the recovery deadline; signing in alone does not cancel deletion. Deletion does not create a refund right or extend existing refund deadlines. Necessary payment, claim and legal records are handled separately.',
                style: TextStyle(
                  letterSpacing: 0,
                  color: isDark
                      ? colorScheme.fontSecondary
                      : colorScheme.fontSecondary.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
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
            foregroundColor: dangerTextColor,
            minimumSize: const Size(48, 48),
            side: const BorderSide(color: Colors.red, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
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
                    Icon(
                      needsStatusCheck ? Icons.refresh : Icons.delete_outline,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        needsStatusCheck
                            ? 'Check Account Status'
                            : 'Delete Account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          letterSpacing: 0,
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
    );
  }
}
