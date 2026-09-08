import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:flutter/material.dart';

class DryerAmountSelector extends StatelessWidget {
  final int amountCents;
  final List<CortinaDryerOption> options;
  final ValueChanged<int> onChanged;

  const DryerAmountSelector({
    super.key,
    required this.amountCents,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (option) => option.amountCents == amountCents,
      orElse: () => const CortinaDryerOption(minutes: 0, amountCents: 0),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text(
            'Choose drying time',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '${selected.minutes} minutes for '
            '\$${(amountCents / 100).toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2073A9),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: [
              for (final option in options)
                OutlinedButton(
                  onPressed: () => onChanged(option.amountCents),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: option.amountCents == amountCents
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: Text(
                    '${option.minutes} min\n'
                    '\$${(option.amountCents / 100).toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('\$0.25 per 5 minutes'),
        ],
      ),
    );
  }
}
