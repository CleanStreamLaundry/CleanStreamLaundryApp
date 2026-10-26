import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/newsletter/controller.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

class NewsletterPage extends StatefulWidget {
  const NewsletterPage({super.key, this.authService, this.profileService});

  final AuthService? authService;
  final ProfileService? profileService;

  @override
  State<NewsletterPage> createState() => _NewsletterPageState();
}

class _NewsletterPageState extends State<NewsletterPage> {
  late final NewsletterController controller;

  @override
  void initState() {
    super.initState();
    controller = NewsletterController(
      authService: widget.authService ?? GetIt.I<AuthService>(),
      profileService: widget.profileService ?? GetIt.I<ProfileService>(),
    );
    controller.refresh();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BasePage(
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final status = controller.status;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  height: 1.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF8DCDF4)
                          : Theme.of(context).colorScheme.primary,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Newsletter preferences',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (controller.busy)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Updating newsletter preferences',
                      ),
                    if (status != null) ...[
                      Text(switch (status.state) {
                        NewsletterState.notSubscribed => 'Not subscribed.',
                        NewsletterState.pending =>
                          'Confirmation pending. Your request is recorded, but you are not subscribed until you confirm using the email link. Email delivery is unknown.',
                        NewsletterState.expired =>
                          'Confirmation expired. You are not subscribed. A new request requires your consent again.',
                        NewsletterState.subscribed =>
                          'Subscribed. Email delivery is not tracked here.',
                        NewsletterState.unsubscribed => 'Unsubscribed.',
                        NewsletterState.suppressed =>
                          'Newsletter email is suppressed. Re-enrollment is unavailable.',
                      }),
                      if (!status.enabled) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Newsletter enrollment is currently disabled. Your recorded preference is shown above.',
                        ),
                      ],
                      const Divider(height: 32),
                      SelectableText(status.consentText),
                      const SizedBox(height: 8),
                      Text(
                        'Consent version: ${status.consentVersion}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.fontSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (const [
                        NewsletterState.notSubscribed,
                        NewsletterState.expired,
                        NewsletterState.unsubscribed,
                      ].contains(status.state)) ...[
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: controller.consent,
                          onChanged: controller.canRequest
                              ? (value) => controller.setConsent(value == true)
                              : null,
                          title: const Text(
                            'I agree to the newsletter consent above (optional).',
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: controller.canRequest && controller.consent
                              ? controller.request
                              : null,
                          icon: const Icon(Icons.mail_outline),
                          label: const Text('Request subscription'),
                        ),
                      ],
                      if (const [
                        NewsletterState.pending,
                        NewsletterState.subscribed,
                      ].contains(status.state))
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                            minimumSize: const Size(48, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: controller.canWithdraw
                              ? controller.withdraw
                              : null,
                          icon: const Icon(Icons.unsubscribe_outlined),
                          label: Text(
                            status.state == NewsletterState.pending
                                ? 'Withdraw request'
                                : 'Unsubscribe',
                          ),
                        ),
                    ],
                    if (controller.message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        controller.message!,
                        semanticsLabel: controller.message,
                      ),
                    ],
                    IconButton(
                      onPressed: controller.busy ? null : controller.refresh,
                      tooltip: 'Refresh newsletter status',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
