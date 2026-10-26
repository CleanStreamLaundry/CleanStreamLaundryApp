import 'package:clean_stream_laundry_app/features/home/controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  final HomePageController controller;
  final VoidCallback onAddFunds;

  const Header({super.key, required this.controller, required this.onAddFunds});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 18;
    final username = controller.username?.trim();
    final balance = controller.balance?["balance"];
    final formattedBalance = balance is num
        ? '\$${balance.toStringAsFixed(2)}'
        : 'Loading...';
    final balanceText = Text(
      formattedBalance,
      maxLines: stacked ? null : 1,
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: colorScheme.homeAccent,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          username == null || username.isEmpty
              ? 'Welcome!'
              : 'Welcome, $username',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 23,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 5,
          shadowColor: Colors.black.withValues(alpha: 0.20),
          surfaceTintColor: Colors.transparent,
          color: colorScheme.homeCard,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: colorScheme.homeAccent.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Flex(
              direction: stacked ? Axis.vertical : Axis.horizontal,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: stacked
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: colorScheme.homeAccent.withValues(
                    alpha: 0.10,
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: colorScheme.homeAccent,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12, height: stacked ? 8 : 0),
                Flexible(
                  flex: stacked ? 0 : 1,
                  fit: stacked ? FlexFit.loose : FlexFit.tight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Wallet balance',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.fontSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (stacked)
                        balanceText
                      else
                        SizedBox(
                          // Fitting "Loading..." must not resize the map below.
                          height:
                              MediaQuery.textScalerOf(context).scale(28) *
                              (DefaultTextStyle.of(context).style.height ??
                                  1.2),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: balanceText,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: 8, height: stacked ? 8 : 0),
                FilledButton.tonalIcon(
                  key: const ValueKey('home-add-funds-button'),
                  onPressed: onAddFunds,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: Text(
                    'Add funds',
                    maxLines: stacked ? null : 1,
                    overflow: stacked ? null : TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
