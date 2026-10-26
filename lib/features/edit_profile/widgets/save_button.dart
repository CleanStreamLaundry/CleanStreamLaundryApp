import 'package:flutter/material.dart';

class SaveButton extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onPressed;

  const SaveButton({
    super.key,
    required this.isSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: isSaving ? null : onPressed,
      child: isSaving
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 20),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Save Changes',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      letterSpacing: 0,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
