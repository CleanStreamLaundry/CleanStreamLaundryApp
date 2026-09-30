import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';

enum LegalPageType { privacy, terms, loyaltyCard }

class LegalPage extends StatelessWidget {
  final LegalPageType type;
  final ProfileService? profileService;

  const LegalPage({super.key, required this.type, this.profileService});

  String get title => switch (type) {
    LegalPageType.privacy => 'Privacy Policy',
    LegalPageType.terms => 'Terms of Service',
    LegalPageType.loyaltyCard => 'Loyalty Card Terms',
  };

  List<String> get paragraphs => switch (type) {
    LegalPageType.privacy => const [
      'Clean Stream collects the account, contact, payment reference, machine usage, refund, maintenance, location, and support information needed to provide laundry services and operate the app.',
      'Clean Stream does not sell personal information or store complete payment-card numbers. Card payments are processed by Stripe, machine vending is provided through Nayax, and application data is hosted through Supabase.',
      'When an account is deleted, app access and profile information are removed or anonymized. Limited transaction, wallet, dispute, fraud-prevention, tax, accounting, and compliance records may be retained as described in the current public policy.',
    ],
    LegalPageType.terms => const [
      'Use of Clean Stream Laundry services is subject to account eligibility, payment authorization, machine availability, and posted service rules.',
      'If a paid machine vend is rejected, voided, or times out, Clean Stream will initiate the applicable card refund or wallet reversal. Laundry refunds may be reviewed by support using the related payment and machine records.',
      'The current public Terms of Service govern use of the website, app, payments, wallet, and connected laundry services.',
    ],
    LegalPageType.loyaltyCard => const [],
  };

  Uri get publicUrl => Uri.parse(switch (type) {
    LegalPageType.privacy => 'https://cleanstreamlaundry.com/privacy',
    LegalPageType.terms => 'https://cleanstreamlaundry.com/terms',
    LegalPageType.loyaltyCard => 'https://cleanstreamlaundry.com/terms',
  });

  Future<void> _openPublicPolicy(BuildContext context) async {
    if (!await launchUrl(publicUrl, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the public policy.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.fontSecondary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                if (type == LegalPageType.loyaltyCard)
                  _LoyaltyPolicyDocument(service: profileService),
                for (final paragraph in paragraphs) ...[
                  Text(
                    paragraph,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.fontSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 4),
                FilledButton.icon(
                  style: FilledButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => _openPublicPolicy(context),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(
                    type == LegalPageType.loyaltyCard
                        ? 'Public website terms'
                        : 'View current policy',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoyaltyPolicyDocument extends StatefulWidget {
  final ProfileService? service;

  const _LoyaltyPolicyDocument({this.service});

  @override
  State<_LoyaltyPolicyDocument> createState() => _LoyaltyPolicyDocumentState();
}

class _LoyaltyPolicyDocumentState extends State<_LoyaltyPolicyDocument> {
  LoyaltyPolicyDescriptor? _descriptor;
  bool _loading = true;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_LoyaltyPolicyDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final descriptor = await (widget.service ?? GetIt.I<ProfileService>())
          .getLoyaltyPolicyDescriptor();
      if (!mounted || request != _request) return;
      setState(() => _descriptor = descriptor);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final descriptor = _descriptor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Review-only draft'),
        if (_loading)
          const LinearProgressIndicator(semanticsLabel: 'Loading policy'),
        if (descriptor != null) LoyaltyPolicyText(descriptor: descriptor),
        if (_failed) const Text('Unable to load the policy.'),
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: _failed ? 'Retry policy' : 'Refresh policy',
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class LoyaltyPolicyText extends StatelessWidget {
  final LoyaltyPolicyDescriptor descriptor;

  const LoyaltyPolicyText({super.key, required this.descriptor});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 14),
      SelectableText(
        descriptor.policyText,
        style: TextStyle(
          color: Theme.of(context).colorScheme.fontSecondary,
          fontSize: 15,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 14),
      SelectableText('Version: ${descriptor.requiredVersion}'),
      SelectableText('SHA-256: ${descriptor.policySha256}'),
    ],
  );
}
