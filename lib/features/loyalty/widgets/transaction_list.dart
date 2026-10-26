import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import '../controller.dart';
import 'package:flutter/material.dart';

class TransactionList extends StatelessWidget {
  final LoyaltyController controller;
  final bool fillAvailableHeight;

  const TransactionList({
    super.key,
    required this.controller,
    this.fillAvailableHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    if (controller.recentTransactions.isEmpty) {
      if (controller.transactionsError != null) {
        return SizedBox(
          height: 76,
          child: Center(child: Text(controller.transactionsError!)),
        );
      }
      if (controller.isLoading) {
        return const SizedBox(
          height: 76,
          child: Center(child: Text('Loading transactions...')),
        );
      }
      return const _EmptyTransactionsCard();
    }

    final colors = Theme.of(context).colorScheme;
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 18;
    final transactions = controller.recentTransactions;
    final listView = ListView.separated(
      cacheExtent: 1000,
      shrinkWrap: !fillAvailableHeight,
      physics: fillAvailableHeight
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: transactions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _TransactionCard(transaction: transactions[index]);
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          mainAxisSize: stacked ? MainAxisSize.min : MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Text(
              'Transactions',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: colors.fontInverted,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('transactions-toggle-button'),
              onPressed: controller.toggleTransactionView,
              icon: Icon(
                controller.showPastTransactions
                    ? Icons.expand_less
                    : Icons.expand_more,
                color: colors.primary,
              ),
              label: Text(
                controller.showPastTransactions ? 'Show Less' : 'Show More',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (controller.transactionsError != null)
          Text(controller.transactionsError!),
        if (fillAvailableHeight) Expanded(child: listView) else listView,
        if (controller.showPastTransactions && controller.hasMoreTransactions)
          TextButton.icon(
            key: const ValueKey('transactions-next-page'),
            onPressed: controller.isLoadingMore || controller.isRefreshing
                ? null
                : controller.loadMoreTransactions,
            icon: const Icon(Icons.expand_more),
            label: Text(
              controller.isLoadingMore ? 'Loading...' : 'More transactions',
            ),
          ),
      ],
    );
  }
}

class _EmptyTransactionsCard extends StatelessWidget {
  const _EmptyTransactionsCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cardColor = colors.brightness == Brightness.dark
        ? const Color(0xFF262626)
        : Colors.white;

    return Material(
      color: cardColor,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                color: colors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No transactions found.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.fontSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final String transaction;

  const _TransactionCard({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cardColor = colors.brightness == Brightness.dark
        ? const Color(0xFF262626)
        : Colors.white;

    return Card(
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.10)),
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.07),
      color: cardColor,
      child: ListTile(
        minLeadingWidth: 40,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.receipt_long,
            color: Color(0xFF2073A9),
            size: 22,
          ),
        ),
        title: Text(
          transaction,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.fontInverted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
