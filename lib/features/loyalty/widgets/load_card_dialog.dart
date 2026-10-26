import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/legal/legal_page.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_action_context.dart';
import 'package:flutter/material.dart';

class LoadCardDialog extends StatefulWidget {
  final Future<void> Function(double amount, Map<String, dynamic> consent) onPay;
  final Future<LoyaltyActionContext> Function() loadConsent;

  const LoadCardDialog({super.key, required this.onPay, required this.loadConsent});

  @override
  State<LoadCardDialog> createState() => _LoadCardDialogState();
}

class _LoadCardDialogState extends State<LoadCardDialog> {
  final _amountController = TextEditingController(text: '1.00');
  LoyaltyActionContext? _consent;
  bool _acknowledged = false;
  bool _loadingConsent = true;
  String? _consentError;

  @override
  void initState() {
    super.initState();
    _loadConsent();
  }

  Future<void> _loadConsent() async {
    setState(() {
      _loadingConsent = true;
      _consent = null;
      _acknowledged = false;
      _consentError = null;
    });
    try {
      final result = await widget.loadConsent();
      if (result.action != 'wallet_load') throw StateError('Unexpected consent');
      if (mounted) setState(() => _consent = result);
    } catch (_) {
      if (mounted) setState(() => _consentError = 'Unable to load purchase terms.');
    } finally {
      if (mounted) setState(() => _loadingConsent = false);
    }
  }

  double? get _selectedAmount {
    final text = _amountController.text.trim();
    if (!RegExp(r'^\d+(?:\.\d{0,2})?$').hasMatch(text)) return null;
    final amount = double.tryParse(text);
    return amount != null && amount >= 1 && amount <= 500 ? amount : null;
  }

  void _setAmount(int cents) {
    final text = (cents / 100).toStringAsFixed(2);
    setState(() {
      _acknowledged = false;
      _amountController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final brandForeground = colors.brightness == Brightness.dark
        ? Colors.white
        : colors.primary;
    final controlSurface = Color.alphaBlend(
      colors.primary.withValues(alpha: .08),
      colors.surface,
    );
    final selectedAmount = _selectedAmount;
    const termsLabel = 'Loyalty Program Terms';
    final acknowledgement = _consent?.acknowledgement ?? '';
    final termsIndex = acknowledgement.indexOf(termsLabel);
    final cents = selectedAmount == null
        ? null
        : (selectedAmount * 100).round();
    final enlargedText = MediaQuery.textScalerOf(context).scale(14) > 18;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: brandForeground.withValues(alpha: .4)),
    );
    final stepStyle = IconButton.styleFrom(
      foregroundColor: brandForeground,
      backgroundColor: controlSurface,
      disabledForegroundColor: colors.fontInverted.withValues(alpha: .3),
      minimumSize: const Size(48, 48),
      side: BorderSide(color: brandForeground.withValues(alpha: .25)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    final decrease = IconButton(
      tooltip: 'Decrease by 25 cents',
      style: stepStyle,
      onPressed: cents != null && cents > 100
          ? () => _setAmount((cents - 25).clamp(100, 50000))
          : null,
      icon: const Icon(Icons.remove),
    );
    final increase = IconButton(
      tooltip: 'Increase by 25 cents',
      style: stepStyle,
      onPressed: cents != null && cents < 50000
          ? () => _setAmount((cents + 25).clamp(100, 50000))
          : null,
      icon: const Icon(Icons.add),
    );
    final field = Semantics(
      label: 'Amount',
      child: TextField(
        controller: _amountController,
        onTap: () => _amountController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _amountController.text.length,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: brandForeground,
        ),
        onChanged: (_) => setState(() => _acknowledged = false),
        decoration: InputDecoration(
          prefixText: '\$ ',
          prefixStyle: TextStyle(fontSize: 24, color: brandForeground),
          filled: true,
          fillColor: controlSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: colors.primary, width: 2),
          ),
          errorMaxLines: 3,
          errorStyle: const TextStyle(fontSize: 12),
          errorText: selectedAmount == null
              ? 'Use \$1 to \$500, up to 2 decimals.'
              : null,
        ),
      ),
    );

    return AlertDialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: colors.primary,
          border: Border(bottom: BorderSide(color: colors.secondary, width: 3)),
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/Icon.png',
              width: 40,
              height: 40,
              fit: BoxFit.contain,
              cacheWidth: (40 * MediaQuery.devicePixelRatioOf(context)).ceil(),
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Load Loyalty Card',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Amount',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.fontInverted,
                ),
              ),
              const SizedBox(height: 8),
              if (enlargedText) ...[
                field,
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [decrease, const SizedBox(width: 24), increase],
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: decrease,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: field),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: increase,
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                '\$1.00 - \$500.00',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.fontSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final amount in [10, 15, 25, 50]) ...[
                    if (amount != 10) const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ChoiceChip(
                          showCheckmark: false,
                          label: SizedBox(
                            width: double.infinity,
                            child: Text(
                              '\$$amount',
                              textAlign: TextAlign.center,
                              softWrap: false,
                            ),
                          ),
                          labelPadding: EdgeInsets.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          labelStyle: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: selectedAmount == amount
                                ? Colors.black
                                : brandForeground,
                          ),
                          backgroundColor: controlSurface,
                          selectedColor: colors.secondary,
                          side: BorderSide(
                            color: selectedAmount == amount
                                ? colors.secondary
                                : brandForeground.withValues(alpha: .4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          selected: selectedAmount == amount,
                          onSelected: (_) => _setAmount(amount * 100),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Divider(
                height: 1,
                color: colors.fontInverted.withValues(alpha: .15),
              ),
              const SizedBox(height: 12),
              if (_loadingConsent)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Loading purchase terms...'),
                ),
              if (_consentError != null) ...[
                Text(_consentError!, style: TextStyle(color: colors.error)),
                TextButton.icon(
                  onPressed: _loadingConsent ? null : _loadConsent,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
              if (_consent != null)
                Row(
                  children: [
                    Checkbox(
                      value: _acknowledged,
                      semanticLabel: acknowledgement,
                      onChanged: selectedAmount == null ? null :
                        (value) => setState(() => _acknowledged = value ?? false),
                    ),
                    Expanded(
                      child: TextButton(
                        key: const Key('purchaseTermsLink'),
                        onPressed: () => showLoyaltyPolicy(context, _consent!.policy),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        ),
                        child: Semantics(
                          label: 'Read Loyalty Program Terms',
                          excludeSemantics: true,
                          child: Text.rich(
                            TextSpan(
                              children: termsIndex < 0
                                  ? [TextSpan(text: acknowledgement)]
                                  : [
                                      TextSpan(text: acknowledgement.substring(0, termsIndex)),
                                      TextSpan(
                                        text: termsLabel,
                                        style: TextStyle(
                                          color: brandForeground,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextSpan(text: acknowledgement.substring(termsIndex + termsLabel.length)),
                                    ],
                            ),
                            style: TextStyle(fontSize: 13, height: 1.5, color: colors.fontInverted),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: colors.fontInverted,
                  minimumSize: const Size(48, 48),
                  textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: selectedAmount == null || !_acknowledged || _consent == null
                    ? null
                    : () async {
                        final amount = _selectedAmount;
                        if (amount == null) return;
                        Navigator.of(context).pop();
                        await widget.onPay(amount, _consent!.acknowledge());
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: textTheme.labelLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Load'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
