import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../features/newsletter/fixtures.dart';

void main() {
  for (final state in [
    'not_subscribed',
    'pending',
    'expired',
    'subscribed',
    'unsubscribed',
    'suppressed',
  ]) {
    test('parses exact $state contract and UTC timestamps', () {
      final status = newsletter(state: state);
      expect(status.subjectId, subjectA);
      expect(status.consentVersion, 'synthetic-newsletter-v2');
      expect(status.requestedAt?.isUtc ?? true, isTrue);
    });
  }
  final invalid = <Object?>[
    null,
    [],
    {},
    {...newsletterWire(), 'extra': true},
    {...newsletterWire()}..remove('requested_at'),
    {...newsletterWire(), 'subject_id': ''},
    {...newsletterWire(), 'subject_id': '$subjectA\n'},
    {...newsletterWire(), 'state': 'enabled'},
    {...newsletterWire(), 'enabled': 'true'},
    {...newsletterWire(), 'consent_text': ' '},
    {...newsletterWire(), 'consent_version': 1},
    {...newsletterWire(state: 'pending'), 'requested_at': null},
    {...newsletterWire(state: 'subscribed'), 'confirmed_at': null},
    {...newsletterWire(), 'confirmed_at': '2026-09-30T01:00:00Z'},
    {
      ...newsletterWire(state: 'pending'),
      'requested_at': '2026-02-30T01:00:00Z',
    },
    {
      ...newsletterWire(state: 'pending'),
      'requested_at': '2026-09-30T01:00:00',
    },
    {
      ...newsletterWire(state: 'pending'),
      'requested_at': '2026-09-30T01:00:00-04:00',
    },
    {...newsletterWire(state: 'pending'), 'requested_at': true},
    {
      ...newsletterWire(state: 'subscribed'),
      'confirmed_at': '2026-09-29T01:00:00Z',
    },
  ];
  for (var i = 0; i < invalid.length; i++) {
    test('rejects malformed contract $i', () {
      expect(
        () => NewsletterStatus.fromJson(invalid[i]),
        throwsFormatException,
      );
    });
  }
}
