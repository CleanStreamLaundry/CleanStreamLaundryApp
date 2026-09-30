import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoadCardDialog extends StatefulWidget {
  final Future<void> Function(double amount) onPay;

  const LoadCardDialog({super.key, required this.onPay});

  @override
  State<LoadCardDialog> createState() => _LoadCardDialogState();
}

class _LoadCardDialogState extends State<LoadCardDialog> {
  double selectedAmount = 1.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Center(
        child: Text(
          'Load Loyalty Card',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: selectedAmount > 1.0
                      ? () => setState(() {
                          selectedAmount = (selectedAmount - 0.25).clamp(
                            1.0,
                            500.0,
                          );
                        })
                      : null,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: selectedAmount > 1.0 ? Colors.blue : Colors.grey,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '-25¢',
                    style: TextStyle(
                      color: selectedAmount > 1.0 ? Colors.blue : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '\$${selectedAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.fontInverted,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: selectedAmount < 500.0
                      ? () => setState(() {
                          selectedAmount = (selectedAmount + 0.25).clamp(
                            1.0,
                            500.0,
                          );
                        })
                      : null,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: selectedAmount < 500.0 ? Colors.blue : Colors.grey,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '+25¢',
                    style: TextStyle(
                      color: selectedAmount < 500.0 ? Colors.blue : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [10, 15, 25].map((amount) {
                return ChoiceChip(
                  label: Text('\$$amount'),
                  labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.fontInverted,
                  ),
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                  selected: selectedAmount == amount.toDouble(),
                  onSelected: (_) =>
                      setState(() => selectedAmount = amount.toDouble()),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                activeTrackColor: Colors.blue,
                inactiveTrackColor: Colors.blue.withAlpha(3),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                tickMarkShape: const RoundSliderTickMarkShape(
                  tickMarkRadius: 0,
                ),
              ),
              child: SizedBox(
                width: 650,
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: selectedAmount,
                        min: 1,
                        max: 500,
                        onChanged: (value) => setState(
                          () => selectedAmount = value.roundToDouble(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              'Loyalty Card loads are final sale prepaid Clean Stream Laundry credit. Balance is usable only for eligible Clean Stream Laundry services, is not a bank account, does not earn interest, and is not redeemable for cash except where required by law. Promotional bonus credits have no cash value and may be subject to separate terms.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.fontInverted.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/legal/loyalty-card');
              },
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.zero,
              ),
              child: const Text('View terms'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: Colors.blue[700])),
        ),
        ElevatedButton(
          onPressed: () async {
            final amount = selectedAmount;
            Navigator.of(context).pop();
            await widget.onPay(amount);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Pay',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
