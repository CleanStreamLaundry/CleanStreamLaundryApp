import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NameFormField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;

  const NameFormField({
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
      inputFormatters: [
        LengthLimitingTextInputFormatter(36),
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 ]')),
      ],
      maxLength: 36,
      style: TextStyle(
        color: Theme.of(context).colorScheme.fontSecondary,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        labelText: 'New Full Name',
        hintText: 'Enter your full name',
        hintStyle: TextStyle(
          color: colorScheme.fontSecondary,
        ),
        labelStyle: TextStyle(
          color: isDark ? colorScheme.fontSecondary : colorScheme.primary,
          fontSize: 14,
        ),
        counterStyle: TextStyle(
          color: isDark
              ? colorScheme.fontSecondary
              : colorScheme.fontSecondary.withValues(alpha: 0.6),
        ),
        filled: true,
        fillColor:
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.03),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2.0,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .fontSecondary
                .withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        prefixIcon: Icon(
          Icons.person_outline,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Name cannot be empty';
        }
        return null;
      },
    );
  }
}
