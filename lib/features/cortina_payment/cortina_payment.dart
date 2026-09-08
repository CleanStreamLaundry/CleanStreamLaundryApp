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
  late final CortinaPaymentController controller;

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
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          success ? Icons.check_circle : Icons.error_outline,
          color: success ? Colors.green : Colors.red,
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clean Stream Laundry'),
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
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.local_laundry_service,
                  size: 58,
                  color: Color(0xFF2073A9),
                ),
                const SizedBox(height: 8),
                Text(
                  quote.machineName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${controller.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                if (quote.isDryer)
                  DryerAmountSelector(
                    amountCents: controller.amountCents,
                    options: quote.dryerOptions,
                    onChanged: controller.setDryerAmount,
                  )
                else
                  WasherCycleNotice(sizeLabel: quote.washerSizeLabel),
                if (controller.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    controller.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: controller.isProcessing ? null : () => _pay(false),
                  icon: controller.isProcessing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.credit_card),
                  label: Text('Pay \$${controller.price.toStringAsFixed(2)}'),
                ),
              ),
              if (controller.isSignedIn) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed:
                        controller.isProcessing ||
                            (controller.walletBalance ?? 0) < controller.price
                        ? null
                        : () => _pay(true),
                    icon: const Icon(Icons.account_balance_wallet),
                    label: Text(
                      'Use Loyalty Wallet - \$${(controller.walletBalance ?? 0).toStringAsFixed(2)}',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
