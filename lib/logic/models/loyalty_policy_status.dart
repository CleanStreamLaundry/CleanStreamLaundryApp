import 'dart:convert';

import 'package:crypto/crypto.dart';

class LoyaltyPolicySection {
  final String heading;
  final List<String> paragraphs;

  const LoyaltyPolicySection({required this.heading, required this.paragraphs});
}

class LoyaltyPolicyDescriptor {
  final String requiredVersion;
  final String policyText;
  final String policySha256;
  final String title;
  final String? effectiveDate;
  final List<LoyaltyPolicySection> sections;

  const LoyaltyPolicyDescriptor._({
    required this.requiredVersion,
    required this.policyText,
    required this.policySha256,
    required this.title,
    required this.effectiveDate,
    required this.sections,
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
    var title = 'Loyalty Program Terms';
    String? effectiveDate;
    var sections = <LoyaltyPolicySection>[
      LoyaltyPolicySection(
        heading: '',
        paragraphs: List.unmodifiable(policyText.split('\n\n')),
      ),
    ];
    // Keep old text readable while new publications carry structured legal copy.
    if (policyText.trimLeft().startsWith('{')) {
      final document = jsonDecode(policyText);
      if (document is! Map<String, dynamic> ||
          document['title'] is! String ||
          (document['title'] as String).trim().isEmpty ||
          document['effective_date'] is! String ||
          !RegExp(
            r'^\d{4}-\d{2}-\d{2}$',
          ).hasMatch(document['effective_date']) ||
          DateTime.tryParse(
                document['effective_date'],
              )?.toIso8601String().substring(0, 10) !=
              document['effective_date'] ||
          document['sections'] is! List ||
          (document['sections'] as List).isEmpty) {
        throw const FormatException('Invalid loyalty policy document');
      }
      title = document['title'];
      effectiveDate = document['effective_date'];
      sections = (document['sections'] as List).map((section) {
        if (section is! Map<String, dynamic> ||
            section['heading'] is! String ||
            (section['heading'] as String).trim().isEmpty ||
            section['paragraphs'] is! List ||
            (section['paragraphs'] as List).isEmpty ||
            !(section['paragraphs'] as List).every(
              (paragraph) => paragraph is String && paragraph.trim().isNotEmpty,
            )) {
          throw const FormatException('Invalid loyalty policy section');
        }
        return LoyaltyPolicySection(
          heading: section['heading'],
          paragraphs: List<String>.unmodifiable(section['paragraphs']),
        );
      }).toList();
    }
    return LoyaltyPolicyDescriptor._(
      requiredVersion: requiredVersion,
      policyText: policyText,
      policySha256: policySha256,
      title: title,
      effectiveDate: effectiveDate,
      sections: List.unmodifiable(sections),
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
