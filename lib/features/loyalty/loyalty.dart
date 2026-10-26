import 'dart:math' as math;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'controller.dart';
import 'widgets/load_card_dialog.dart';
import 'widgets/header.dart';
import 'widgets/transaction_list.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:clean_stream_laundry_app/features/widgets/status_dialog_box.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoyaltyPage extends StatefulWidget {
  final LoyaltyController? controller;
  final bool openLoadCardOnStart;
  final VoidCallback? onWalletActivity;

  const LoyaltyPage({
    super.key,
    this.controller,
    this.openLoadCardOnStart = false,
    this.onWalletActivity,
  });

  @override
  State<LoyaltyPage> createState() => _LoyaltyPageState();
}

class _LoyaltyPageState extends State<LoyaltyPage> with WidgetsBindingObserver {
  late LoyaltyController controller;
  bool _routeCurrent = true;
  bool _branchActive = true;
  bool _handlingPayment = false;
  bool _initialized = false;
  bool _foreground = true;
  bool _loadCardRequested = false;
  DialogRoute<void>? _loadCardRoute;
  int? _loadCardAccount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = widget.controller ?? LoyaltyController();
    controller.addListener(_rebuild);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _loadCardRequested = widget.openLoadCardOnStart;
  }

  @override
  void didUpdateWidget(covariant LoyaltyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.openLoadCardOnStart) {
      _loadCardRequested = false;
    } else if (!oldWidget.openLoadCardOnStart) {
      _loadCardRequested = true;
    }
    _scheduleLoadCard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_rebuild);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
    if (_loadCardAccount != null &&
        _loadCardAccount != controller.accountEpoch) {
      _dismissLoadCard();
      _loadCardRequested = false;
    }
    _scheduleLoadCard();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _branchActive = TickerMode.of(context);
    final current =
        _branchActive && (ModalRoute.of(context)?.isCurrent ?? true);
    controller.setActive(current && _foreground);
    if (!_initialized) {
      _initialized = true;
      controller.initialize();
    } else if (current && !_routeCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _routeCurrent && _foreground && !_handlingPayment) {
          controller.refresh(ifStale: true);
        }
      });
    }
    _routeCurrent = current;
    if (!_branchActive) _dismissLoadCard();
    _scheduleLoadCard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    controller.setActive(_routeCurrent && _foreground);
    if (_foreground && _routeCurrent && !_handlingPayment) {
      controller.refresh(ifStale: true);
    }
  }

  void _scheduleLoadCard() {
    if (!_loadCardRequested) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_branchActive ||
          (!_routeCurrent && _loadCardRoute == null) ||
          !_foreground ||
          !_loadCardRequested ||
          !controller.isCurrentAccount) {
        return;
      }
      _loadCardRequested = false;
      final router = GoRouter.of(context);
      final uri = router.routeInformationProvider.value.uri;
      if (uri.queryParameters['loadCard'] == 'true') {
        // Replace the action-bearing history entry, preserving every other
        // parameter. Back/forward must not replay a consumed payment form.
        final query = Map<String, dynamic>.from(uri.queryParametersAll)
          ..remove('loadCard');
        Router.neglect(context, () {
          router.replace(uri.replace(queryParameters: query).toString());
        });
      }
      _showLoadCardDialog();
    });
  }

  void _dismissLoadCard() {
    final route = _loadCardRoute;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  void _showRewardInfoDialog() {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rewards program'),
        content: const Text(
          'For every \$20 you spend, you get an extra \$5 automatically added to your loyalty balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showRewardsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ListenableBuilder(
        listenable: controller,
        builder: (_, _) => _RewardsSheet(controller: controller),
      ),
    );
  }

  void _showLoadCardDialog() {
    if (!_routeCurrent ||
        !_foreground ||
        _loadCardRoute != null ||
        _handlingPayment ||
        controller.isPaying ||
        !controller.isCurrentAccount) {
      return;
    }
    final account = controller.accountEpoch;
    _loadCardAccount = account;
    final route = DialogRoute<void>(
      context: context,
      builder: (_) => LoadCardDialog(
        loadConsent: controller.loadPurchaseConsent,
        onPay: (amount, consent) async {
          if (mounted &&
              _branchActive &&
              controller.isCurrentAccount &&
              account == controller.accountEpoch) {
            await _handlePayment(amount, consent);
          }
        },
      ),
    );
    _loadCardRoute = route;
    Navigator.of(context).push(route).whenComplete(() {
      if (identical(_loadCardRoute, route)) {
        _loadCardRoute = null;
        _loadCardAccount = null;
      }
    });
  }

  Future<void> _handlePayment(double amount, Map<String, dynamic> consent) async {
    if (_handlingPayment) return;
    _handlingPayment = true;
    final account = controller.accountEpoch;
    late final PaymentResult result;
    try {
      result = await controller.loadCard(amount, consent: consent);
    } finally {
      _handlingPayment = false;
    }
    if (!mounted ||
        !controller.isCurrentAccount ||
        account != controller.accountEpoch) {
      return;
    }
    if (result == PaymentResult.success || result == PaymentResult.pending) {
      widget.onWalletActivity?.call();
    }
    if (!_branchActive) return;

    if (result == PaymentResult.success) {
      statusDialog(
        context,
        title: 'Payment Successful!',
        message:
            'Thank you! Your payment of \$${amount.toStringAsFixed(2)} was processed successfully.',
        isSuccess: true,
      );
    } else if (result == PaymentResult.canceled) {
      statusDialog(
        context,
        title: 'Payment Canceled',
        message: 'Payment of \$${amount.toStringAsFixed(2)} was canceled.',
        isSuccess: false,
      );
    } else if (result == PaymentResult.pending) {
      showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.hourglass_top),
          title: const Text('Payment verification pending'),
          content: const Text(
            'We could not yet confirm the outcome of this payment. '
            'Check your wallet activity or contact Clean Stream support before '
            'making another payment. A balance refresh does not confirm this charge.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else {
      statusDialog(
        context,
        title: 'Payment Failed',
        message:
            'An error occurred while processing your payment. Please try again.',
        isSuccess: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 106,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: Theme.of(context).colorScheme.primaryGradient,
              ),
            ),
          ),
          SafeArea(
            top: false,
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metrics = _LoyaltyLayoutMetrics.fromConstraints(
                  constraints,
                  showPastTransactions: controller.showPastTransactions,
                  enlargedText: MediaQuery.textScalerOf(context).scale(14) > 18,
                );
                final content = _LoyaltyContent(
                  metrics: metrics,
                  controller: controller,
                  onInfoTap: _showRewardInfoDialog,
                  onLoadCard: _showLoadCardDialog,
                  onRewardsTap: _showRewardsSheet,
                );

                return _LoyaltyResponsiveWrapper(
                  metrics: metrics,
                  child: metrics.needsScrollFallback
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                            vertical: metrics.verticalPadding,
                          ),
                          child: content,
                        )
                      : Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: metrics.verticalPadding,
                          ),
                          child: content,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoyaltyContent extends StatelessWidget {
  final _LoyaltyLayoutMetrics metrics;
  final LoyaltyController controller;
  final VoidCallback onInfoTap;
  final VoidCallback onLoadCard;
  final VoidCallback onRewardsTap;

  const _LoyaltyContent({
    required this.metrics,
    required this.controller,
    required this.onInfoTap,
    required this.onLoadCard,
    required this.onRewardsTap,
  });

  @override
  Widget build(BuildContext context) {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.isCurrentAccount && controller.userBalance != null)
          Header(controller: controller, onInfoTap: onInfoTap)
        else
          SizedBox(
            height: 200,
            child: Center(
              child: Text(
                controller.isLoading
                    ? 'Loading wallet...'
                    : 'Wallet balance unavailable',
              ),
            ),
          ),
        if (controller.errorMessage != null)
          Text(
            controller.userBalance == null
                ? controller.errorMessage!
                : '${controller.errorMessage}. Showing the last loaded balance.',
          ),
      ],
    );
    final loadButton = _LoadCardButton(
      onPressed: controller.isPaying || !controller.isCurrentAccount
          ? null
          : onLoadCard,
    );
    final transactions = !controller.isCurrentAccount
        ? const SizedBox.shrink()
        : TransactionList(
            controller: controller,
            fillAvailableHeight: !metrics.needsScrollFallback,
          );

    if (metrics.needsScrollFallback) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _WalletPageTitle(onRewardsTap: onRewardsTap, controller: controller),
          SizedBox(height: metrics.gap),
          header,
          SizedBox(height: metrics.gap),
          loadButton,
          SizedBox(height: metrics.gap),
          transactions,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WalletPageTitle(onRewardsTap: onRewardsTap, controller: controller),
        SizedBox(height: metrics.gap),
        header,
        SizedBox(height: metrics.gap),
        loadButton,
        SizedBox(height: metrics.gap),
        Expanded(child: transactions),
      ],
    );
  }
}

