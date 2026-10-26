import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class VerificationCodeField extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final ValueChanged<String>? onChanged;

  const VerificationCodeField({
    super.key,
    required this.controller,
    this.error,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = error != null;

    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: 6,
      style: TextStyle(
        letterSpacing: 0,
        color: scheme.fontInverted,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
      onChanged: onChanged,
      decoration: InputDecoration(
        constraints: const BoxConstraints(minHeight: 48),
        labelText: hasError ? error : '6-digit code',
        labelStyle: TextStyle(
          letterSpacing: 0,
          color: scheme.brightness == Brightness.dark
              ? scheme.fontInverted
              : (hasError ? scheme.error : scheme.primary),
        ),
        counterText: '',
        prefixIcon: Icon(
          Icons.lock,
          color: hasError ? Colors.red : scheme.primary,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }
}
