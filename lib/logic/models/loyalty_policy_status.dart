import 'dart:convert';

import 'package:crypto/crypto.dart';

class LoyaltyPolicyDescriptor {
  final String requiredVersion;
  final String policyText;
  final String policySha256;

  const LoyaltyPolicyDescriptor._({
    required this.requiredVersion,
    required this.policyText,
    required this.policySha256,
  });

  factory LoyaltyPolicyDescriptor.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid loyalty policy descriptor');
    }
    final requiredVersion = json['required_version'];
    final policyText = json['policy_text'];
    final policySha256 = json['policy_sha256'];
    if (requiredVersion is! String ||
        requiredVersion.trim().isEmpty ||
        policyText is! String ||
        policyText.trim().isEmpty ||
        policySha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(policySha256)) {
      throw const FormatException('Invalid loyalty policy descriptor fields');
    }
    if (sha256.convert(utf8.encode(policyText)).toString() != policySha256) {
      throw const FormatException('Loyalty policy hash mismatch');
    }
    return LoyaltyPolicyDescriptor._(
      requiredVersion: requiredVersion,
      policyText: policyText,
      policySha256: policySha256,
    );
  }
}

class LoyaltyPolicyStatus {
  final LoyaltyPolicyDescriptor descriptor;
  final String? acceptedVersion;
  final DateTime? acceptedAt;
  final bool acceptanceRequired;

  String get requiredVersion => descriptor.requiredVersion;
  String get policyText => descriptor.policyText;
  String get policySha256 => descriptor.policySha256;

  const LoyaltyPolicyStatus._({
    required this.descriptor,
    required this.acceptedVersion,
    required this.acceptedAt,
    required this.acceptanceRequired,
  });

  factory LoyaltyPolicyStatus.fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        !const [
          'accepted_version',
          'accepted_at',
          'acceptance_required',
        ].every(json.containsKey)) {
      throw const FormatException('Invalid loyalty policy response');
    }

    final descriptor = LoyaltyPolicyDescriptor.fromJson(json);
    final acceptedVersion = json['accepted_version'];
    final acceptanceRequired = json['acceptance_required'];
    if ((acceptedVersion != null &&
            (acceptedVersion is! String || acceptedVersion.trim().isEmpty)) ||
        acceptanceRequired is! bool) {
      throw const FormatException('Invalid loyalty policy fields');
    }
    final acceptedAt = _parseAcceptedAt(json['accepted_at']);
    // Match the RPC predicate; nullable legacy fields never imply acceptance.
    if (acceptanceRequired !=
        (acceptedVersion != descriptor.requiredVersion || acceptedAt == null)) {
      throw const FormatException('Inconsistent loyalty policy acceptance');
    }

    return LoyaltyPolicyStatus._(
      descriptor: descriptor,
      acceptedVersion: acceptedVersion as String?,
      acceptedAt: acceptedAt,
      acceptanceRequired: acceptanceRequired,
    );
  }

  static DateTime? _parseAcceptedAt(Object? value) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(
          r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T'
          r'([01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?'
          r'(Z|[+-]([01]\d|2[0-3]):[0-5]\d)$',
        ).hasMatch(value)) {
      throw const FormatException('Invalid loyalty policy acceptance time');
    }
    final parsed = DateTime.tryParse(value);
    final date = value.substring(0, 10);
    // DateTime.parse normalizes overflow dates, which are not valid wire data.
    if (parsed == null ||
        DateTime.parse(
              '${date}T00:00:00Z',
            ).toIso8601String().substring(0, 10) !=
            date) {
      throw const FormatException('Invalid loyalty policy acceptance time');
    }
    return parsed;
  }
}
