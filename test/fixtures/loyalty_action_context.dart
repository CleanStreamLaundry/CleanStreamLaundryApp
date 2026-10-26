import 'dart:convert';

import 'package:clean_stream_laundry_app/logic/models/loyalty_action_context.dart';
import 'package:crypto/crypto.dart';

const purchaseAcknowledgement =
    'I agree to the Loyalty Program Terms for this purchase.';
const deletionAcknowledgement =
    'I voluntarily request account deletion and agree to surrender my remaining purchased and promotional laundry credit without payment if I do not restore my account before the recovery deadline.';

Map<String, dynamic> actionContextWire({
  String action = 'wallet_load',
  String subject = '11111111-1111-4111-8111-111111111111',
}) {
  final text = jsonEncode({
    'title': 'Loyalty Program Terms',
    'effective_date': '2026-10-05',
    'sections': [
      {
        'heading': '1. Prepaid services',
        'paragraphs': [purchaseAcknowledgement],
      },
      {
        'heading': '2. Voluntary surrender',
        'paragraphs': [deletionAcknowledgement],
      },
    ],
  });
  return {
    'context_id': '22222222-2222-4222-8222-222222222222',
    'subject_id': subject,
    'action': action,
    'policy': {
      'required_version': 'synthetic-review-consent',
      'policy_text': text,
      'policy_sha256': sha256.convert(utf8.encode(text)).toString(),
    },
    'acknowledgement': action == 'wallet_load'
        ? purchaseAcknowledgement
        : deletionAcknowledgement,
    'purchased_balance_cents': 2050,
    'promotional_balance_cents': 500,
    'recovery_days': action == 'account_deletion' ? 90 : null,
  };
}

LoyaltyActionContext actionContext({
  String action = 'wallet_load',
  String subject = '11111111-1111-4111-8111-111111111111',
}) => LoyaltyActionContext.fromJson(
  actionContextWire(action: action, subject: subject),
);
