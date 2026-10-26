import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const subjectA = '11111111-1111-1111-1111-111111111111';
const subjectB = '22222222-2222-2222-2222-222222222222';

Map<String, dynamic> newsletterWire({
  String state = 'not_subscribed',
  String subject = subjectA,
  bool enabled = true,
}) => {
  'subject_id': subject,
  'state': state,
  'requested_at': ['not_subscribed', 'suppressed'].contains(state)
      ? null
      : '2026-09-30T01:00:00+00:00',
  'confirmed_at': state == 'subscribed' ? '2026-09-30T01:01:00Z' : null,
  'unsubscribed_at': state == 'unsubscribed'
      ? '2026-09-30T01:02:00.123456Z'
      : null,
  'consent_version': 'synthetic-newsletter-v2',
  'consent_text': 'Synthetic newsletter purpose consent. You may unsubscribe.',
  'enabled': enabled,
};

NewsletterStatus newsletter({
  String state = 'not_subscribed',
  String subject = subjectA,
  bool enabled = true,
}) => NewsletterStatus.fromJson(
  newsletterWire(state: state, subject: subject, enabled: enabled),
);

Session sessionFixture({String id = subjectA, int seconds = 3600}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return Session(
    accessToken:
        '${part({'alg': 'HS256'})}.${part({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds})}.synthetic',
    tokenType: 'bearer',
    user: User(
      id: id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '',
    ),
  );
}

AdmissionStatus admission({String subject = subjectA, String next = 'home'}) =>
    AdmissionStatus.fromJson({
      'subject_id': subject,
      'account_access': 'eligible',
      'next_step': next,
      'reason': null,
      'account_state': 'legacy_active',
      'restore_until': null,
    });

class NewsletterAuth extends Mock implements AuthService {}

class NewsletterProfile extends Mock implements ProfileService {}

class NewsletterFixture {
  final auth = NewsletterAuth();
  final profile = NewsletterProfile();
  final events = StreamController<AuthState>.broadcast(sync: true);
  Session? session = sessionFixture();

  NewsletterFixture() {
    when(() => auth.currentSession).thenAnswer((_) => session);
    when(() => auth.getCurrentUserId).thenAnswer((_) => session?.user.id);
    when(() => auth.authStateChanges).thenAnswer((_) => events.stream);
    when(
      () => profile.getAdmissionStatus(),
    ).thenAnswer((_) async => admission());
    when(
      () => profile.getNewsletterStatus(),
    ).thenAnswer((_) async => newsletter());
    when(
      () => profile.requestNewsletter(any()),
    ).thenAnswer((_) async => newsletter(state: 'pending'));
    when(
      () => profile.withdrawNewsletter(),
    ).thenAnswer((_) async => newsletter(state: 'unsubscribed'));
  }

  void change(Session? value) {
    session = value;
    events.add(
      AuthState(
        value == null ? AuthChangeEvent.signedOut : AuthChangeEvent.signedIn,
        value,
      ),
    );
  }
}
