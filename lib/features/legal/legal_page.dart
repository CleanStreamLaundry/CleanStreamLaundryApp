import 'package:clean_stream_laundry_app/features/legal/legal_drafts.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

enum LegalPageType { privacy, terms, loyaltyCard }

Future<void> showLoyaltyPolicy(
  BuildContext context,
  LoyaltyPolicyDescriptor descriptor,
) => Navigator.of(context).push<void>(MaterialPageRoute(
  builder: (_) => Scaffold(
    appBar: AppBar(title: const Text('Loyalty terms')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: LoyaltyPolicyText(descriptor: descriptor),
      ),
    ),
  ),
));

class LegalPage extends StatelessWidget {
  final LegalPageType type;
  final ProfileService? profileService;

  const LegalPage({super.key, required this.type, this.profileService});

  String get title => switch (type) {
    LegalPageType.privacy => 'Privacy Policy',
    LegalPageType.terms => 'Terms of Service',
    LegalPageType.loyaltyCard => 'Loyalty Card Terms',
  };

  Map<String, dynamic> get draft =>
      legalDrafts[type == LegalPageType.privacy ? 'privacy' : 'terms']
          as Map<String, dynamic>;

  List<LoyaltyPolicySection> get draftSections => [
    for (final section in draft['sections'] as List)
      LoyaltyPolicySection(
        heading: section['heading'] as String,
        paragraphs: List<String>.from(section['paragraphs'] as List),
      ),
  ];

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
                if (type == LegalPageType.loyaltyCard)
                  _LoyaltyPolicyDocument(service: profileService)
                else
                  LoyaltyPolicyText.draft(
                    title: draft['title'] as String,
                    sections: draftSections,
                    metadata: legalDrafts['metadata'] as String,
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => _openPublicPolicy(context),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(
                    type == LegalPageType.loyaltyCard
                        ? 'Public website terms'
                        : 'Open public website',
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
  final LoyaltyPolicyDescriptor? descriptor;
  final String? _draftTitle;
  final List<LoyaltyPolicySection>? _draftSections;
  final String? _draftMetadata;

  const LoyaltyPolicyText({super.key, required LoyaltyPolicyDescriptor descriptor})
    : descriptor = descriptor,
      _draftTitle = null,
      _draftSections = null,
      _draftMetadata = null;

  const LoyaltyPolicyText.draft({
    super.key,
    required String title,
    required List<LoyaltyPolicySection> sections,
    required String metadata,
  }) : descriptor = null,
       _draftTitle = title,
       _draftSections = sections,
       _draftMetadata = metadata;

  @override
  Widget build(BuildContext context) {
    final document = descriptor;
    final colors = Theme.of(context).colorScheme;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: colors.onSurface.withValues(alpha: 0.78),
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.6,
      letterSpacing: 0,
    );
    final metadataStyle = bodyStyle.copyWith(
      color: colors.onSurface.withValues(alpha: 0.62),
      fontSize: 12,
      height: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Image.asset(
            'assets/splash-logo.png',
            width: 180,
            height: 150,
            fit: BoxFit.contain,
            semanticLabel: 'Clean Stream Laundry Solutions',
          ),
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: SelectableText(
            document?.title ?? _draftTitle!,
            style: bodyStyle.copyWith(
              color: colors.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            if (_draftMetadata != null)
              SelectableText(_draftMetadata!, style: metadataStyle),
            if (document?.effectiveDate != null)
              SelectableText(
                'Effective ${DateFormat.yMMMMd().format(DateTime.parse(document!.effectiveDate!))}',
                style: metadataStyle,
              ),
            if (document != null)
              SelectableText(
                'Version: ${document.requiredVersion}',
                style: metadataStyle,
              ),
          ],
        ),
        Divider(
          height: 40,
          thickness: 1,
          color: colors.onSurface.withValues(alpha: 0.12),
        ),
        for (final (index, section)
            in (document?.sections ?? _draftSections!).indexed) ...[
          if (index > 0) const SizedBox(height: 28),
          if (section.heading.isNotEmpty) ...[
            Semantics(
              header: true,
              child: SelectableText(
                section.heading,
                style: bodyStyle.copyWith(
                  color: colors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          for (final (paragraphIndex, paragraph)
              in section.paragraphs.indexed) ...[
            if (paragraphIndex > 0) const SizedBox(height: 12),
            SelectableText(paragraph, style: bodyStyle),
          ],
        ],
      ],
    );
  }
}
