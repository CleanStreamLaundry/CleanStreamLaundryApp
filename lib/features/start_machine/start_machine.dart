import 'dart:math' as math;

import 'controller.dart';
import 'widgets/searching_dialog.dart';
import 'widgets/tap_card.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/services/kisi/door_unlocker.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:clean_stream_laundry_app/features/widgets/status_dialog_box.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StartPage extends StatefulWidget {
  final DoorUnlocker? doorUnlocker;
  // Keep the unfinished Kisi flow out of customer builds until it is integrated.
  final bool doorAccessEnabled;

  const StartPage({
    super.key,
    this.doorUnlocker,
    this.doorAccessEnabled = false,
  });

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  late final StartPageController _controller;
  bool _routeCurrent = false;

  @override
  void initState() {
    super.initState();
    _controller = StartPageController(doorUnlocker: widget.doorUnlocker);
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    if (widget.doorAccessEnabled && current && !_routeCurrent) {
      _controller.loadUserData();
    }
    _routeCurrent = current;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onUnlockPressed() async {
    if (!widget.doorAccessEnabled) return;
    if (!_controller.hasSufficientBalance) {
      _showLowBalanceDialog();
      return;
    }
    await _processUnlocking();
  }

  Future<void> _processUnlocking() async {
    showSearchingDialog(context, _controller.cancelUnlock);

    final success = await _controller.unlockDoor();

    if (!mounted) return;
    if (_controller.cancelSearch) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    statusDialog(
      context,
      title: success ? 'Door Unlocked!' : 'No Nearby Doors Found',
      message: success
          ? 'The nearest door has been unlocked successfully'
          : "We couldn't detect any nearby doors",
      isSuccess: success,
    );
  }

  void _showLowBalanceDialog() {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Low Balance'),
        content: Text(
          'You need at least ${minimumBalance.toStringAsFixed(2)} to unlock a door',
        ),
        icon: const Icon(Icons.error),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.go('/startPage');
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showTapToPayInstructions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _TapToPayInstructionsSheet(),
    );
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
                final horizontalPadding = constraints.maxWidth < 380
                    ? 16.0
                    : 20.0;
                final availableWidth = math.max(
                  0.0,
                  constraints.maxWidth - (horizontalPadding * 2),
                );
                final contentWidth = math.min(availableWidth, 520.0);
                final baseScale = (contentWidth / 340)
                    .clamp(0.94, 1.0)
                    .toDouble();
                final contentHeight = widget.doorAccessEnabled ? 610.0 : 390.0;
                final baseMetrics = _StartLayoutMetrics(scale: baseScale);
                final verticalPadding = baseMetrics.gap(4);
                final canvasHeight = math.max(
                  0.0,
                  constraints.maxHeight - (verticalPadding * 2),
                );
                final heightScale = canvasHeight <= 0
                    ? 1.0
                    : (canvasHeight / baseMetrics.size(contentHeight))
                          .clamp(1.0, 1.05)
                          .toDouble();
                final layoutScale = (baseScale * heightScale)
                    .clamp(0.94, 1.04)
                    .toDouble();
                final scaledMetrics = _StartLayoutMetrics(scale: layoutScale);
                final sectionGapBoost =
                    ((canvasHeight - scaledMetrics.size(contentHeight)) / 5.35)
                        .clamp(0.0, 14.0)
                        .toDouble();
                final metrics = _StartLayoutMetrics(
                  scale: layoutScale,
                  sectionGapBoost: sectionGapBoost,
                );
                final targetHeight = math.max(
                  canvasHeight,
                  metrics.size(contentHeight),
                );
                final media = MediaQuery.of(context);
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final cappedTextScale = math.min(textScale, 1.08).toDouble();

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    verticalPadding,
                    horizontalPadding,
                    verticalPadding,
                  ),
                  child: MediaQuery(
                    data: media.copyWith(
                      textScaler: TextScaler.linear(cappedTextScale),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: contentWidth,
                        height: canvasHeight,
                        child: FittedBox(
                          alignment: Alignment.topCenter,
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: contentWidth,
                            height: targetHeight,
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _StartHeader(metrics: metrics),
                                SizedBox(height: metrics.sectionGap(8)),
                                TapToPayCard(
                                  key: const ValueKey('tap-to-pay-card'),
                                  layoutScale: metrics.scale,
                                  onTap: _showTapToPayInstructions,
                                ),
                                SizedBox(height: metrics.sectionGap(8)),
                                _PrimaryScanCard(
                                  metrics: metrics,
                                  onPressed: () => context.go('/scanner'),
                                ),
                                SizedBox(height: metrics.sectionGap(10)),
                                _HowItWorksSection(metrics: metrics),
                                if (widget.doorAccessEnabled) ...[
                                  SizedBox(height: metrics.sectionGap(10)),
                                  _SectionHeading(
                                    metrics: metrics,
                                    icon: Icons.dark_mode_rounded,
                                    title: 'After Hours',
                                  ),
                                  SizedBox(
                                    height: metrics.compactSectionGap(6),
                                  ),
                                  _OutlinedActionCard(
                                    metrics: metrics,
                                    cardKey: const ValueKey('unlock-door-card'),
                                    icon: Icons.lock_outline_rounded,
                                    title: 'Unlock Door',
                                    description: 'Unlock the facility door.',
                                    onPressed: _onUnlockPressed,
                                  ),
                                  SizedBox(height: metrics.sectionGap(8)),
                                  _AfterHoursSteps(metrics: metrics),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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

class _StartLayoutMetrics {
  final double scale;
  final double sectionGapBoost;

  const _StartLayoutMetrics({required this.scale, this.sectionGapBoost = 0});

  double gap(double value) => value * scale;

  double sectionGap(double value) => gap(value) + sectionGapBoost;

  double compactSectionGap(double value) =>
      gap(value) + (sectionGapBoost * 0.35);

  double size(double value) => value * scale;

  double font(double value) =>
      (value * scale).clamp(value * 0.88, value * 1.03).toDouble();
}

class _StartHeader extends StatelessWidget {
  final _StartLayoutMetrics metrics;

  const _StartHeader({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Start Laundry',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontSize: metrics.font(27),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(width: metrics.gap(12)),
            _InfoPill(
              metrics: metrics,
              icon: Icons.contactless_rounded,
              label: 'NFC or QR',
            ),
          ],
        ),
        SizedBox(height: metrics.gap(5)),
        Text(
          'Choose a method and start your machine.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.92),
            height: 1.16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AfterHoursSteps extends StatelessWidget {
  final _StartLayoutMetrics metrics;

  const _AfterHoursSteps({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _AfterHoursStep(
            metrics: metrics,
            number: '1',
            icon: Icons.account_balance_wallet_outlined,
            label: r'Load $20 on loyalty card',
          ),
        ),
        _AfterHoursConnector(metrics: metrics),
        Expanded(
          child: _AfterHoursStep(
            metrics: metrics,
            number: '2',
            icon: Icons.lock_open_rounded,
            label: 'Tap Unlock button',
          ),
        ),
        _AfterHoursConnector(metrics: metrics),
        Expanded(
          child: _AfterHoursStep(
            metrics: metrics,
            number: '3',
            icon: Icons.contactless_rounded,
            label: 'Place phone on door lock',
          ),
        ),
      ],
    );
  }
}

class _AfterHoursStep extends StatelessWidget {
  final _StartLayoutMetrics metrics;
  final String number;
  final IconData icon;
  final String label;

  const _AfterHoursStep({
    required this.metrics,
    required this.number,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: metrics.size(42),
          height: metrics.size(37),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: metrics.size(32),
                  height: metrics.size(32),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.09),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: colors.primary,
                    size: metrics.size(18),
                  ),
                ),
              ),
              Positioned(
                left: metrics.size(5),
                top: 0,
                child: Container(
                  width: metrics.size(17),
                  height: metrics.size(17),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    number,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontSize: metrics.font(10),
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.gap(3)),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.fontSecondary,
            fontSize: metrics.font(11),
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
      ],
    );
  }
}