class _WalletPageTitle extends StatelessWidget {
  final VoidCallback onRewardsTap;
  final LoyaltyController controller;

  const _WalletPageTitle({
    required this.onRewardsTap,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      overflowSpacing: 8,
      children: [
        Text(
          'Wallet',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Refresh wallet',
              onPressed: controller.isRefreshing || controller.isPaying
                  ? null
                  : controller.refresh,
              icon: const Icon(Icons.refresh),
              color: Colors.white,
            ),
            IconButton(
              tooltip: 'Top-up refunds',
              onPressed: controller.isPaying || !controller.isCurrentAccount
                  ? null
                  : () => context.go('/topup-refunds'),
              icon: const Icon(Icons.receipt_long_outlined),
              color: Colors.white,
            ),
            Material(
              key: const ValueKey('rewards-sheet-button'),
              color: colors.primary,
              borderRadius: BorderRadius.circular(999),
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.16),
              child: InkWell(
                onTap: onRewardsTap,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.stars_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Rewards',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RewardsSheet extends StatelessWidget {
  static const double _rewardThreshold = 20.0;

  final LoyaltyController controller;

  const _RewardsSheet({required this.controller});

  double get _progress {
    return (controller.userReward ?? 0.0)
        .clamp(0.0, _rewardThreshold)
        .toDouble();
  }

  double get _remaining {
    return (_rewardThreshold - _progress)
        .clamp(0.0, _rewardThreshold)
        .toDouble();
  }

  double get _progressValue {
    return (_progress / _rewardThreshold).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rewards = controller.isCurrentAccount
        ? controller.rewardTransactions
        : <String>[];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rewards',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: colors.fontInverted,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: colors.fontSecondary,
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (controller.isCurrentAccount && controller.userReward != null)
                _RewardsStatusCard(
                  remaining: _remaining,
                  progressValue: _progressValue,
                ),
              const SizedBox(height: 10),
              const _RewardsRuleCard(),
              const SizedBox(height: 18),
              Text(
                'Reward history',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.fontInverted,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              if (controller.rewardsError != null)
                Text(controller.rewardsError!),
              if (rewards.isEmpty &&
                  controller.rewardsError == null &&
                  !controller.isRefreshing)
                const _EmptyRewardsCard()
              else if (rewards.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: rewards.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _RewardHistoryTile(transaction: rewards[index]);
                    },
                  ),
                ),
              if (controller.hasMoreRewards)
                TextButton.icon(
                  onPressed:
                      controller.isLoadingRewards || controller.isRefreshing
                      ? null
                      : () =>
                            controller.loadMoreTransactions(rewardsOnly: true),
                  icon: const Icon(Icons.expand_more),
                  label: Text(
                    controller.isLoadingRewards ? 'Loading...' : 'More rewards',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardsStatusCard extends StatelessWidget {
  final double remaining;
  final double progressValue;

  const _RewardsStatusCard({
    required this.remaining,
    required this.progressValue,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _RewardsCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.stars_rounded,
                  color: colors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\$${remaining.toStringAsFixed(2)} until your next \$5 reward',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.fontInverted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Promo credit is added automatically.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.fontSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 9,
              backgroundColor: colors.primary.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardsRuleCard extends StatelessWidget {
  const _RewardsRuleCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _RewardsCardShell(
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
              Icons.auto_awesome_rounded,
              color: colors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Earn \$5 promo credit for every \$20 loaded.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.fontInverted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRewardsCard extends StatelessWidget {
  const _EmptyRewardsCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _RewardsCardShell(
      child: Text(
        'No rewards earned yet.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colors.fontSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RewardHistoryTile extends StatelessWidget {
  final String transaction;

  const _RewardHistoryTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _RewardsCardShell(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.stars_rounded, color: colors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              transaction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.fontInverted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardsCardShell extends StatelessWidget {
  final Widget child;

  const _RewardsCardShell({required this.child});

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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }
}

class _LoadCardButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _LoadCardButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.add_rounded, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Load card',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 30),
        ],
      ),
    );
  }
}

class _LoyaltyResponsiveWrapper extends StatelessWidget {
  final _LoyaltyLayoutMetrics metrics;
  final Widget child;

  const _LoyaltyResponsiveWrapper({required this.metrics, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
        child: SizedBox(
          width: metrics.contentWidth,
          height: metrics.availableHeight,
          child: child,
        ),
      ),
    );
  }
}

class _LoyaltyLayoutMetrics {
  final double availableHeight;
  final double horizontalPadding;
  final double contentWidth;
  final double verticalPadding;
  final double gap;
  final bool needsScrollFallback;

  const _LoyaltyLayoutMetrics({
    required this.availableHeight,
    required this.horizontalPadding,
    required this.contentWidth,
    required this.verticalPadding,
    required this.gap,
    required this.needsScrollFallback,
  });

  factory _LoyaltyLayoutMetrics.fromConstraints(
    BoxConstraints constraints, {
    required bool showPastTransactions,
    required bool enlargedText,
  }) {
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 390.0;
    final height = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 700.0;
    final horizontalPadding = width < 380 ? 16.0 : 20.0;
    final contentWidth = math.min(
      500.0,
      math.max(0.0, width - (horizontalPadding * 2)),
    );
    final compactHeight = height < 760;
    final verticalPadding = compactHeight ? 4.0 : 8.0;
    final gap = compactHeight ? 6.0 : 8.0;

    return _LoyaltyLayoutMetrics(
      availableHeight: height,
      horizontalPadding: horizontalPadding,
      contentWidth: contentWidth,
      verticalPadding: verticalPadding,
      gap: gap,
      needsScrollFallback:
          height < 640.0 || width < 380 || enlargedText || showPastTransactions,
    );
  }
}
