import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import '../controller.dart';
import 'wallet_pass_card.dart';
import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  final LoyaltyController controller;
  final VoidCallback onInfoTap;

  const Header({super.key, required this.controller, required this.onInfoTap});

  @override
  Widget build(BuildContext context) {
    final balance = controller.userBalance ?? 0.0;
    final paidBalance = controller.paidBalance ?? 0.0;
    final promoBalance = controller.promoBalance ?? 0.0;
    final rewardProgress = controller.userReward ?? 0.0;
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 18;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WalletPassCard(
          username: controller.userName ?? 'John Doe',
          balance: balance,
        ),
        const SizedBox(height: 10),
        Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            Flexible(
              flex: stacked ? 0 : 1,
              child: _BalanceTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Paid',
                amount: paidBalance,
              ),
            ),
            const SizedBox(width: 8, height: 8),
            Flexible(
              flex: stacked ? 0 : 1,
              child: _BalanceTile(
                icon: Icons.auto_awesome_rounded,
                label: 'Promo',
                amount: promoBalance,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _RewardProgressCard(progress: rewardProgress, onInfoTap: onInfoTap),
      ],
    );
  }
}

class _BalanceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final double amount;

  const _BalanceTile({
    required this.icon,
    required this.label,
    required this.amount,
  });

  String get _formattedAmount => '\$${amount.toStringAsFixed(2)}';

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
        constraints: const BoxConstraints(minHeight: 66),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$label $_formattedAmount',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.fontInverted,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardProgressCard extends StatelessWidget {
  static const double rewardThreshold = 20.0;

  final double progress;
  final VoidCallback onInfoTap;

  const _RewardProgressCard({required this.progress, required this.onInfoTap});

  double get _remaining {
    return (rewardThreshold - progress).clamp(0.0, rewardThreshold).toDouble();
  }

  double get _progressValue {
    return (progress / rewardThreshold).clamp(0.0, 1.0).toDouble();
  }

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
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.stars_rounded,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '\$${_remaining.toStringAsFixed(2)} until next reward',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.fontInverted,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onInfoTap,
                  icon: const Icon(Icons.info_outline),
                  iconSize: 19,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  color: colors.primary,
                  tooltip: 'Rewards program',
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _progressValue,
                minHeight: 8,
                backgroundColor: colors.primary.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
