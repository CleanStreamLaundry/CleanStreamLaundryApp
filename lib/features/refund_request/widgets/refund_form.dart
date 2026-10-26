import '../controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/refund_request/widgets/transactions_search_sheet.dart';
import 'package:flutter/material.dart';

class RefundForm extends StatelessWidget {
  final RefundController controller;

  const RefundForm({super.key, required this.controller});

  InputDecoration _inputDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      hintMaxLines: 3,
      errorMaxLines: 3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.fontSecondary, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.fontSecondary, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a Transaction',
          style: TextStyle(
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: colorScheme.fontInverted,
          ),
        ),
        const SizedBox(height: 8),

        controller.isFetchingTransactions
            ? const Center(child: CircularProgressIndicator())
            : GestureDetector(
                onTap: () async {
                  final selected = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TransactionSearchSheet(
                      transactions: controller.recentTransactions,
                    ),
                  );
                  if (selected != null) {
                    controller.selectTransaction(selected);
                  }
                },
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: _inputDecoration(context).copyWith(
                      hintText: 'Select a transaction',
                      hintStyle: TextStyle(
                        letterSpacing: 0,
                        color: colorScheme.fontSecondary,
                      ),
                    ),
                    controller: TextEditingController(
                      text: controller.selectedTransaction,
                    ),
                    style: TextStyle(
                      letterSpacing: 0,
                      color: colorScheme.fontInverted,
                    ),
                  ),
                ),
              ),

        const SizedBox(height: 24),

        Text(
          'Reason for Refund',
          style: TextStyle(
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: colorScheme.fontInverted,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller.descriptionController,
          minLines: 8,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: TextStyle(letterSpacing: 0, color: colorScheme.fontInverted),
          decoration: _inputDecoration(context).copyWith(
            hintText: 'Describe the issue with your transaction...',
            hintStyle: TextStyle(
              letterSpacing: 0,
              color: colorScheme.fontSecondary,
            ),
          ),
        ),

        if (controller.attemptedSubmit && !controller.isFormValid)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.brightness == Brightness.dark
                      ? colorScheme.fontSecondary
                      : colorScheme.error,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Please fill in all fields',
                    style: TextStyle(
                      letterSpacing: 0,
                      color: colorScheme.brightness == Brightness.dark
                          ? colorScheme.fontSecondary
                          : colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
