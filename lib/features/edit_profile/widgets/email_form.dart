import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class EmailFormField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;

  const EmailFormField({
    super.key,
    required this.controller,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      enabled: enabled,
      style: TextStyle(
        letterSpacing: 0,
        color: Theme.of(context).colorScheme.fontSecondary,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        labelText: 'New Email',
        hintText: 'Enter your email address',
        hintMaxLines: 3,
        errorMaxLines: 3,
        errorStyle: isDark
            ? TextStyle(letterSpacing: 0, color: colorScheme.fontSecondary)
            : null,
        hintStyle: TextStyle(
          letterSpacing: 0,
          color: colorScheme.fontSecondary,
        ),
        labelStyle: TextStyle(
          letterSpacing: 0,
          color: isDark ? colorScheme.fontSecondary : colorScheme.primary,
          fontSize: 14,
        ),
        filled: true,
        fillColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.03),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2.0,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.fontSecondary.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        prefixIcon: Icon(
          Icons.email_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Email cannot be empty';
        }
        if (!value.trim().contains('@')) {
          return 'Please enter a valid email';
        }
        return null;
      },
    );
  }
}
