import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';

class LoyaltyActionContext {
  final String subjectId;
  final String action;
  final String contextId;
  final LoyaltyPolicyDescriptor policy;
  final String acknowledgement;
  final int purchasedBalanceCents;
  final int promotionalBalanceCents;
  final int? recoveryDays;

  const LoyaltyActionContext._({
    required this.subjectId,
    required this.action,
    required this.contextId,
    required this.policy,
    required this.acknowledgement,
    required this.purchasedBalanceCents,
    required this.promotionalBalanceCents,
    required this.recoveryDays,
  });

  factory LoyaltyActionContext.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        !['subject_id', 'context_id', 'acknowledgement'].every(
          (key) =>
              value[key] is String && (value[key] as String).trim().isNotEmpty,
        ) ||
        !['wallet_load', 'account_deletion'].contains(value['action']) ||
        value['purchased_balance_cents'] is! int ||
        value['promotional_balance_cents'] is! int ||
        value['purchased_balance_cents'] < 0 ||
        value['promotional_balance_cents'] < 0 ||
        (value['action'] == 'account_deletion' &&
            (value['recovery_days'] is! int || value['recovery_days'] <= 0))) {
      throw const FormatException('Invalid loyalty consent details');
    }
    return LoyaltyActionContext._(
      subjectId: value['subject_id'],
      action: value['action'],
      contextId: value['context_id'],
      policy: LoyaltyPolicyDescriptor.fromJson(value['policy']),
      acknowledgement: value['acknowledgement'],
      purchasedBalanceCents: value['purchased_balance_cents'],
      promotionalBalanceCents: value['promotional_balance_cents'],
      recoveryDays: value['recovery_days'] as int?,
    );
  }

  Map<String, dynamic> acknowledge() => {
    'context_id': contextId,
    'acknowledged': true,
  };
}
