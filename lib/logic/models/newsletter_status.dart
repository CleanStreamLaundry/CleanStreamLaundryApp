enum NewsletterState {
  notSubscribed,
  pending,
  expired,
  subscribed,
  unsubscribed,
  suppressed,
}

class NewsletterStatus {
  final String subjectId;
  final NewsletterState state;
  final DateTime? requestedAt;
  final DateTime? confirmedAt;
  final DateTime? unsubscribedAt;
  final String consentVersion;
  final String consentText;
  final bool enabled;

  const NewsletterStatus._({
    required this.subjectId,
    required this.state,
    required this.requestedAt,
    required this.confirmedAt,
    required this.unsubscribedAt,
    required this.consentVersion,
    required this.consentText,
    required this.enabled,
  });

  factory NewsletterStatus.fromJson(Object? json) {
    const keys = {
      'subject_id',
      'state',
      'requested_at',
      'confirmed_at',
      'unsubscribed_at',
      'consent_version',
      'consent_text',
      'enabled',
    };
    if (json is! Map<String, dynamic> ||
        json.length != keys.length ||
        !keys.every(json.containsKey)) {
      throw const FormatException('Invalid newsletter response');
    }
    final subject = json['subject_id'];
    final version = json['consent_version'];
    final text = json['consent_text'];
    if (subject is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(subject) ||
        version is! String ||
        version.trim().isEmpty ||
        text is! String ||
        text.trim().isEmpty ||
        json['enabled'] is! bool) {
      throw const FormatException('Invalid newsletter fields');
    }
    final state = switch (json['state']) {
      'not_subscribed' => NewsletterState.notSubscribed,
      'pending' => NewsletterState.pending,
      'expired' => NewsletterState.expired,
      'subscribed' => NewsletterState.subscribed,
      'unsubscribed' => NewsletterState.unsubscribed,
      'suppressed' => NewsletterState.suppressed,
      _ => throw const FormatException('Invalid newsletter state'),
    };
    DateTime? date(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String ||
          !RegExp(
            r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
          ).hasMatch(value)) {
        throw const FormatException('Invalid newsletter timestamp');
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null ||
          parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
        throw const FormatException('Invalid newsletter timestamp');
      }
      return parsed;
    }

    final requested = date('requested_at');
    final confirmed = date('confirmed_at');
    final unsubscribed = date('unsubscribed_at');
    final validState = switch (state) {
      NewsletterState.notSubscribed =>
        requested == null && confirmed == null && unsubscribed == null,
      NewsletterState.pending || NewsletterState.expired =>
        requested != null && confirmed == null && unsubscribed == null,
      NewsletterState.subscribed =>
        requested != null && confirmed != null && unsubscribed == null,
      NewsletterState.unsubscribed => requested != null && unsubscribed != null,
      NewsletterState.suppressed => true,
    };
    if (!validState ||
        (requested == null && (confirmed != null || unsubscribed != null)) ||
        (confirmed != null && confirmed.isBefore(requested!)) ||
        (unsubscribed != null &&
            unsubscribed.isBefore(confirmed ?? requested!))) {
      throw const FormatException('Inconsistent newsletter status');
    }
    return NewsletterStatus._(
      subjectId: subject,
      state: state,
      requestedAt: requested,
      confirmedAt: confirmed,
      unsubscribedAt: unsubscribed,
      consentVersion: version,
      consentText: text,
      enabled: json['enabled'] as bool,
    );
  }
}
