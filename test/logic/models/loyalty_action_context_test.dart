import 'package:clean_stream_laundry_app/logic/models/loyalty_action_context.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/loyalty_action_context.dart';

void main() {
  test(
    'keeps the verified policy and sends only server context acknowledgement',
    () {
      final value = actionContext(action: 'account_deletion');
      expect(value.recoveryDays, 90);
      expect(value.purchasedBalanceCents, 2050);
      expect(value.acknowledgement, deletionAcknowledgement);
      expect(value.policy.requiredVersion, 'synthetic-review-consent');
      expect(value.acknowledge(), {
        'context_id': '22222222-2222-4222-8222-222222222222',
        'acknowledged': true,
      });
    },
  );

  for (final invalid in <String, Object?>{
    'context_id': '',
    'subject_id': null,
    'acknowledgement': ' ',
    'action': 'unknown',
    'purchased_balance_cents': -1,
    'promotional_balance_cents': 2.5,
    'recovery_days': 0,
  }.entries) {
    test('rejects invalid ${invalid.key}', () {
      final wire = actionContextWire(action: 'account_deletion');
      wire[invalid.key] = invalid.value;
      expect(() => LoyaltyActionContext.fromJson(wire), throwsFormatException);
    });
  }

  test('rejects a changed policy body without its matching hash', () {
    final wire = actionContextWire();
    (wire['policy'] as Map<String, dynamic>)['policy_text'] = '{}';
    expect(() => LoyaltyActionContext.fromJson(wire), throwsFormatException);
  });
}
