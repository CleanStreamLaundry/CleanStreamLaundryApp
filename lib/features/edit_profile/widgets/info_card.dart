import 'package:flutter/material.dart';

class InfoCard extends StatelessWidget {
  final String label;
  final String value;

  const InfoCard({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label),
        const SizedBox(width: 8),
        Flexible(child: Text(value)),
      ],
    );
  }
}
