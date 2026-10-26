import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:flutter_test/flutter_test.dart';

const _text = 'Review-only synthetic policy.\n\nSecond paragraph.';
const _hash =
    '18194ff45fc91b265e82cd1560733c3518c541b4027db4670c74a93f1d055f18';

Map<String, dynamic> _status() => {
  'required_version': 'synthetic-v2',
  'policy_text': _text,
  'policy_sha256': _hash,
  'accepted_version': null,
  'accepted_at': null,
  'acceptance_required': true,
};

void main() {
  group('structured legal document', () {
    Map<String, dynamic> document() => {
      'title': 'Loyalty Program Terms',
      'effective_date': '2026-10-02',
      'sections': [
        {
          'heading': 'Purchased credit',
          'paragraphs': ['Credit does not expire.'],
        },
      ],
    };
    LoyaltyPolicyDescriptor parse(Map<String, dynamic> content) {
      final text = jsonEncode(content);
      return LoyaltyPolicyDescriptor.fromJson({
        'required_version': '2026-10-02.1',
        'policy_text': text,
        'policy_sha256': sha256.convert(utf8.encode(text)).toString(),
      });
    }

    test('formats structured content without changing accepted bytes', () {
      final content = document();
      final result = parse(content);
      expect(result.title, 'Loyalty Program Terms');
      expect(result.effectiveDate, '2026-10-02');
      expect(result.sections.single.heading, 'Purchased credit');
      expect(result.sections.single.paragraphs, ['Credit does not expire.']);
      expect(result.policyText, jsonEncode(content));
      expect(() => result.sections.clear(), throwsUnsupportedError);
      expect(
        () => result.sections.single.paragraphs.clear(),
        throwsUnsupportedError,
      );
    });
    for (final bad in [
      document()..['title'] = '',
      document()..['effective_date'] = '2026-02-30',
      document()..['sections'] = [],
      document()
        ..['sections'] = [
          {
            'heading': 'A',
            'paragraphs': [42],
          },
        ],
      document()
        ..['sections'] = [
          {
            'heading': '',
            'paragraphs': ['A'],
          },
        ],
    ]) {
      test('rejects malformed content $bad', () {
        expect(() => parse(bad), throwsFormatException);
      });
    }
  });
  group('public descriptor', () {
    Map<String, dynamic> descriptor() => {
      'required_version': 'review-only-synthetic',
      'policy_text': _text,
      'policy_sha256': _hash,
    };

    test(
      'decodes only the three public fields without acceptance defaults',
      () {
        final result = LoyaltyPolicyDescriptor.fromJson(descriptor());
        expect(result.requiredVersion, 'review-only-synthetic');
        expect(result.policyText, _text);
        expect(result.policySha256, _hash);
        expect(
          () => LoyaltyPolicyStatus.fromJson(descriptor()),
          throwsFormatException,
        );
      },
    );

    test(
      'status reuses the same descriptor and preserves existing getters',
      () {
        final result = LoyaltyPolicyStatus.fromJson(_status());
        expect(result.requiredVersion, result.descriptor.requiredVersion);
        expect(result.policyText, result.descriptor.policyText);
        expect(result.policySha256, result.descriptor.policySha256);
      },
    );

    for (final key in ['required_version', 'policy_text', 'policy_sha256']) {
      test('requires public field $key', () {
        expect(
          () => LoyaltyPolicyDescriptor.fromJson(descriptor()..remove(key)),
          throwsFormatException,
        );
      });
    }

    for (final value in [
      null,
      [descriptor()],
      descriptor()..['policy_text'] = 'changed',
    ]) {
      test('rejects malformed public descriptor ${value.runtimeType}', () {
        expect(
          () => LoyaltyPolicyDescriptor.fromJson(value),
          throwsFormatException,
        );
      });
    }
  });

  test('decodes the six fields without accepting a new account', () {
    final status = LoyaltyPolicyStatus.fromJson(_status());

    expect(status.requiredVersion, 'synthetic-v2');
    expect(status.policyText, _text);
    expect(status.policySha256, _hash);
    expect(status.acceptedVersion, isNull);
    expect(status.acceptedAt, isNull);
    expect(status.acceptanceRequired, isTrue);
  });

  test('decodes accepted server time, including offset and microseconds', () {
    final status = LoyaltyPolicyStatus.fromJson(
      _status()
        ..['accepted_version'] = 'synthetic-v2'
        ..['accepted_at'] = '2026-09-29T12:34:56.123456-04:00'
        ..['acceptance_required'] = false,
    );

    expect(status.acceptedVersion, 'synthetic-v2');
    expect(status.acceptedAt, DateTime.utc(2026, 9, 29, 16, 34, 56, 123, 456));
    expect(status.acceptanceRequired, isFalse);
  });

  test('an earlier accepted version still requires acceptance', () {
    final status = LoyaltyPolicyStatus.fromJson(
      _status()
        ..['accepted_version'] = 'synthetic-v1'
        ..['accepted_at'] = '2026-09-28T00:00:00Z',
    );

    expect(status.acceptedVersion, 'synthetic-v1');
    expect(status.acceptanceRequired, isTrue);
  });

  test('nullable legacy fields follow the server acceptance predicate', () {
    final missingTime = LoyaltyPolicyStatus.fromJson(
      _status()..['accepted_version'] = 'synthetic-v2',
    );
    final missingVersion = LoyaltyPolicyStatus.fromJson(
      _status()..['accepted_at'] = '2026-09-28T00:00:00+00:00',
    );

    expect(missingTime.acceptanceRequired, isTrue);
    expect(missingVersion.acceptanceRequired, isTrue);
  });

  test('copies values without retaining the mutable response map', () {
    final wire = _status();
    final status = LoyaltyPolicyStatus.fromJson(wire);
    wire.clear();

    expect(status.requiredVersion, 'synthetic-v2');
    expect(status.policyText, _text);
    expect(status.policySha256, _hash);
    expect(status.acceptanceRequired, isTrue);
  });

  test('hashes exact UTF-8 bytes, including non-ASCII text', () {
    const text = 'Caf\u00e9 policy.\n\n\u6d17\u6fef';
    final status = LoyaltyPolicyStatus.fromJson(
      _status()
        ..['policy_text'] = text
        ..['policy_sha256'] =
            '74f04e1d861f10b81642ec5f80da216d16c387ea0cdb164dcd04e661db8d2725',
    );

    expect(status.policyText, text);
  });

  test('retains whitespace when it is covered by the server hash', () {
    const text = '  $_text\n';
    final status = LoyaltyPolicyStatus.fromJson(
      _status()
        ..['policy_text'] = text
        ..['policy_sha256'] =
            '5f8d01f619633d72b2daf3c3f083f448c3e5c7f83ae5f6ab269f10dc64840381',
    );

    expect(status.policyText, text);
  });

  test(
    'accepts leap day and UTC timestamps without calendar normalization',
    () {
      final status = LoyaltyPolicyStatus.fromJson(
        _status()
          ..['accepted_version'] = 'synthetic-v1'
          ..['accepted_at'] = '2024-02-29T00:00:00Z',
      );

      expect(status.acceptedAt, DateTime.utc(2024, 2, 29));
    },
  );

  for (final entry in {
    'trailing newline': '$_text\n',
    'leading space': ' $_text',
    'CRLF conversion': _text.replaceAll('\n', '\r\n'),
  }.entries) {
    test('rejects a changed payload: ${entry.key}', () {
      expect(
        () => LoyaltyPolicyStatus.fromJson(
          _status()..['policy_text'] = entry.value,
        ),
        throwsFormatException,
      );
    });
  }

  for (final input in [
    null,
    'status',
    true,
    <dynamic>[],
    [_status()],
  ]) {
    test('rejects a non-object response ${input.runtimeType}', () {
      expect(() => LoyaltyPolicyStatus.fromJson(input), throwsFormatException);
    });
  }

  for (final field in _status().keys) {
    test('requires the $field key even when its value can be null', () {
      expect(
        () => LoyaltyPolicyStatus.fromJson(_status()..remove(field)),
        throwsFormatException,
      );
    });
  }

  for (final field in ['required_version', 'policy_text', 'policy_sha256']) {
    for (final value in [null, 123, '', '   ']) {
      test('rejects invalid $field value $value', () {
        expect(
          () => LoyaltyPolicyStatus.fromJson(_status()..[field] = value),
          throwsFormatException,
        );
      });
    }
  }

  for (final hash in [_hash.toUpperCase(), 'a' * 63, 'g' * 64, 'a' * 64]) {
    test('rejects malformed or mismatched hash $hash', () {
      expect(
        () => LoyaltyPolicyStatus.fromJson(_status()..['policy_sha256'] = hash),
        throwsFormatException,
      );
    });
  }

  for (final value in [123, '', '   ']) {
    test('rejects invalid accepted_version $value', () {
      expect(
        () => LoyaltyPolicyStatus.fromJson(
          _status()..['accepted_version'] = value,
        ),
        throwsFormatException,
      );
    });
  }

  for (final value in [null, 0, 'true']) {
    test('requires a boolean acceptance_required $value', () {
      expect(
        () => LoyaltyPolicyStatus.fromJson(
          _status()..['acceptance_required'] = value,
        ),
        throwsFormatException,
      );
    });
  }

  for (final value in [
    123,
    '',
    'not-a-time',
    '2026-09-29',
    '2026-09-29T12:00:00',
    '2026-02-30T12:00:00Z',
    '2026-09-29T24:00:00Z',
    '2026-09-29T12:60:00Z',
  ]) {
    test('rejects invalid or unzoned accepted_at $value', () {
      expect(
        () => LoyaltyPolicyStatus.fromJson(_status()..['accepted_at'] = value),
        throwsFormatException,
      );
    });
  }

  for (final acceptedVersion in [null, 'synthetic-v1', 'synthetic-v2']) {
    test(
      'false acceptance_required needs matching version and time $acceptedVersion',
      () {
        expect(
          () => LoyaltyPolicyStatus.fromJson(
            _status()
              ..['accepted_version'] = acceptedVersion
              ..['acceptance_required'] = false,
          ),
          throwsFormatException,
        );
      },
    );
  }

  test('rejects an old version marked accepted even with a timestamp', () {
    expect(
      () => LoyaltyPolicyStatus.fromJson(
        _status()
          ..['accepted_version'] = 'synthetic-v1'
          ..['accepted_at'] = '2026-09-29T00:00:00Z'
          ..['acceptance_required'] = false,
      ),
      throwsFormatException,
    );
  });

  test('rejects a matching accepted version/time marked required', () {
    expect(
      () => LoyaltyPolicyStatus.fromJson(
        _status()
          ..['accepted_version'] = 'synthetic-v2'
          ..['accepted_at'] = '2026-09-29T00:00:00Z',
      ),
      throwsFormatException,
    );
  });
}
