import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'controller.dart';

class TopupRefundsPage extends StatefulWidget {
  const TopupRefundsPage({super.key, this.active = true, this.onBack});

  final bool active;
  final VoidCallback? onBack;

  @override
  State<TopupRefundsPage> createState() => _TopupRefundsPageState();
}

class _TopupRefundsPageState extends State<TopupRefundsPage>
    with WidgetsBindingObserver {
  late final TopupRefundsController _controller;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _controller = TopupRefundsController();
    _controller.setActive(widget.active);
    WidgetsBinding.instance.addObserver(this);
    _controller.initialize();
  }

  @override
  void didUpdateWidget(covariant TopupRefundsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      // An open dialog is a sibling route, so notify after this build finishes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.setActive(widget.active);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  String _money(int cents) =>
      NumberFormat.currency(name: 'USD', symbol: '\$').format(cents / 100);
  String _date(DateTime date) =>
      '${DateFormat('MMM d, yyyy, h:mm a').format(date.toLocal())} (local time)';

  static const _headingStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
  static const _amountStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  ButtonStyle _actionStyle(BuildContext context, {bool filled = false}) {
    final colors = Theme.of(context).colorScheme;
    return TextButton.styleFrom(
      foregroundColor: filled
          ? Colors.white
          : colors.brightness == Brightness.dark
          ? Colors.white
          : colors.primary,
      backgroundColor: filled ? colors.primary : null,
      disabledBackgroundColor: filled
          ? colors.onSurface.withValues(alpha: .12)
          : null,
      disabledForegroundColor: colors.onSurface.withValues(alpha: .38),
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _body(Widget child) => DefaultTextStyle.merge(
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 14,
      height: 1.45,
      letterSpacing: 0,
    ),
    child: child,
  );

  Future<void> _confirm(RefundableTopup topup) async {
    final epoch = _controller.generation;
    if (!widget.active ||
        _confirming ||
        !_controller.canRequest(topup, epoch)) {
      return;
    }
    _confirming = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => AlertDialog(
            scrollable: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            titlePadding: EdgeInsets.zero,
            contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            actionsOverflowButtonSpacing: 8,
            title: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.secondary,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/Icon.png',
                    width: 40,
                    height: 40,
                    cacheWidth: (40 * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Request full top-up refund?',
                      style: _headingStyle.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            content: _body(
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_money(topup.principalCents)} USD',
                    style: _amountStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_money(topup.principalCents)} USD to your original payment method. No processing fee is deducted.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Reserved credits',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'The full paid amount and required promotional credit will be reserved immediately and unavailable to spend. Attributable bonuses and reward progress will be unwound; bonus credit has no cash value.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Eligibility',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The server must receive your request within 48 hours of successful payment, by ${_date(topup.requestDeadline!)}. Any wallet spending after this top-up disqualifies it, including promotional spending and later-reversed payments.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Owner review',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Owner review is required and may happen later. A request is not a paid refund. Pending or unknown refunds remain reserved until resolved.',
                  ),
                  if (epoch != _controller.generation ||
                      !_controller.hasSession)
                    const Text(
                      'Your session changed. Close this confirmation and refresh.',
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                style: _actionStyle(context),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: _actionStyle(context, filled: true),
                onPressed: widget.active && _controller.canRequest(topup, epoch)
                    ? () {
                        if (widget.active &&
                            _controller.canRequest(topup, epoch)) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      }
                    : null,
                child: const Text('Confirm request'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || !widget.active || confirmed != true) return;
      await _controller.request(topup, expectedGeneration: epoch);
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).colorScheme.primaryGradient,
          ),
        ),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 28
            ? 96
            : 56,
        titleTextStyle: _headingStyle.copyWith(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(
            height: 3,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        leading: widget.onBack == null
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
        title: const Text('Top-up refunds', maxLines: 2),
        actions: [
          IconButton(
            tooltip: 'Refresh refunds',
            icon: const Icon(Icons.refresh),
            onPressed:
                _controller.writing ||
                    _controller.loadingTopups ||
                    _controller.loadingRefunds
                ? null
                : _controller.refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _controller.refresh,
        child: _body(
          ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const Text('Unused top-ups', style: _headingStyle),
              const SizedBox(height: 8),
              const Text(
                'Request within 48 hours of successful payment. No wallet spending is allowed after the top-up, even bonus-only spending or a payment later reversed. The server checks eligibility when it receives your request.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Full paid amount to the original payment method, subject to Owner review. Machine-issue claims and legally required remedies are separate.',
              ),
              if (_controller.message != null) _notice(_controller.message!),
              if (_controller.writing)
                const LinearProgressIndicator(
                  semanticsLabel: 'Recording and checking refund request',
                ),
              if (_controller.topupsError != null)
                _notice(_controller.topupsError!),
              if (_controller.loadingTopups)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading top-ups',
                ),
              if (_controller.topupsLoaded && _controller.topups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No top-ups found.'),
                ),
              for (final topup in _controller.topups) _topup(topup),
              if (_controller.moreTopups)
                TextButton.icon(
                  style: _actionStyle(context),
                  onPressed: _controller.loadingTopups || _controller.writing
                      ? null
                      : _controller.loadMoreTopups,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('More top-ups'),
                ),
              const Divider(height: 32),
              const Text('Your requests', style: _headingStyle),
              if (_controller.refundsError != null)
                _notice(_controller.refundsError!),
              if (_controller.loadingRefunds)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading refund requests',
                ),
              if (_controller.refundsLoaded && _controller.refunds.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No refund requests found.'),
                ),
              for (final refund in _controller.refunds) _refund(refund),
              if (_controller.moreRefunds)
                TextButton.icon(
                  style: _actionStyle(context),
                  onPressed: _controller.loadingRefunds || _controller.writing
                      ? null
                      : _controller.loadMoreRefunds,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('More requests'),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _notice(String text) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text),
    ),
  );

  Widget _topup(RefundableTopup topup) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .16),
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_money(topup.principalCents)} USD', style: _amountStyle),
        const SizedBox(height: 4),
        Text('Top-up #${topup.loadId}'),
        const SizedBox(height: 8),
        if (topup.paymentSucceededAt != null)
          Text('Paid ${_date(topup.paymentSucceededAt!)}'),
        if (topup.requestDeadline != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Server request deadline: ${_date(topup.requestDeadline!)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          _controller.isUncertain(topup.loadId)
              ? 'Request unconfirmed. Refresh or contact support; do not submit again.'
              : _reason(topup),
        ),
        if (topup.refund != null) Text(_status(topup.refund!.status)),
        if (topup.isAdvisoryEligible)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              style: _actionStyle(context),
              onPressed: _controller.canRequest(topup, _controller.generation)
                  ? () => _confirm(topup)
                  : null,
              icon: const Icon(Icons.undo),
              label: const Text('Request full refund'),
            ),
          ),
      ],
    ),
  );

  String _reason(RefundableTopup topup) => switch (topup.ineligibleReason) {
    null => 'May be eligible. Final eligibility is checked by the server.',
    TopupRefundIneligibleReason.alreadyRequested =>
      'A refund request already exists.',
    TopupRefundIneligibleReason.provenanceUnavailable =>
      'Verified payment evidence is unavailable for this top-up.',
    TopupRefundIneligibleReason.refundWindowClosed =>
      'Outside the 48-hour request window.',
    TopupRefundIneligibleReason.walletUsedAfterTopup =>
      'Wallet spending occurred after this top-up.',
    TopupRefundIneligibleReason.rewardProvenanceUnavailable =>
      'Reward history needs review. Contact support.',
    TopupRefundIneligibleReason.refundFundsUnavailable =>
      'Insufficient available funds for the refund and bonus unwind.',
  };

  Widget _refund(TopupRefund refund) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .16),
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_money(refund.principalCents)} USD', style: _amountStyle),
        const SizedBox(height: 4),
        Text(
          _status(refund.status),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('Top-up #${refund.loadId}'),
        Text('Requested ${_date(refund.requestedAt)}'),
        const SizedBox(height: 8),
        Text(_detail(refund.status)),
        const SizedBox(height: 8),
        Text(
          'Promotional credit reserved at request: ${_money(refund.bonusReservedCents)}. Reward progress is recalculated.',
        ),
        if (refund.completedAt != null)
          Text('Processor confirmation: ${_date(refund.completedAt!)}'),
        if (refund.reviewNote != null && refund.reviewNote!.isNotEmpty)
          Text('Review note: ${refund.reviewNote}'),
      ],
    ),
  );

  String _status(TopupRefundStatus status) => switch (status) {
    TopupRefundStatus.requested => 'Awaiting Owner review',
    TopupRefundStatus.approved => 'Approved - not yet confirmed',
    TopupRefundStatus.unknown => 'Outcome unknown',
    TopupRefundStatus.pending => 'Refund pending',
    TopupRefundStatus.succeeded => 'Refund confirmed by processor',
    TopupRefundStatus.failed => 'Refund failed',
    TopupRefundStatus.canceled => 'Refund canceled',
    TopupRefundStatus.denied => 'Request denied',
  };

  String _detail(TopupRefundStatus status) => switch (status) {
    TopupRefundStatus.requested =>
      'Request received, not repaid. Funds remain reserved during Owner review.',
    TopupRefundStatus.approved =>
      'Approved for processing, not repaid. Funds remain reserved.',
    TopupRefundStatus.unknown =>
      'Repayment is not confirmed. Funds remain reserved while the Owner reconciles the outcome. Contact support.',
    TopupRefundStatus.pending =>
      'The processor has not confirmed completion. Funds remain reserved.',
    TopupRefundStatus.succeeded =>
      'Full paid amount refunded to the original payment method. Bank posting may take additional time.',
    TopupRefundStatus.failed ||
    TopupRefundStatus.canceled ||
    TopupRefundStatus.denied =>
      'No completed refund. The reservation has been released and reward progress recalculated.',
  };
}
