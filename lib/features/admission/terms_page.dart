import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/features/legal/legal_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoyaltyTermsPage extends StatelessWidget {
  final AdmissionController controller;
  final VoidCallback? onBackToLogin;
  final VoidCallback onCheckAccess;

  const LoyaltyTermsPage({
    super.key,
    required this.controller,
    required this.onCheckAccess,
    this.onBackToLogin,
  });

  @override
  Widget build(BuildContext context) {
    final descriptor = controller.policyDescriptor;
    final error = controller.policyError;
    final accessConfirmed = controller.error == null;
    final busy = controller.isChecking || controller.isLoadingPolicy;
    final colors = Theme.of(context).colorScheme;
    final bodyStyle = TextStyle(
      color: colors.onSurface,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
      letterSpacing: 0,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty terms'),
        titleTextStyle: bodyStyle.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        titleSpacing: 4,
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: colors.onSurface.withValues(alpha: 0.12),
          ),
        ),
        automaticallyImplyLeading: false,
        leading: onBackToLogin == null
            ? null
            : IconButton(
                tooltip: 'Back to login',
                onPressed: onBackToLogin,
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      body: SafeArea(
        bottom: false,
        child: Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            primary: true,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: DefaultTextStyle(
                  style: bodyStyle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (busy ||
                          (descriptor == null &&
                              error == null &&
                              accessConfirmed))
                        LinearProgressIndicator(
                          semanticsLabel: controller.isAcceptingPolicy
                              ? 'Waiting for acceptance'
                              : 'Loading loyalty terms',
                        ),
                      if (descriptor != null)
                        LoyaltyPolicyText(descriptor: descriptor),
                      if (!accessConfirmed) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Unable to confirm account access. Please try again.',
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          error is PostgrestException && error.code == '22023'
                              ? 'The policy changed. Load the current terms and review them again.'
                              : 'Unable to confirm the policy. Reload its status before accepting.',
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: 'Load current terms',
                            onPressed:
                                accessConfirmed && controller.canReviewPolicy
                                ? controller.loadPolicy
                                : null,
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                      ],
                      if (controller.error != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: 'Check account access',
                            onPressed: busy ? null : onCheckAccess,
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: descriptor == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: colors.onSurface.withValues(alpha: 0.12),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: accessConfirmed && controller.policyConsent,
                          onChanged:
                              accessConfirmed && controller.canConsentToPolicy
                              ? (value) =>
                                    controller.setPolicyConsent(value ?? false)
                              : null,
                          title: Text(
                            'I have read and agree to the loyalty card terms.',
                            style: bodyStyle,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: bodyStyle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed:
                              accessConfirmed && controller.canAcceptPolicy
                              ? controller.acceptPolicy
                              : null,
                          icon: const Icon(Icons.check),
                          label: const Text(
                            'Agree and continue',
                            textAlign: TextAlign.center,
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
