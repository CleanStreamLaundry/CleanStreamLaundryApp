import 'package:flutter/material.dart';

class SignUpInfoBanner extends StatelessWidget {
  const SignUpInfoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.secondary,
            width: 3,
          ),
        ),
      ),
      child: Text(
        'Enter your info to create your account.\n'
        ' After submitting, you will receive a confirmation email.',
        textAlign: TextAlign.center,
        style: TextStyle(
          letterSpacing: 0,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
