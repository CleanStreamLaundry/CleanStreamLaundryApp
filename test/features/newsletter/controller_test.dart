import 'dart:async';

import 'package:clean_stream_laundry_app/features/newsletter/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'fixtures.dart';

void main() {
  late NewsletterFixture fixture;
  late NewsletterController controller;
  setUp(() {
    fixture = NewsletterFixture();
    controller = NewsletterController(
      authService: fixture.auth,
      profileService: fixture.profile,
    );
  });
  tearDown(() async {
    controller.dispose();
    await fixture.events.close();
  });

  test(
    'unchecked is a no-op; explicit consent uses server version after admission',
    () async {
      await controller.refresh();
      await controller.request();
      verifyNever(() => fixture.profile.requestNewsletter(any()));
      controller.setConsent(true);
      await controller.request();
      expect(controller.status?.state, NewsletterState.pending);
      expect(controller.consent, isFalse);
      verifyInOrder([
        () => fixture.profile.getAdmissionStatus(),
        () => fixture.profile.requestNewsletter('synthetic-newsletter-v2'),
      ]);
    },
  );

  for (final next in ['review_terms', 'wrong_subject']) {
    test('admission $next prevents mutation', () async {
      when(() => fixture.profile.getAdmissionStatus()).thenAnswer(
        (_) async => admission(
          next: next == 'review_terms' ? next : 'home',
          subject: next == 'wrong_subject' ? subjectB : subjectA,
        ),
      );
      await controller.refresh();
      controller.setConsent(true);
      await controller.request();
      verifyNever(() => fixture.profile.requestNewsletter(any()));
      expect(controller.needsStatusCheck, isTrue);
      expect(controller.consent, isFalse);
    });
  }

  test('busy suppresses duplicate request, withdrawal and refresh', () async {
    final pending = Completer<AdmissionStatus>();
    when(
      () => fixture.profile.getAdmissionStatus(),
    ).thenAnswer((_) => pending.future);
    await controller.refresh();
    controller.setConsent(true);
    final work = controller.request();
    await controller.request();
    await controller.refresh();
    await controller.withdraw();
    pending.complete(admission());
    await work;
    verify(() => fixture.profile.getAdmissionStatus()).called(1);
    verify(() => fixture.profile.requestNewsletter(any())).called(1);
    verify(() => fixture.profile.getNewsletterStatus()).called(1);
  });

  for (final state in ['pending', 'subscribed']) {
    test('separate withdrawal works for $state even disabled', () async {
      when(
        () => fixture.profile.getNewsletterStatus(),
      ).thenAnswer((_) async => newsletter(state: state, enabled: false));
      await controller.refresh();
      expect(controller.canRequest, isFalse);
      await controller.withdraw();
      expect(controller.status?.state, NewsletterState.unsubscribed);
      verify(() => fixture.profile.withdrawNewsletter()).called(1);
      verifyNever(() => fixture.profile.requestNewsletter(any()));
    });
  }

  for (final state in ['suppressed', 'pending', 'subscribed']) {
    test('$state cannot enroll', () async {
      when(
        () => fixture.profile.getNewsletterStatus(),
      ).thenAnswer((_) async => newsletter(state: state));
      await controller.refresh();
      controller.setConsent(true);
      await controller.request();
      verifyNever(() => fixture.profile.requestNewsletter(any()));
    });
  }

  for (final withdraw in [false, true]) {
    for (final readFails in [false, true]) {
      test(
        'uncertain ${withdraw ? 'withdraw' : 'request'} reconciles read only, read fails=$readFails',
        () async {
          when(() => fixture.profile.getNewsletterStatus()).thenAnswer(
            (_) async =>
                newsletter(state: withdraw ? 'pending' : 'not_subscribed'),
          );
          await controller.refresh();
          controller.setConsent(true);
          when(
            () => fixture.profile.requestNewsletter(any()),
          ).thenThrow(TimeoutException('synthetic'));
          when(
            () => fixture.profile.withdrawNewsletter(),
          ).thenThrow(TimeoutException('synthetic'));
          when(() => fixture.profile.getNewsletterStatus()).thenAnswer((
            _,
          ) async {
            if (readFails) throw StateError('synthetic');
            return newsletter(state: withdraw ? 'unsubscribed' : 'pending');
          });
          await (withdraw ? controller.withdraw() : controller.request());
          expect(controller.needsStatusCheck, readFails);
          expect(controller.consent, isFalse);
          await controller.request();
          if (withdraw) {
            verify(() => fixture.profile.withdrawNewsletter()).called(1);
          } else {
            verify(() => fixture.profile.requestNewsletter(any())).called(1);
          }
          verify(() => fixture.profile.getNewsletterStatus()).called(2);
        },
      );
    }
  }

  test(
    'failed refresh preserves visible status but disables mutation',
    () async {
      await controller.refresh();
      final old = controller.status;
      controller.setConsent(true);
      when(
        () => fixture.profile.getNewsletterStatus(),
      ).thenThrow(StateError('offline'));
      await controller.refresh();
      expect(controller.status, same(old));
      expect(controller.canRequest, isFalse);
      expect(controller.consent, isFalse);
    },
  );

  test('server consent change resets checked intent', () async {
    await controller.refresh();
    controller.setConsent(true);
    when(() => fixture.profile.getNewsletterStatus()).thenAnswer(
      (_) async => NewsletterStatus.fromJson({
        ...newsletterWire(),
        'consent_text': 'New synthetic purpose',
      }),
    );
    await controller.refresh();
    expect(controller.consent, isFalse);
  });

  for (final phase in ['load', 'admission', 'mutation']) {
    for (final change in ['logout', 'B', 'A-B-A']) {
      test('$phase ignores late result after $change', () async {
        final pending = Completer<NewsletterStatus>();
        final access = Completer<AdmissionStatus>();
        await controller.refresh();
        controller.setConsent(true);
        if (phase == 'load') {
          when(
            () => fixture.profile.getNewsletterStatus(),
          ).thenAnswer((_) => pending.future);
        } else if (phase == 'admission') {
          when(
            () => fixture.profile.getAdmissionStatus(),
          ).thenAnswer((_) => access.future);
        } else {
          when(
            () => fixture.profile.requestNewsletter(any()),
          ).thenAnswer((_) => pending.future);
        }
        final work = phase == 'load'
            ? controller.refresh()
            : controller.request();
        await Future<void>.delayed(const Duration(milliseconds: 1));
        final original = fixture.session;
        fixture.change(
          change == 'logout' ? null : sessionFixture(id: subjectB),
        );
        if (change == 'A-B-A') fixture.change(original);
        pending.complete(newsletter(state: 'pending'));
        access.complete(admission());
        await work;
        expect(controller.status, isNull);
        expect(controller.consent, isFalse);
        expect(controller.busy, isFalse);
        if (phase == 'admission') {
          verifyNever(() => fixture.profile.requestNewsletter(any()));
        }
      });
    }
  }

  test('mismatched subject is never displayed', () async {
    when(
      () => fixture.profile.getNewsletterStatus(),
    ).thenAnswer((_) async => newsletter(subject: subjectB));
    await controller.refresh();
    expect(controller.status, isNull);
    expect(controller.needsStatusCheck, isTrue);
  });

  test('initial matching auth replay does not discard a status load', () async {
    final work = controller.refresh();
    fixture.change(fixture.session);
    await work;
    expect(controller.status?.subjectId, subjectA);
    fixture.change(fixture.session);
    expect(controller.status, isNull);
  });

  test(
    'auth stream failure stays closed even after repeated refresh',
    () async {
      await controller.refresh();
      fixture.events.addError(StateError('synthetic auth unavailable'));
      await controller.refresh();
      await controller.refresh();
      expect(controller.status, isNull);
      verify(() => fixture.profile.getNewsletterStatus()).called(1);
    },
  );

  test('expired session cannot read or mutate', () async {
    fixture.session = sessionFixture(seconds: -60);
    await controller.refresh();
    controller.setConsent(true);
    await controller.request();
    verifyZeroInteractions(fixture.profile);
  });
}