class _AfterHoursConnector extends StatelessWidget {
  final _StartLayoutMetrics metrics;

  const _AfterHoursConnector({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(top: metrics.gap(18)),
      child: SizedBox(
        width: metrics.size(28),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            3,
            (_) => Container(
              width: metrics.size(7),
              height: metrics.size(2),
              decoration: BoxDecoration(
                color: colors.outline.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final _StartLayoutMetrics metrics;
  final IconData icon;
  final String label;

  const _InfoPill({
    required this.metrics,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gap(9),
        vertical: metrics.gap(6),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: metrics.size(14), color: colors.primary),
          SizedBox(width: metrics.gap(5)),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryScanCard extends StatelessWidget {
  final _StartLayoutMetrics metrics;
  final VoidCallback onPressed;

  const _PrimaryScanCard({required this.metrics, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      enabled: true,
      child: Material(
        color: Colors.transparent,
        elevation: 10,
        shadowColor: colors.primary.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: metrics.size(120),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primary, const Color(0xFF007DCE)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        metrics.gap(14),
                        metrics.gap(12),
                        metrics.gap(12),
                        metrics.gap(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: metrics.size(54),
                            height: metrics.size(54),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              Icons.qr_code_scanner_rounded,
                              color: colors.primary,
                              size: metrics.size(32),
                            ),
                          ),
                          SizedBox(width: metrics.gap(14)),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Scan QR code',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontSize: metrics.font(23),
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                SizedBox(height: metrics.gap(4)),
                                Text(
                                  'Use your loyalty balance.',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.92,
                                        ),
                                        height: 1.12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: metrics.gap(6)),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.88),
                            size: metrics.size(30),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    height: metrics.size(30),
                    padding: EdgeInsets.symmetric(horizontal: metrics.gap(12)),
                    color: const Color(0xFF0065AA).withValues(alpha: 0.78),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          color: Colors.white,
                          size: metrics.size(15),
                        ),
                        SizedBox(width: metrics.gap(8)),
                        Flexible(
                          child: Text(
                            'Fast  •  Secure  •  No extra fees',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HowItWorksSection extends StatelessWidget {
  final _StartLayoutMetrics metrics;

  const _HowItWorksSection({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          metrics: metrics,
          icon: Icons.info_outline_rounded,
          title: 'How it works',
        ),
        SizedBox(height: metrics.gap(6)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _HowItWorksStep(
                metrics: metrics,
                number: '1',
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan',
                description: 'Scan QR Code.',
              ),
            ),
            _DashedConnector(metrics: metrics),
            Expanded(
              child: _HowItWorksStep(
                metrics: metrics,
                number: '2',
                icon: Icons.check_circle_outline_rounded,
                title: 'Confirm',
                description: 'Confirm details.',
              ),
            ),
            _DashedConnector(metrics: metrics),
            Expanded(
              child: _HowItWorksStep(
                metrics: metrics,
                number: '3',
                icon: Icons.play_arrow_rounded,
                title: 'Start',
                description: 'Start the cycle.',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final _StartLayoutMetrics metrics;
  final String number;
  final IconData icon;
  final String title;
  final String description;

  const _HowItWorksStep({
    required this.metrics,
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          width: metrics.size(46),
          height: metrics.size(42),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: metrics.size(36),
                  width: metrics.size(36),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.09),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: colors.primary,
                    size: metrics.size(21),
                  ),
                ),
              ),
              Positioned(
                left: metrics.size(4),
                top: 0,
                child: Container(
                  width: metrics.size(18),
                  height: metrics.size(18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    number,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.gap(3)),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.primary,
            fontSize: metrics.font(13),
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: metrics.gap(1)),
        Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.fontSecondary,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DashedConnector extends StatelessWidget {
  final _StartLayoutMetrics metrics;

  const _DashedConnector({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: metrics.gap(22)),
      child: SizedBox(
        width: metrics.size(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            3,
            (_) => Container(
              width: metrics.size(7),
              height: metrics.size(2),
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinedActionCard extends StatelessWidget {
  final _StartLayoutMetrics metrics;
  final Key? cardKey;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onPressed;

  const _OutlinedActionCard({
    required this.metrics,
    this.cardKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cardColor = colors.brightness == Brightness.dark
        ? const Color(0xFF262626)
        : Colors.white;

    return Semantics(
      button: true,
      enabled: true,
      child: Material(
        key: cardKey,
        color: cardColor,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            constraints: BoxConstraints(minHeight: metrics.size(84)),
            padding: EdgeInsets.symmetric(
              horizontal: metrics.gap(15),
              vertical: metrics.gap(10),
            ),
            decoration: BoxDecoration(
              border: Border.all(color: colors.primary.withValues(alpha: 0.28)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  height: metrics.size(48),
                  width: metrics.size(48),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    icon,
                    color: colors.primary,
                    size: metrics.size(28),
                  ),
                ),
                SizedBox(width: metrics.gap(14)),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colors.fontInverted,
                          fontSize: metrics.font(20),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: metrics.gap(3)),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.fontSecondary,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: metrics.gap(8)),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.primary,
                  size: metrics.size(26),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final _StartLayoutMetrics metrics;
  final IconData icon;
  final String title;

  const _SectionHeading({
    required this.metrics,
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: metrics.size(26),
          height: metrics.size(26),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colors.primary, size: metrics.size(16)),
        ),
        SizedBox(width: metrics.gap(9)),
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colors.fontInverted,
              fontSize: metrics.font(19),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        SizedBox(width: metrics.gap(10)),
        Expanded(
          child: Divider(
            color: colors.outline.withValues(alpha: 0.22),
            thickness: 1,
          ),
        ),
      ],
    );
  }
}

class _TapToPayInstructionsSheet extends StatelessWidget {
  const _TapToPayInstructionsSheet();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(Icons.tap_and_play, color: colors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Tap to pay at the machine',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.fontInverted,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Open your phone wallet, hold it near the machine NFC reader, then approve on your phone. This does not use your loyalty balance.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.fontSecondary,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            const _InstructionRow(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Open your wallet',
              description: 'Use Apple Pay, Google Wallet, or another NFC card.',
            ),
            const _InstructionRow(
              icon: Icons.contactless_rounded,
              title: 'Hold near the reader',
              description: 'Wait for the machine to confirm the payment.',
            ),
            const _InstructionRow(
              icon: Icons.local_laundry_service_rounded,
              title: 'Start the machine',
              description: 'Select the cycle and follow the display prompts.',
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _InstructionRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.fontInverted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.fontSecondary,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
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
