import 'package:flutter/material.dart';

class TransactionRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const TransactionRow({
    super.key,
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      style: TextStyle(fontSize: 14, height: 1.4, color: color),
    );
    final amountText = Text(
      '\$${amount.toStringAsFixed(2)}',
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
    );
    if (MediaQuery.textScalerOf(context).scale(14) > 21) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [labelText, const SizedBox(height: 4), amountText],
      );
    }
    return Row(
      children: [
        Expanded(flex: 3, child: labelText),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: amountText),
      ],
    );
  }
}
