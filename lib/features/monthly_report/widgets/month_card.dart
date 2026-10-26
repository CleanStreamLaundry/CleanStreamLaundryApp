import 'transaction_row.dart';
import 'package:flutter/material.dart';

class MonthCard extends StatelessWidget {
  final String month;
  final Map<String, double> data;
  final Color cardBackgroundColor;
  final Color cardTextColor;
  final Color primaryColor;

  const MonthCard({
    super.key,
    required this.month,
    required this.data,
    required this.cardBackgroundColor,
    required this.cardTextColor,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final total =
        data['directWasher']! + data['directDryer']! + data['loyaltyCard']!;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cardTextColor.withValues(alpha: .16)),
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      color: cardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    month,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cardTextColor,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            TransactionRow(
              label: 'Direct Washer Payments',
              amount: data['directWasher']!,
              color: cardTextColor,
            ),
            const SizedBox(height: 8),
            TransactionRow(
              label: 'Loyalty Washer Payments',
              amount: data['loyaltyWasher']!,
              color: primaryColor,
            ),
            const SizedBox(height: 8),
            TransactionRow(
              label: 'Direct Dryer Payments',
              amount: data['directDryer']!,
              color: cardTextColor,
            ),
            const SizedBox(height: 8),
            TransactionRow(
              label: 'Loyalty Dryer Payments',
              amount: data['loyaltyDryer']!,
              color: primaryColor,
            ),
            const SizedBox(height: 8),
            TransactionRow(
              label: 'Loyalty Card Loads',
              amount: data['loyaltyCard']!,
              color: cardTextColor,
            ),
          ],
        ),
      ),
    );
  }
}
