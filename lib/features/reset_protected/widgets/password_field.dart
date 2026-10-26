import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String visibilityLabel;
  final bool obscureText;
  final VoidCallback onToggleVisibility;
  final ValueChanged<String>? onChanged;
  final Color iconColor;
  final Color labelColor;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.visibilityLabel = 'password',
    required this.obscureText,
    required this.onToggleVisibility,
    required this.iconColor,
    required this.labelColor,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          letterSpacing: 0,
          color: colorScheme.brightness == Brightness.dark
              ? colorScheme.fontInverted
              : (labelColor == Colors.blue ? colorScheme.primary : labelColor),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary, width: 2.0),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.fontSecondary),
          borderRadius: BorderRadius.circular(8),
        ),
        prefixIcon: Icon(
          Icons.lock,
          color: iconColor == Colors.blue ? colorScheme.primary : iconColor,
        ),
        suffixIcon: IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: '${obscureText ? 'Show' : 'Hide'} $visibilityLabel',
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
            color: colorScheme.brightness == Brightness.dark
                ? colorScheme.fontInverted
                : colorScheme.primary,
          ),
          onPressed: onToggleVisibility,
        ),
      ),
    );
  }
}
