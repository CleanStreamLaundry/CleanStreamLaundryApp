import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/topup_refunds/fixtures.dart';

void main() {
  test('lossless bigint IDs, integer cents, UTC and nullable fields', () {
    final refund = TopupRefund.fromJson(refundJson());
    expect(refund.loadId, '9007199254740993');
    expect(refund.principalCents, 2000);
    expect(refund.bonusReservedCents, 500);
    expect(refund.requestedAt.isUtc, isTrue);
    expect(refund.completedAt, isNull);
    expect(refund.locationId, isNull);
  });
  for (final status in TopupRefundStatus.values) {
    test('parses exact ${status.name} status', () {
      expect(
        TopupRefund.fromJson(refundJson(status: status.name)).status,
        status,
      );
    });
  }
  for (final entry in <String, Object?>{
    'id': 'bad',
    'load_id': 42,
    'customer_id': '',
    'status': 'paid',
    'principal_cents': 20.0,
    'bonus_reserved_cents': -1,
    'currency': 'USD',
    'requested_at': '2026-02-30T10:00:00Z',
    'payment_succeeded_at': '2026-09-29T10:00:00',
    'reviewed_at': false,
    'completed_at': '2026-09-30T12:00:00Z',
    'policy_version': '',
    'location_id': '9223372036854775808',
    'review_note': 7,
  }.entries) {
    test('rejects malformed operation ${entry.key}', () {
      expect(
        () => TopupRefund.fromJson(refundJson()..[entry.key] = entry.value),
        throwsFormatException,
      );
    });
  }
  test('succeeded requires processor completion timestamp', () {
    expect(
      () => TopupRefund.fromJson(
        refundJson(status: 'succeeded')..['completed_at'] = null,
      ),
      throwsFormatException,
    );
  });
  test('unknown/missing keys and nonobject rejected', () {
    for (final json in [
      null,
      [],
      refundJson()..remove('review_note'),
      refundJson()..['extra'] = 1,
    ]) {
      expect(() => TopupRefund.fromJson(json), throwsFormatException);
    }
  });
  test(
    'advisory eligibility includes server deadline, not local clock verdict',
    () {
      final topup = RefundableTopup.fromJson(topupJson());
      expect(topup.isAdvisoryEligible, isTrue);
      expect(
        topup.requestDeadline!.difference(topup.paymentSucceededAt!),
        const Duration(hours: 48),
      );
    },
  );
  for (final reason in TopupRefundIneligibleReason.values) {
    test('parses reason ${reason.wire}', () {
      final topup = RefundableTopup.fromJson(
        topupJson(
          reason: reason.wire,
          refund: reason == TopupRefundIneligibleReason.alreadyRequested
              ? refundJson()
              : null,
        ),
      );
      expect(topup.ineligibleReason, reason);
      expect(topup.isAdvisoryEligible, isFalse);
    });
  }
  test('historical load may have no provenance clock', () {
    final json = topupJson(reason: 'provenance_unavailable')
      ..['payment_succeeded_at'] = null
      ..['request_deadline'] = null;
    expect(RefundableTopup.fromJson(json).isAdvisoryEligible, isFalse);
  });
  test('rejects mismatched clocks, nested refund, reason and money', () {
    for (final json in [
      topupJson()..['request_deadline'] = '2026-10-01T10:00:01Z',
      topupJson()..['payment_succeeded_at'] = null,
      topupJson()..['ineligible_reason'] = 'new_unknown_reason',
      topupJson(reason: 'already_requested'),
      topupJson(refund: refundJson()),
      topupJson(
        reason: 'already_requested',
        refund: refundJson(load: '2'),
      ),
      topupJson()..['principal_cents'] = 0,
      topupJson()..['currency'] = 'eur',
    ]) {
      expect(() => RefundableTopup.fromJson(json), throwsFormatException);
    }
  });
  test('strict bigint rejects unsafe coercion and noncanonical values', () {
    for (final id in [
      null,
      1,
      '0',
      '-1',
      '01',
      '1.0',
      ' 1',
      '9223372036854775808',
    ]) {
      expect(() => topupRefundLoadId(id), throwsFormatException);
    }
    expect(topupRefundLoadId('9223372036854775807'), '9223372036854775807');
  });
}
