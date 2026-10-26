import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const subject = '11111111-1111-1111-1111-111111111111';
  const outcomes = [
    ('eligible', 'home', null, 'legacy_active'),
    ('eligible', 'review_terms', null, 'legacy_active'),
    ('restricted', 'verify_email', null, 'legacy_active'),
    ('restricted', 'enroll_totp', null, 'legacy_active'),
    ('restricted', 'challenge_totp', null, 'legacy_active'),
    ('restricted', 'blocked', 'profile_missing', 'legacy_active'),
    ('restricted', 'blocked', 'role_unavailable', 'legacy_active'),
    ('restricted', 'blocked', 'unsupported_factor', 'legacy_active'),
    ('restricted', 'blocked', 'account_restricted', 'blocked'),
  ];

  Map<String, dynamic> wire({
    String access = 'eligible',
    String step = 'home',
    String? reason,
    String state = 'legacy_active',
  }) => {
    'subject_id': subject,
    'account_access': access,
    'next_step': step,
    'reason': reason,
    'account_state': state,
    'restore_until': null,
  };

  for (final outcome in outcomes) {
    test('decodes SQL outcome $outcome without inferring authorization', () {
      final result = AdmissionStatus.fromJson(
        wire(
          access: outcome.$1,
          step: outcome.$2,
          reason: outcome.$3,
          state: outcome.$4,
        ),
      );

      expect(result.subjectId, subject);
      expect(result.accountAccess, outcome.$1);
      expect(result.nextStep, outcome.$2);
      expect(result.reason, outcome.$3);
      expect(result.accountState, outcome.$4);
      expect(result.restoreUntil, isNull);
    });
  }

  test('rejects every impossible combination of the implemented values', () {
    var rejected = 0;
    for (final access in ['eligible', 'restricted']) {
      for (final step in [
        'home',
        'review_terms',
        'verify_email',
        'enroll_totp',
        'challenge_totp',
        'blocked',
      ]) {
        for (final reason in [
          null,
          'profile_missing',
          'role_unavailable',
          'unsupported_factor',
          'account_restricted',
        ]) {
          for (final state in ['legacy_active', 'blocked']) {
            final outcome = (access, step, reason, state);
            if (outcomes.contains(outcome)) continue;
            expect(
              () => AdmissionStatus.fromJson(
                wire(access: access, step: step, reason: reason, state: state),
              ),
              throwsFormatException,
              reason: '$outcome',
            );
            rejected++;
          }
        }
      }
    }
    expect(rejected, 111);
  });

  for (final value in <Object?>[
    null,
    true,
    1,
    'home',
    [],
    <String, dynamic>{},
  ]) {
    test('rejects non-object or empty response $value', () {
      expect(() => AdmissionStatus.fromJson(value), throwsFormatException);
    });
  }

  for (final key in wire().keys) {
    test('requires key $key even when its value can be null', () {
      final input = wire()..remove(key);
      expect(() => AdmissionStatus.fromJson(input), throwsFormatException);
    });
    test('rejects wrong type for $key', () {
      expect(
        () => AdmissionStatus.fromJson({...wire(), key: false}),
        throwsFormatException,
      );
    });
  }

  for (final key in ['provisioning_allowed', 'role', 'extra']) {
    test('rejects extra key $key', () {
      expect(
        () => AdmissionStatus.fromJson({...wire(), key: null}),
        throwsFormatException,
      );
    });
  }

  for (final value in <Object?>[
    null,
    '',
    ' ',
    'not-a-uuid',
    '11111111111111111111111111111111',
    '11111111-1111-1111-1111-11111111111g',
    '$subject\n',
    ' $subject',
  ]) {
    test('rejects malformed subject ${value.runtimeType}: $value', () {
      expect(
        () => AdmissionStatus.fromJson({...wire(), 'subject_id': value}),
        throwsFormatException,
      );
    });
  }

  for (final entry in <String, Object?>{
    'account_access': 'allowed',
    'next_step': 'account_recovery',
    'reason': 'deletion_pending',
    'account_state': 'active',
    'restore_until': '2026-10-30T00:00:00Z',
  }.entries) {
    test('rejects unknown or unimplemented ${entry.key}', () {
      expect(
        () => AdmissionStatus.fromJson({...wire(), entry.key: entry.value}),
        throwsFormatException,
      );
    });
  }

  for (final state in ['pending_deletion', 'finalization_due']) {
    test('does not infer admission for lifecycle $state', () {
      expect(
        () => AdmissionStatus.fromJson({...wire(), 'account_state': state}),
        throwsFormatException,
      );
    });
  }

  const pendingOutcomes = [
    ('verify_email', null),
    ('enroll_totp', null),
    ('challenge_totp', null),
    ('blocked', 'profile_missing'),
    ('blocked', 'role_unavailable'),
    ('blocked', 'unsupported_factor'),
    ('blocked', 'explicit_restore_required'),
    ('blocked', 'restore_expired'),
  ];
  for (final outcome in pendingOutcomes) {
    test('decodes pending prerequisite $outcome without granting access', () {
      final result = AdmissionStatus.fromJson({
        ...wire(
          access: 'restricted',
          step: outcome.$1,
          reason: outcome.$2,
          state: 'pending_deletion',
        ),
        'restore_until': '2026-12-29T06:39:23.123456+00:00',
      });
      expect(result.accountAccess, 'restricted');
      expect(result.nextStep, outcome.$1);
      expect(result.reason, outcome.$2);
      expect(
        result.restoreUntil,
        DateTime.utc(2026, 12, 29, 6, 39, 23, 123, 456),
      );
    });
  }
  for (final value in <Object?>[
    null,
    true,
    123,
    '',
    '2026-10-30',
    '2026-10-30T06:39:23',
    '2026-10-30T06:39:23-04:00',
    '2026-02-30T06:39:23Z',
    '2026-13-30T06:39:23Z',
    '2026-10-30T24:39:23Z',
    '2026-10-30T06:60:23Z',
    '2026-10-30T06:39:60Z',
    '2026-10-30T06:39:23.1234567Z',
    '2026-10-30T06:39:23Z\n',
  ]) {
    test('rejects invalid pending deadline $value', () {
      expect(
        () => AdmissionStatus.fromJson({
          ...wire(
            access: 'restricted',
            step: 'blocked',
            reason: 'explicit_restore_required',
            state: 'pending_deletion',
          ),
          'restore_until': value,
        }),
        throwsFormatException,
      );
    });
  }
  test('preserves a longer server deadline without clamping to 90 days', () {
    final result = AdmissionStatus.fromJson({
      ...wire(
        access: 'restricted',
        step: 'blocked',
        reason: 'explicit_restore_required',
        state: 'pending_deletion',
      ),
      'restore_until': '2099-01-01T00:00:00Z',
    });
    expect(result.restoreUntil, DateTime.utc(2099));
    expect(result.accountAccess, 'restricted');
  });

  test('pending deadline does not independently grant restoration', () {
    final result = AdmissionStatus.fromJson({
      ...wire(
        access: 'restricted',
        step: 'blocked',
        reason: 'restore_expired',
        state: 'pending_deletion',
      ),
      'restore_until': '2020-01-01T00:00:00Z',
    });
    expect(result.accountAccess, 'restricted');
    expect(result.restoreUntil, DateTime.utc(2020));
    expect(
      () => AdmissionStatus.fromJson({
        ...wire(state: 'pending_deletion'),
        'restore_until': '2026-10-30T06:39:23Z',
      }),
      throwsFormatException,
    );
  });

  test('does not retain the mutable response map', () {
    final input = wire(step: 'review_terms');
    final result = AdmissionStatus.fromJson(input);
    input['next_step'] = 'home';
    input['subject_id'] = '22222222-2222-2222-2222-222222222222';
    expect(result.nextStep, 'review_terms');
    expect(result.subjectId, subject);
  });
}
