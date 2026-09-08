import 'package:flutter/material.dart';

class WasherCycleNotice extends StatelessWidget {
  final String? sizeLabel;

  const WasherCycleNotice({super.key, required this.sizeLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD6DCE1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF3C404).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.tune_rounded,
              size: 22,
              color: Color(0xFF165F8C),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose your cycle at the washer',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  sizeLabel == null
                      ? 'Select the cycle after payment.'
                      : '$sizeLabel washer settings are selected on the machine.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
