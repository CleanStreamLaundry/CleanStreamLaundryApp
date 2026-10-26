class AdmissionStatus {
  final String subjectId;
  final String accountAccess;
  final String nextStep;
  final String? reason;
  final String accountState;
  // Server-authoritative UTC deadline: never derive it from the client clock
  // or clamp a grandfathered deadline to the current 90-day request window.
  final DateTime? restoreUntil;

  const AdmissionStatus._({
    required this.subjectId,
    required this.accountAccess,
    required this.nextStep,
    required this.reason,
    required this.accountState,
    required this.restoreUntil,
  });

  factory AdmissionStatus.fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json.length != 6 ||
        !const [
          'subject_id',
          'account_access',
          'next_step',
          'reason',
          'account_state',
          'restore_until',
        ].every(json.containsKey)) {
      throw const FormatException('Invalid admission response');
    }

    final subjectId = json['subject_id'];
    if (subjectId is! String ||
        subjectId.length != 36 ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(subjectId)) {
      throw const FormatException('Invalid admission subject');
    }

    final accountAccess = json['account_access'];
    final nextStep = json['next_step'];
    final reason = json['reason'];
    final accountState = json['account_state'];
    final pending = accountState == 'pending_deletion';
    final valid = switch ((accountAccess, nextStep, reason, accountState)) {
      ('eligible', 'home' || 'review_terms', null, 'legacy_active') => true,
      (
        'restricted',
        'verify_email' || 'enroll_totp' || 'challenge_totp',
        null,
        'legacy_active' || 'pending_deletion',
      ) =>
        true,
      (
        'restricted',
        'blocked',
        'profile_missing' || 'role_unavailable' || 'unsupported_factor',
        'legacy_active' || 'pending_deletion',
      ) =>
        true,
      ('restricted', 'blocked', 'account_restricted', 'blocked') => true,
      (
        'restricted',
        'blocked',
        'explicit_restore_required' || 'restore_expired',
        'pending_deletion',
      ) =>
        true,
      _ => false,
    };
    if (!valid || (!pending && json['restore_until'] != null)) {
      throw const FormatException('Invalid admission state');
    }
    DateTime? restoreUntil;
    if (pending) {
      final value = json['restore_until'];
      if (value is! String ||
          RegExp(
                r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
                r'(?:\.\d{1,6})?(?:Z|\+00:00)$',
              ).stringMatch(value) !=
              value) {
        throw const FormatException('Invalid restoration deadline');
      }
      restoreUntil = DateTime.tryParse(value);
      if (restoreUntil == null ||
          restoreUntil.toIso8601String().substring(0, 19) !=
              value.substring(0, 19)) {
        throw const FormatException('Invalid restoration deadline');
      }
    }

    return AdmissionStatus._(
      subjectId: subjectId,
      accountAccess: accountAccess as String,
      nextStep: nextStep as String,
      reason: reason as String?,
      accountState: accountState as String,
      restoreUntil: restoreUntil,
    );
  }
}
