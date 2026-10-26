import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class SignUpFormFields extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmController;

  final String passwordLabel;
  final String confirmLabel;
  final Color iconColor;
  final Color labelColor;

  final bool obscurePassword;
  final bool obscureConfirmPassword;

  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String> onConfirmChanged;

  const SignUpFormFields({
    super.key,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmController,
    required this.passwordLabel,
    required this.confirmLabel,
    required this.iconColor,
    required this.labelColor,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onPasswordChanged,
    required this.onConfirmChanged,
  });

  InputDecoration _baseDecoration(BuildContext context) {
    return InputDecoration(
      constraints: const BoxConstraints(minHeight: 48),
      errorMaxLines: 3,
      hintMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2.0,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.fontSecondary,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = _baseDecoration(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          style: TextStyle(letterSpacing: 0, color: colorScheme.fontInverted),
          decoration: base.copyWith(
            labelText: 'Name',
            labelStyle: TextStyle(
              letterSpacing: 0,
              color: colorScheme.brightness == Brightness.dark
                  ? colorScheme.fontInverted
                  : colorScheme.primary,
            ),
            prefixIcon: Icon(Icons.person, color: colorScheme.primary),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: emailController,
          style: TextStyle(letterSpacing: 0, color: colorScheme.fontInverted),
          decoration: base.copyWith(
            labelText: 'Email',
            labelStyle: TextStyle(
              letterSpacing: 0,
              color: colorScheme.brightness == Brightness.dark
                  ? colorScheme.fontInverted
                  : colorScheme.primary,
            ),
            prefixIcon: Icon(Icons.email, color: colorScheme.primary),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: passwordController,
          obscureText: obscurePassword,
          onChanged: onPasswordChanged,
          style: TextStyle(letterSpacing: 0, color: colorScheme.fontInverted),
          decoration: base.copyWith(
            labelText: passwordLabel,
            labelStyle: TextStyle(
              letterSpacing: 0,
              color: colorScheme.brightness == Brightness.dark
                  ? colorScheme.fontInverted
                  : (labelColor == Colors.blue
                        ? colorScheme.primary
                        : labelColor),
            ),
            prefixIcon: Icon(
              Icons.lock,
              color: iconColor == Colors.blue ? colorScheme.primary : iconColor,
            ),
            suffixIcon: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: colorScheme.brightness == Brightness.dark
                    ? colorScheme.fontInverted
                    : colorScheme.primary,
              ),
              onPressed: onTogglePassword,
            ),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: confirmController,
          obscureText: obscureConfirmPassword,
          onChanged: onConfirmChanged,
          style: TextStyle(letterSpacing: 0, color: colorScheme.fontInverted),
          decoration: base.copyWith(
            labelText: confirmLabel,
            labelStyle: TextStyle(
              letterSpacing: 0,
              color: colorScheme.brightness == Brightness.dark
                  ? colorScheme.fontInverted
                  : (labelColor == Colors.blue
                        ? colorScheme.primary
                        : labelColor),
            ),
            prefixIcon: Icon(
              Icons.lock,
              color: iconColor == Colors.blue ? colorScheme.primary : iconColor,
            ),
            suffixIcon: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: obscureConfirmPassword
                  ? 'Show confirmation password'
                  : 'Hide confirmation password',
              icon: Icon(
                obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                color: colorScheme.brightness == Brightness.dark
                    ? colorScheme.fontInverted
                    : colorScheme.primary,
              ),
              onPressed: onToggleConfirm,
            ),
          ),
        ),
      ],
    );
  }
}
