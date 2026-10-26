enum TopupRefundStatus {
  requested,
  approved,
  unknown,
  pending,
  succeeded,
  failed,
  canceled,
  denied,
}

enum TopupRefundIneligibleReason {
  alreadyRequested('already_requested'),
  provenanceUnavailable('provenance_unavailable'),
  refundWindowClosed('refund_window_closed'),
  walletUsedAfterTopup('wallet_used_after_topup'),
  rewardProvenanceUnavailable('reward_provenance_unavailable'),
  refundFundsUnavailable('refund_funds_unavailable');

  const TopupRefundIneligibleReason(this.wire);
  final String wire;
}

class TopupRefund {
  const TopupRefund._({
    required this.id,
    required this.loadId,
    required this.customerId,
    required this.status,
    required this.principalCents,
    required this.bonusReservedCents,
    required this.requestedAt,
    required this.paymentSucceededAt,
    required this.reviewedAt,
    required this.completedAt,
    required this.policyVersion,
    required this.locationId,
    required this.reviewNote,
  });

  final String id, loadId, customerId, policyVersion;
  final String? locationId, reviewNote;
  final TopupRefundStatus status;
  final int principalCents, bonusReservedCents;
  final DateTime requestedAt, paymentSucceededAt;
  final DateTime? reviewedAt, completedAt;

  factory TopupRefund.fromJson(Object? value) {
    final j = _object(value, const [
      'id',
      'load_id',
      'customer_id',
      'status',
      'principal_cents',
      'bonus_reserved_cents',
      'currency',
      'requested_at',
      'payment_succeeded_at',
      'reviewed_at',
      'completed_at',
      'policy_version',
      'location_id',
      'review_note',
    ]);
    final statuses = TopupRefundStatus.values.where(
      (s) => s.name == j['status'],
    );
    if (statuses.isEmpty ||
        j['currency'] != 'usd' ||
        j['policy_version'] is! String ||
        (j['policy_version'] as String).isEmpty ||
        (j['review_note'] != null &&
            (j['review_note'] is! String ||
                (j['review_note'] as String).length > 2000))) {
      throw const FormatException('Invalid top-up refund');
    }
    final status = statuses.single;
    final completed = _date(j['completed_at'], nullable: true);
    if ((status == TopupRefundStatus.succeeded) != (completed != null)) {
      throw const FormatException('Invalid refund completion');
    }
    return TopupRefund._(
      id: _uuid(j['id']),
      loadId: topupRefundLoadId(j['load_id']),
      customerId: _uuid(j['customer_id']),
      status: status,
      principalCents: _cents(j['principal_cents'], positive: true),
      bonusReservedCents: _cents(j['bonus_reserved_cents']),
      requestedAt: _date(j['requested_at'])!,
      paymentSucceededAt: _date(j['payment_succeeded_at'])!,
      reviewedAt: _date(j['reviewed_at'], nullable: true),
      completedAt: completed,
      policyVersion: j['policy_version'] as String,
      locationId: j['location_id'] == null
          ? null
          : topupRefundLoadId(j['location_id']),
      reviewNote: j['review_note'] as String?,
    );
  }
}

class RefundableTopup {
  const RefundableTopup._({
    required this.loadId,
    required this.principalCents,
    required this.paymentSucceededAt,
    required this.requestDeadline,
    required this.refund,
    required this.ineligibleReason,
  });

  final String loadId;
  final int principalCents;
  final DateTime? paymentSucceededAt, requestDeadline;
  final TopupRefund? refund;
  final TopupRefundIneligibleReason? ineligibleReason;
  bool get isAdvisoryEligible => ineligibleReason == null && refund == null;

  factory RefundableTopup.fromJson(Object? value) {
    final j = _object(value, const [
      'load_id',
      'principal_cents',
      'currency',
      'payment_succeeded_at',
      'request_deadline',
      'refund',
      'ineligible_reason',
    ]);
    final reason = j['ineligible_reason'];
    final reasons = TopupRefundIneligibleReason.values.where(
      (r) => r.wire == reason,
    );
    if (j['currency'] != 'usd' || (reason != null && reasons.isEmpty)) {
      throw const FormatException('Invalid top-up eligibility');
    }
    final loadId = topupRefundLoadId(j['load_id']);
    final principal = _cents(j['principal_cents'], positive: true);
    final paid = _date(j['payment_succeeded_at'], nullable: true);
    final deadline = _date(j['request_deadline'], nullable: true);
    final refund = j['refund'] == null
        ? null
        : TopupRefund.fromJson(j['refund']);
    if ((paid == null) != (deadline == null) ||
        (paid != null && deadline != paid.add(const Duration(hours: 48))) ||
        (reason == null && paid == null) ||
        ((reason == 'already_requested') != (refund != null)) ||
        (refund != null &&
            (refund.loadId != loadId ||
                refund.principalCents != principal ||
                refund.paymentSucceededAt != paid))) {
      throw const FormatException('Inconsistent top-up refund');
    }
    return RefundableTopup._(
      loadId: loadId,
      principalCents: principal,
      paymentSucceededAt: paid,
      requestDeadline: deadline,
      refund: refund,
      ineligibleReason: reason == null ? null : reasons.single,
    );
  }
}

// Keep PostgreSQL bigint identifiers lossless on Flutter web as well as mobile.
String topupRefundLoadId(Object? value) {
  if (value is! String ||
      !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(value) ||
      BigInt.parse(value) > BigInt.parse('9223372036854775807')) {
    throw const FormatException('Invalid top-up identifier');
  }
  return value;
}

Map<String, dynamic> _object(Object? value, List<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    throw const FormatException('Invalid refund response shape');
  }
  return value;
}

String _uuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(value)) {
    throw const FormatException('Invalid refund identifier');
  }
  return value;
}

int _cents(Object? value, {bool positive = false}) {
  if (value is! int || value < (positive ? 1 : 0) || value > 2147483647) {
    throw const FormatException('Invalid refund cents');
  }
  return value;
}

DateTime? _date(Object? value, {bool nullable = false}) {
  if (value == null && nullable) return null;
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid refund timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
    throw const FormatException('Invalid refund timestamp');
  }
  return parsed;
}
