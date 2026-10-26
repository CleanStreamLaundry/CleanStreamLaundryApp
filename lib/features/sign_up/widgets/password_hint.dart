import 'package:clean_stream_laundry_app/logic/parsing/password_parser.dart';
import 'package:flutter/material.dart';

class SignUpPasswordHint extends StatelessWidget {
  final TextEditingController controller;

  const SignUpPasswordHint({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final requirementText = PasswordParser.process(value.text);

        if (requirementText == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.secondary,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              requirementText,
              textAlign: TextAlign.center,
              style: TextStyle(
                letterSpacing: 0,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}
