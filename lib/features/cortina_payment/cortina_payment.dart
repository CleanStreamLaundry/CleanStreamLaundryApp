import 'package:clean_stream_laundry_app/features/cortina_payment/controller.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/widgets/dryer_amount_selector.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/widgets/washer_cycle_notice.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CortinaPaymentPage extends StatefulWidget {
  final String? machineToken;
  final String? terminalId;
  final String? uniQr;

  const CortinaPaymentPage({
    super.key,
    required this.machineToken,
    required this.terminalId,
    required this.uniQr,
  });

  @override
  State<CortinaPaymentPage> createState() => _CortinaPaymentPageState();
}

class _CortinaPaymentPageState extends State<CortinaPaymentPage> {
  static const _brandYellow = Color(0xFFF3C404);
  static const _pageBackground = Color(0xFFF4F6F8);

  late final CortinaPaymentController controller;
  bool _useWallet = false;

  @override
  void initState() {
    super.initState();
    controller = CortinaPaymentController(
      machineToken: widget.machineToken,
      terminalId: widget.terminalId,
      uniQr: widget.uniQr,
    )..addListener(_refresh);
    controller.init();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  Future<void> _pay(bool wallet) async {
    final outcome = wallet
        ? await controller.payWithWallet()
        : await controller.payWithCard();
    if (!mounted) return;
    final (title, message, success) = switch (outcome) {
      CortinaPaymentOutcome.success => (
        'Machine Started',
        controller.isDryer
            ? '${controller.dryerMinutes} minutes were added.'
            : 'Select your cycle on the washer.',
        true,
      ),
      CortinaPaymentOutcome.pending => (
        'Payment Received',
        'The machine is still connecting. This screen will retain your transaction.',
        true,
      ),
      CortinaPaymentOutcome.refunded => (
        'Vend Canceled',
        'The machine did not start and your payment was returned.',
        false,
      ),
      CortinaPaymentOutcome.canceled => (
        'Payment Canceled',
        'No payment was completed.',
        false,
      ),
      CortinaPaymentOutcome.failed => (
        'Unable to Start',
        controller.errorMessage ?? 'Please contact Clean Stream support.',
        false,
      ),
    };
    await _showResultDialog(title: title, message: message, success: success);
  }

  void _selectWallet(bool useWallet) {
    if (controller.isProcessing) return;
    setState(() => _useWallet = useWallet);
  }

  Future<void> _showResultDialog({
    required String title,
    required String message,
    required bool success,
  }) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = success ? Colors.green.shade700 : Colors.red.shade700;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        key: const ValueKey('cortina-result-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _brandYellow, width: 3),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    success ? Icons.check_rounded : Icons.error_outline_rounded,
                    color: statusColor,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Machine payment',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => context.go('/homePage'),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.quote == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.qr_code_2, size: 52),
              const SizedBox(height: 16),
              Text(
                controller.errorMessage ?? 'This machine QR is unavailable.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: controller.init,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final quote = controller.quote!;
    final colors = Theme.of(context).colorScheme;
    final walletBalance = controller.walletBalance ?? 0;
    final walletAvailable = walletBalance >= controller.price;
    final useWallet = _useWallet && walletAvailable;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MachineSummary(
                      machineName: quote.machineName,
                      amount: controller.price,
                      detail: quote.isDryer
                          ? '${controller.dryerMinutes} minute dry'
                          : '${quote.washerSizeLabel ?? 'Washer'} flat rate',
                    ),
                    const SizedBox(height: 12),
                    if (quote.isDryer)
                      DryerAmountSelector(
                        amountCents: controller.amountCents,
                        options: quote.dryerOptions,
                        onChanged: controller.setDryerAmount,
                      )
                    else
                      WasherCycleNotice(sizeLabel: quote.washerSizeLabel),
                    const SizedBox(height: 20),
                    const Text(
                      'Payment method',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PaymentMethodTile(
                      icon: Icons.credit_card_rounded,
                      title: 'Credit or debit card',
                      subtitle: 'Secure payment with Stripe',
                      selected: !useWallet,
                      onTap: () => _selectWallet(false),
                    ),
                    if (controller.isSignedIn) ...[
                      const SizedBox(height: 8),
                      _PaymentMethodTile(
                        icon: Icons.account_balance_wallet_rounded,
                        title: 'Loyalty wallet',
                        subtitle:
                            '\$${walletBalance.toStringAsFixed(2)} available',
                        selected: useWallet,
                        enabled: walletAvailable,
                        onTap: () => _selectWallet(true),
                      ),
                    ],
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: colors.onErrorContainer,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                controller.errorMessage!,
                                style: TextStyle(
                                  color: colors.onErrorContainer,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Center(
                      child: Image.asset(
                        'assets/Logo.png',
                        height: 76,
                        semanticLabel: 'Clean Stream Laundry Solutions',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _CheckoutBar(
          amount: controller.price,
          isProcessing: controller.isProcessing,
          paymentLabel: useWallet ? 'Loyalty wallet' : 'Card',
          onPay: controller.isProcessing ? null : () => _pay(useWallet),
        ),
      ],
    );
  }
}

class _MachineSummary extends StatelessWidget {
  final String machineName;
  final double amount;
  final String detail;

  const _MachineSummary({
    required this.machineName,
    required this.amount,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF165F8C),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          top: BorderSide(
            color: _CortinaPaymentPageState._brandYellow,
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_laundry_service_rounded,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  machineName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(color: Color(0xFFDCEAF2))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(
                  color: Color(0xFFDCEAF2),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '\$${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = selected ? colors.primary : const Color(0xFFD6DCE1);
    return Material(
      color: enabled ? Colors.white : const Color(0xFFE9EDF0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor, width: selected ? 2 : 1),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: enabled ? colors.primary : Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? colors.primary : const Color(0xFF9AA5AD),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  final double amount;
  final bool isProcessing;
  final String paymentLabel;
  final VoidCallback? onPay;

  const _CheckoutBar({
    required this.amount,
    required this.isProcessing,
    required this.paymentLabel,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paymentLabel,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '\$${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 176,
                height: 48,
                child: FilledButton.icon(
                  onPressed: onPay,
                  icon: isProcessing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_rounded, size: 18),
                  label: Text(
                    isProcessing
                        ? 'Starting...'
                        : 'Pay \$${amount.toStringAsFixed(2)}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
