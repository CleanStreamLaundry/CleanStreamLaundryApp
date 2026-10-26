import 'package:clean_stream_laundry_app/features/login/controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class FormFields extends StatelessWidget {
  final LoginController controller;

  const FormFields({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller.emailController,
          style: TextStyle(
            color: Theme.of(context).colorScheme.fontInverted,
          ),
          decoration: InputDecoration(
            labelText: controller.emailLabel,
            labelStyle: TextStyle(color: Theme.of(context).colorScheme.fontSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: controller.focusedBorderColor,
                width: 2.0,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: controller.enabledBorderColor),
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: Icon(Icons.email, color: controller.iconColor),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller.passwordController,
          style: TextStyle(
            color: Theme.of(context).colorScheme.fontInverted,
          ),
          decoration: InputDecoration(
            labelText: controller.passwordLabel,
            labelStyle: TextStyle(color: Theme.of(context).colorScheme.fontSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: controller.focusedBorderColor,
                width: 2.0,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: controller.enabledBorderColor),
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: Icon(Icons.lock, color: controller.iconColor),
            suffixIcon: IconButton(
              tooltip: controller.obscurePassword
                  ? 'Show password'
                  : 'Hide password',
              icon: Icon(
                controller.obscurePassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                color: Colors.blue,
              ),
              onPressed: controller.togglePasswordVisibility,
            ),
          ),
          obscureText: controller.obscurePassword,
        ),
      ],
    );
  }
}
