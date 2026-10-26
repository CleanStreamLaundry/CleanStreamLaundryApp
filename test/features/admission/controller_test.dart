import 'dart:async';
import 'dart:io';

import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mocks.dart';

LoyaltyPolicyStatus policyFixture({
  String version = 'review-only-v1',
  bool accepted = false,
  bool changedText = false,
}) => LoyaltyPolicyStatus.fromJson({
  'required_version': version,
  'policy_text': changedText ? 'hello' : 'abc',
  'policy_sha256': changedText
      ? '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'
      : 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  'accepted_version': accepted ? version : null,
  'accepted_at': accepted ? '2030-01-01T00:00:00Z' : null,
  'acceptance_required': !accepted,
});

void main() {
  late MockAdmissionAuthService auth;
  late MockAdmissionProfileService profiles;
  late StreamController<AuthState> events;
  late AdmissionController controller;
  late DateTime now;
  Session? current;
  var listens = 0;
  var cancellations = 0;

  setUp(() {
    now = DateTime.utc(2030, 1, 1);
    current = admissionSession(expiresAt: now.add(const Duration(hours: 1)));
    auth = MockAdmissionAuthService();
    profiles = MockAdmissionProfileService();
    listens = 0;
    cancellations = 0;
    events = StreamController<AuthState>.broadcast(
      onListen: () => listens++,
      onCancel: () => cancellations++,
    );
    when(() => auth.currentSession).thenAnswer((_) => current);
    when(() => auth.authStateChanges).thenAnswer((_) => events.stream);
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) async => admissionStatus());
    controller = AdmissionController(
      authService: auth,
      profileService: profiles,
      now: () => now,
    );
  });

  tearDown(() async {
    controller.dispose();
    await events.close();
    verify(() => auth.currentSession).called(greaterThan(0));
    verify(() => auth.authStateChanges).called(1);
    verifyNoMoreInteractions(auth);
  });

  Future<void> emit(AuthChangeEvent event, Session? session) async {
    current = session;
    events.add(AuthState(event, session));
    await Future<void>.delayed(Duration.zero);
  }

  void expectClosed({bool retained = false}) {
    expect(controller.canEnterHome, isFalse);
    expect(controller.canUseMaintenance, isFalse);
    expect(controller.retainSafePresentation, retained);
  }

  test(
    'constructor owns one observer but performs no RPC or Auth mutation',
    () {
      expect(listens, 1);
      expect(controller.status, isNull);
      expect(controller.isChecking, isFalse);
      expectClosed();
      verifyZeroInteractions(profiles);
    },
  );

  group('explicit policy review', () {
    Future<void> review({bool consent = false}) async {
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) async => admissionStatus(step: 'review_terms'));
      when(
        () => profiles.getLoyaltyPolicyStatus(),
      ).thenAnswer((_) async => policyFixture());
      await controller.revalidate();
      await controller.loadPolicy();
      controller.setPolicyConsent(consent);
    }

    test('no status/consent means no protected policy call', () async {
      await controller.loadPolicy();
      await controller.acceptPolicy();
      controller.setPolicyConsent(true);
      expect(controller.policyConsent, isFalse);
      verifyZeroInteractions(profiles);
      await review();
      await controller.acceptPolicy();
      expect(controller.policyDescriptor?.policyText, 'abc');
      expect(controller.canAcceptPolicy, isFalse);
      verify(() => profiles.getAdmissionStatus()).called(1);
      verify(() => profiles.getLoyaltyPolicyStatus()).called(1);
      verifyNoMoreInteractions(profiles);
    });

    test(
      'one exact-version write and one admission recheck, not Home inference',
      () async {
        await review(consent: true);
        final pending = Completer<LoyaltyPolicyStatus>();
        when(
          () => profiles.acceptLoyaltyPolicy('review-only-v1'),
        ).thenAnswer((_) => pending.future);
        when(
          () => profiles.getAdmissionStatus(),
        ).thenAnswer((_) async => admissionStatus(step: 'challenge_totp'));
        final result = controller.acceptPolicy();
        expect(identical(result, controller.acceptPolicy()), isTrue);
        expect(controller.isAcceptingPolicy, isTrue);
        expect(controller.canAcceptPolicy, isFalse);
        pending.complete(policyFixture(accepted: true));
        await result;
        expect(controller.status?.nextStep, 'challenge_totp');
        expect(controller.canEnterHome, isFalse);
        verify(() => profiles.acceptLoyaltyPolicy('review-only-v1')).called(1);
        verify(() => profiles.getAdmissionStatus()).called(2);
        verify(() => profiles.getLoyaltyPolicyStatus()).called(1);
        verifyNoMoreInteractions(profiles);
      },
    );

    test('already accepted policy only rechecks admission', () async {
      await review();
      when(
        () => profiles.getLoyaltyPolicyStatus(),
      ).thenAnswer((_) async => policyFixture(accepted: true));
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) async => admissionStatus());
      await controller.loadPolicy();
      expect(controller.canEnterHome, isTrue);
      expect(controller.policyConsent, isFalse);
      verify(() => profiles.getLoyaltyPolicyStatus()).called(2);
      verify(() => profiles.getAdmissionStatus()).called(2);
      verifyNoMoreInteractions(profiles);
    });

    for (final result in [
      policyFixture(version: 'review-only-v2', accepted: true),
      policyFixture(changedText: true, accepted: true),
      policyFixture(),
    ]) {
      test(
        'reject mismatch ${result.requiredVersion}/${result.policyText}/${result.acceptanceRequired}',
        () async {
          await review(consent: true);
          when(
            () => profiles.acceptLoyaltyPolicy('review-only-v1'),
          ).thenAnswer((_) async => result);
          await controller.acceptPolicy();
          expect(controller.error, isFormatException);
          expectClosed();
          expect(controller.policyDescriptor, isNull);
          verify(() => profiles.getAdmissionStatus()).called(1);
        },
      );
    }

    for (final code in ['22023', 'PT503', 'PT401', 'PT403']) {
      test(
        '$code never retries acceptance and requires fresh review',
        () async {
          await review(consent: true);
          final error = PostgrestException(
            message: 'synthetic failure',
            code: code,
          );
          when(
            () => profiles.acceptLoyaltyPolicy('review-only-v1'),
          ).thenThrow(error);
          await controller.acceptPolicy();
          expect(controller.canAcceptPolicy, isFalse);
          expect(controller.policyConsent, isFalse);
          await controller.acceptPolicy();
          verify(
            () => profiles.acceptLoyaltyPolicy('review-only-v1'),
          ).called(1);
          verify(() => profiles.getAdmissionStatus()).called(1);
          if (code == '22023' || code == 'PT503') {
            expect(controller.policyError, same(error));
            expect(controller.policyDescriptor?.policyText, 'abc');
            await controller.loadPolicy();
            expect(controller.canConsentToPolicy, isTrue);
            expect(controller.canAcceptPolicy, isFalse);
          } else {
            expect(controller.error, same(error));
            expect(controller.policyDescriptor, isNull);
            expectClosed();
          }
        },
      );
    }

    for (final accept in [false, true]) {
      for (final responseFirst in [false, true]) {
        test(
          'policy accept=$accept drops A-B-A completion, responseFirst=$responseFirst',
          () async {
            await review(consent: true);
            final pending = Completer<LoyaltyPolicyStatus>();
            when(
              () => profiles.getLoyaltyPolicyStatus(),
            ).thenAnswer((_) => pending.future);
            when(
              () => profiles.acceptLoyaltyPolicy('review-only-v1'),
            ).thenAnswer((_) => pending.future);
            final result = accept
                ? controller.acceptPolicy()
                : controller.loadPolicy();
            if (responseFirst) {
              pending.complete(policyFixture(accepted: accept));
            }
            events.add(
              AuthState(
                AuthChangeEvent.signedIn,
                admissionSession(
                  id: accountB,
                  expiresAt: now.add(const Duration(hours: 1)),
                ),
              ),
            );
            events.add(AuthState(AuthChangeEvent.signedIn, current));
            if (!responseFirst) {
              pending.complete(policyFixture(accepted: accept));
            }
            await result;
            expect(controller.policyDescriptor, isNull);
            expect(controller.policyConsent, isFalse);
            expectClosed();
            verify(() => profiles.getAdmissionStatus()).called(1);
          },
        );
      }
    }

    for (final action in ['expiry', 'dismiss', 'dispose']) {
      test(
        '$action prevents late acceptance from starting admission',
        () async {
          await review(consent: true);
          final pending = Completer<LoyaltyPolicyStatus>();
          when(
            () => profiles.acceptLoyaltyPolicy('review-only-v1'),
          ).thenAnswer((_) => pending.future);
          final result = controller.acceptPolicy();
          if (action == 'expiry') now = now.add(const Duration(hours: 1));
          if (action == 'dismiss') controller.dismissPolicy();
          if (action == 'dispose') controller.dispose();
          pending.complete(policyFixture(accepted: true));
          await result;
          expect(controller.canAcceptPolicy, isFalse);
          verify(() => profiles.getAdmissionStatus()).called(1);
        },
      );
    }

    test(
      'silent switch before dispatch and soft refresh revoke consent',
      () async {
        await review(consent: true);
        current = admissionSession(
          id: accountB,
          expiresAt: now.add(const Duration(hours: 1)),
        );
        await controller.acceptPolicy();
        verifyNever(() => profiles.acceptLoyaltyPolicy(any()));
        await emit(
          AuthChangeEvent.tokenRefreshed,
          admissionSession(
            expiresAt: now.add(const Duration(hours: 2)),
            revision: 'renewed',
          ),
        );
        expect(controller.canAcceptPolicy, isFalse);
      },
    );

    testWidgets('ten-second policy wait ignores late write completion', (
      tester,
    ) async {
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) async => admissionStatus(step: 'review_terms'));
      final admission = controller.revalidate();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      await admission;
      when(
        () => profiles.getLoyaltyPolicyStatus(),
      ).thenAnswer((_) async => policyFixture());
      final load = controller.loadPolicy();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      await load;
      controller.setPolicyConsent(true);
      final pending = Completer<LoyaltyPolicyStatus>();
      when(
        () => profiles.acceptLoyaltyPolicy('review-only-v1'),
      ).thenAnswer((_) => pending.future);
      final result = controller.acceptPolicy();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 1));
      await result;
      expect(controller.policyError, isA<TimeoutException>());
      expect(controller.policyDescriptor?.policyText, 'abc');
      expect(controller.canAcceptPolicy, isFalse);
      pending.complete(policyFixture(accepted: true));
      await tester.pump();
      verify(() => profiles.acceptLoyaltyPolicy('review-only-v1')).called(1);
      verify(() => profiles.getAdmissionStatus()).called(1);
      controller.dispose();
    });
  });

  for (final entry in <(String, String?)>[
    ('home', null),
    ('review_terms', null),
    ('verify_email', null),
    ('enroll_totp', null),
    ('challenge_totp', null),
    ('blocked', 'profile_missing'),
    ('blocked', 'role_unavailable'),
    ('blocked', 'unsupported_factor'),
    ('blocked', 'account_restricted'),
  ]) {
    test(
      'models canonical ${entry.$1}/${entry.$2} without extra calls',
      () async {
        final status = admissionStatus(step: entry.$1, reason: entry.$2);
        when(
          () => profiles.getAdmissionStatus(),
        ).thenAnswer((_) async => status);
        await controller.revalidate();
        expect(controller.status, same(status));
        expect(controller.canEnterHome, entry.$1 == 'home');
        expect(
          controller.canUseMaintenance,
          ['home', 'review_terms'].contains(entry.$1),
        );
        expect(controller.retainSafePresentation, entry.$1 == 'home');
        expect(
          controller.canUseTopupRefunds,
          ['home', 'review_terms'].contains(entry.$1),
        );
        verify(() => profiles.getAdmissionStatus()).called(1);
        verifyNoMoreInteractions(profiles);
      },
    );
  }

  for (final reason in ['explicit_restore_required', 'restore_expired']) {
    test('pending deletion allows refunds only: $reason', () async {
      final status = AdmissionStatus.fromJson({
        'subject_id': accountA,
        'account_access': 'restricted',
        'next_step': 'blocked',
        'reason': reason,
        'account_state': 'pending_deletion',
        'restore_until': '2030-01-31T00:00:00Z',
      });
      when(() => profiles.getAdmissionStatus()).thenAnswer((_) async => status);
      await controller.revalidate();
      expect(controller.canUseTopupRefunds, isTrue);
      expect(controller.canEnterHome, isFalse);
      expect(controller.canUseMaintenance, isFalse);

      final response = Completer<AdmissionStatus>();
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) => response.future);
      final checking = controller.revalidate();
      expect(controller.canUseTopupRefunds, isFalse);
      expect(controller.retainSafePresentation, isTrue);
      response.complete(status);
      await checking;
      expect(controller.canUseTopupRefunds, isTrue);
      await emit(AuthChangeEvent.signedOut, null);
      expect(controller.canUseTopupRefunds, isFalse);
      expect(controller.retainSafePresentation, isFalse);
    });
  }

  for (final kind in [
    'missing',
    'empty user',
    'empty bearer',
    'missing expiry',
    'expired',
    'near expiry',
  ]) {
    test('$kind snapshot never dispatches admission', () async {
      current = switch (kind) {
        'missing' => null,
        'empty user' => admissionSession(
          expiresAt: now.add(const Duration(hours: 1)),
          id: '',
        ),
        'empty bearer' => current!.copyWith(accessToken: ''),
        'missing expiry' => current!.copyWith(
          accessToken: 'synthetic-malformed',
        ),
        'expired' => admissionSession(
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ),
        _ => admissionSession(expiresAt: now.add(const Duration(seconds: 20))),
      };
      await controller.revalidate();
      expectClosed();
      expect(controller.status, isNull);
      verifyZeroInteractions(profiles);
    });
  }

  test('duplicate explicit checks share one bounded request', () async {
    final result = Completer<AdmissionStatus>();
    when(() => profiles.getAdmissionStatus()).thenAnswer((_) => result.future);
    final first = controller.revalidate();
    final second = controller.revalidate();
    expect(identical(first, second), isTrue);
    expect(controller.isChecking, isTrue);
    expectClosed();
    result.complete(admissionStatus());
    await first;
    expect(controller.canEnterHome, isTrue);
    verify(() => profiles.getAdmissionStatus()).called(1);
  });

  test('initial-session replay does not discard an explicit check', () async {
    final pending = controller.revalidate();
    events.add(AuthState(AuthChangeEvent.initialSession, current));
    await pending;
    expect(controller.canEnterHome, isTrue);
    verify(() => profiles.getAdmissionStatus()).called(1);
  });

  test('soft revalidation retains presentation but no reads/actions', () async {
    await controller.revalidate();
    final generation = controller.generation;
    final pending = Completer<AdmissionStatus>();
    when(() => profiles.getAdmissionStatus()).thenAnswer((_) => pending.future);
    final result = controller.revalidate();
    expectClosed(retained: true);
    expect(controller.generation, greaterThan(generation));
    pending.complete(admissionStatus());
    await result;
    expect(controller.canEnterHome, isTrue);
  });

  for (final event in [
    AuthChangeEvent.tokenRefreshed,
    AuthChangeEvent.mfaChallengeVerified,
    AuthChangeEvent.userUpdated,
  ]) {
    test(
      '$event keeps same-account presentation but never auto-checks',
      () async {
        await controller.revalidate();
        await emit(
          event,
          admissionSession(
            expiresAt: now.add(const Duration(hours: 2)),
            revision: 'renewed',
          ),
        );
        expectClosed(retained: true);
        expect(controller.status, isNull);
        verify(() => profiles.getAdmissionStatus()).called(1);
        await controller.revalidate();
        expect(controller.canEnterHome, isTrue);
        verify(() => profiles.getAdmissionStatus()).called(1);
      },
    );
  }

  for (final error in <Object>[
    TimeoutException('synthetic timeout'),
    const SocketException('synthetic offline'),
    const PostgrestException(message: 'synthetic unavailable', code: 'PT503'),
    AuthRetryableFetchException(
      message: 'synthetic offline',
      statusCode: '503',
    ),
  ]) {
    test(
      '${error.runtimeType} retains only previously admitted presentation',
      () async {
        await controller.revalidate();
        when(
          () => profiles.getAdmissionStatus(),
        ).thenAnswer((_) => Future.error(error));
        await controller.revalidate();
        expect(controller.error, same(error));
        expectClosed(retained: true);
        expect(controller.isChecking, isFalse);
        verify(() => profiles.getAdmissionStatus()).called(2);
      },
    );
  }

  for (final error in <Object>[
    const AuthException('synthetic invalid session', statusCode: '401'),
    const PostgrestException(message: 'synthetic invalid', code: 'PT401'),
    const PostgrestException(message: 'synthetic restricted', code: 'PT403'),
    const FormatException('synthetic malformed response'),
  ]) {
    test('${error.runtimeType} $error clears previous presentation', () async {
      await controller.revalidate();
      when(() => profiles.getAdmissionStatus()).thenThrow(error);
      await controller.revalidate();
      expect(controller.error, same(error));
      expectClosed();
    });
  }

  test(
    'first-check error cannot create a presentation grant; explicit retry can',
    () async {
      const error = SocketException('synthetic offline');
      when(() => profiles.getAdmissionStatus()).thenThrow(error);
      await controller.revalidate();
      expectClosed();
      expect(controller.error, same(error));
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) async => admissionStatus());
      await controller.revalidate();
      expect(controller.error, isNull);
      expect(controller.canEnterHome, isTrue);
    },
  );

  for (final step in [
    'review_terms',
    'verify_email',
    'enroll_totp',
    'challenge_totp',
    'blocked',
  ]) {
    test('fresh $step replaces Home and removes cached presentation', () async {
      await controller.revalidate();
      when(() => profiles.getAdmissionStatus()).thenAnswer(
        (_) async => admissionStatus(
          step: step,
          reason: step == 'blocked' ? 'account_restricted' : null,
        ),
      );
      await controller.revalidate();
      expect(controller.canEnterHome, isFalse);
      expect(controller.canUseMaintenance, step == 'review_terms');
      expect(controller.retainSafePresentation, isFalse);
    });
  }

  test(
    'wrong-subject response fails closed even after prior admission',
    () async {
      await controller.revalidate();
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) async => admissionStatus(id: accountB));
      await controller.revalidate();
      expectClosed();
      expect(controller.error, isStateError);
    },
  );

  for (final failure in [false, true]) {
    for (final responseFirst in [false, true]) {
      test(
        'A-B-A rejects stale ${failure ? 'error' : 'success'}, responseFirst=$responseFirst',
        () async {
          await controller.revalidate();
          final pending = Completer<AdmissionStatus>();
          when(
            () => profiles.getAdmissionStatus(),
          ).thenAnswer((_) => pending.future);
          final result = controller.revalidate();
          final a = current;
          void complete() => failure
              ? pending.completeError(
                  const PostgrestException(
                    message: 'synthetic stale',
                    code: 'PT401',
                  ),
                )
              : pending.complete(admissionStatus());
          if (responseFirst) complete();
          events.add(
            AuthState(
              AuthChangeEvent.signedIn,
              admissionSession(
                id: accountB,
                expiresAt: now.add(const Duration(hours: 1)),
              ),
            ),
          );
          current = a;
          events.add(AuthState(AuthChangeEvent.signedIn, a));
          if (!responseFirst) complete();
          await result;
          expectClosed();
          expect(controller.status, isNull);
          expect(controller.error, isNull);
        },
      );
    }
  }

  test(
    'new explicit generation coalesces behind stale in-flight work',
    () async {
      final first = Completer<AdmissionStatus>();
      var count = 0;
      when(() => profiles.getAdmissionStatus()).thenAnswer((_) {
        count++;
        return count == 1
            ? first.future
            : Future.value(admissionStatus(id: accountB));
      });
      final a = controller.revalidate();
      await emit(
        AuthChangeEvent.signedIn,
        admissionSession(
          id: accountB,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      final b = controller.revalidate();
      final duplicate = controller.revalidate();
      expect(identical(a, b), isTrue);
      expect(identical(b, duplicate), isTrue);
      expect(count, 1);
      first.complete(admissionStatus());
      await b;
      expect(count, 2);
      expect(controller.status?.subjectId, accountB);
      expect(controller.canEnterHome, isTrue);
    },
  );

  for (final event in AuthChangeEvent.values.where(
    (event) => !const [
      AuthChangeEvent.initialSession,
      AuthChangeEvent.tokenRefreshed,
      AuthChangeEvent.userUpdated,
      AuthChangeEvent.mfaChallengeVerified,
    ].contains(event),
  )) {
    test('$event clears immediately without a status call', () async {
      await controller.revalidate();
      await emit(event, event == AuthChangeEvent.signedOut ? null : current);
      expectClosed();
      expect(controller.status, isNull);
      verify(() => profiles.getAdmissionStatus()).called(1);
    });
  }

  test(
    'stream offline error is handled and keeps safe same-account presentation',
    () async {
      await controller.revalidate();
      final error = AuthRetryableFetchException(message: 'synthetic offline');
      events.addError(error);
      await Future<void>.delayed(Duration.zero);
      expect(controller.error, same(error));
      expectClosed(retained: true);
      verify(() => profiles.getAdmissionStatus()).called(1);
    },
  );

  test(
    'stream closure clears admission and refuses checks without observation',
    () async {
      await controller.revalidate();
      await events.close();
      expectClosed();
      await controller.revalidate();
      verify(() => profiles.getAdmissionStatus()).called(1);
    },
  );

  test(
    'explicit hard invalidation prevents pending result resurrection',
    () async {
      await controller.revalidate();
      final pending = Completer<AdmissionStatus>();
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) => pending.future);
      final result = controller.revalidate();
      controller.invalidate();
      expectClosed();
      pending.complete(admissionStatus());
      await result;
      expectClosed();
      expect(controller.status, isNull);
    },
  );

  test(
    'silent session mismatch closes presentation before an Auth event',
    () async {
      await controller.revalidate();
      current = admissionSession(
        id: accountB,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      expectClosed();
      expect(controller.status, isNull);
      verify(() => profiles.getAdmissionStatus()).called(1);
    },
  );

  test(
    'expired prior session cannot retain presentation through refresh',
    () async {
      await controller.revalidate();
      now = now.add(const Duration(hours: 1));
      await emit(
        AuthChangeEvent.tokenRefreshed,
        admissionSession(
          expiresAt: now.add(const Duration(hours: 1)),
          revision: 'after-expiry',
        ),
      );
      expectClosed();
      verify(() => profiles.getAdmissionStatus()).called(1);
    },
  );

  test(
    'stream rejection invalidates an outstanding successful response',
    () async {
      await controller.revalidate();
      final pending = Completer<AdmissionStatus>();
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) => pending.future);
      final result = controller.revalidate();
      const error = AuthException('synthetic revoked', statusCode: '401');
      events.addError(error);
      pending.complete(admissionStatus());
      await result;
      expectClosed();
      expect(controller.error, same(error));
    },
  );

  test(
    'maintenance permission is not cached during terms revalidation',
    () async {
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) async => admissionStatus(step: 'review_terms'));
      await controller.revalidate();
      expect(controller.canUseMaintenance, isTrue);
      final pending = Completer<AdmissionStatus>();
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) => pending.future);
      final result = controller.revalidate();
      expectClosed();
      pending.complete(admissionStatus(step: 'challenge_totp'));
      await result;
      expectClosed();
    },
  );

  for (final failure in [false, true]) {
    test(
      'disposal cancels observer and ignores late completion: $failure',
      () async {
        final pending = Completer<AdmissionStatus>();
        when(
          () => profiles.getAdmissionStatus(),
        ).thenAnswer((_) => pending.future);
        var changes = 0;
        controller.addListener(() => changes++);
        final result = controller.revalidate();
        controller.dispose();
        final afterDispose = changes;
        expect(controller.isChecking, isFalse);
        expectClosed();
        expect(cancellations, 1);
        if (failure) {
          pending.completeError(const SocketException('synthetic late'));
        } else {
          pending.complete(admissionStatus());
        }
        await result;
        await controller.revalidate();
        expect(changes, afterDispose);
        verify(() => profiles.getAdmissionStatus()).called(1);
      },
    );
  }

  for (final lateFailure in [false, true]) {
    testWidgets(
      'ten-second wait closes actions and ignores late result: $lateFailure',
      (tester) async {
        final pending = Completer<AdmissionStatus>();
        when(
          () => profiles.getAdmissionStatus(),
        ).thenAnswer((_) => pending.future);
        final result = controller.revalidate();
        await tester.pump(const Duration(milliseconds: 9999));
        expect(controller.isChecking, isTrue);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        await result;
        expect(controller.error, isA<TimeoutException>());
        expectClosed();
        if (lateFailure) {
          pending.completeError(const SocketException('synthetic late'));
        } else {
          pending.complete(admissionStatus());
        }
        await tester.pump();
        expectClosed();
        verify(() => profiles.getAdmissionStatus()).called(1);
        expect(tester.takeException(), isNull);
        controller.dispose();
      },
    );
  }

  testWidgets(
    'expiry is a single invalidation, not polling, and dispose cancels it',
    (tester) async {
      // Re-arm inside the widget test's fake timer zone.
      current = admissionSession(
        expiresAt: now.add(const Duration(seconds: 60)),
        revision: 'short',
      );
      final result = controller.revalidate();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      await result;
      expect(controller.canEnterHome, isTrue);
      now = now.add(const Duration(seconds: 29));
      await tester.pump(const Duration(seconds: 29));
      expect(controller.canEnterHome, isTrue);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expectClosed();
      expect(controller.status, isNull);
      await tester.pump(const Duration(hours: 1));
      verify(() => profiles.getAdmissionStatus()).called(1);
      controller.dispose();
      expect(cancellations, 1);
    },
  );

  testWidgets(
    'explicit retry after hard invalidation re-arms expiry notification',
    (tester) async {
      current = admissionSession(
        expiresAt: now.add(const Duration(seconds: 60)),
        revision: 'retry-expiry',
      );
      controller.invalidate();
      final result = controller.revalidate();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      await result;
      controller.invalidate();
      final retry = controller.revalidate();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      await retry;
      final generation = controller.generation;
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(controller.generation, generation + 1);
      expectClosed();
      verify(() => profiles.getAdmissionStatus()).called(2);
    },
  );

  testWidgets('refresh replaces old expiry and disposal cancels new expiry', (
    tester,
  ) async {
    current = admissionSession(
      expiresAt: now.add(const Duration(seconds: 60)),
      revision: 'old-expiry',
    );
    final result = controller.revalidate();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await result;
    now = now.add(const Duration(seconds: 29));
    await tester.pump(const Duration(seconds: 29));
    current = admissionSession(
      expiresAt: now.add(const Duration(hours: 1)),
      revision: 'new-expiry',
    );
    events.add(AuthState(AuthChangeEvent.tokenRefreshed, current));
    await tester.pump();
    expectClosed(retained: true);
    final generation = controller.generation;
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.generation, generation);
    expectClosed(retained: true);
    var changes = 0;
    controller.addListener(() => changes++);
    controller.dispose();
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    expect(changes, 0);
    expect(cancellations, 1);
    verify(() => profiles.getAdmissionStatus()).called(1);
  });

  test(
    'DI registration is lazy, shares existing services and disposes its controller',
    () {
      final source = File('lib/core/di/di.dart').readAsStringSync();
      expect(
        RegExp(
          r'registerLazySingleton<AdmissionController>',
        ).allMatches(source).length,
        1,
      );
      expect(source, contains('authService: getIt<AuthService>()'));
      expect(source, contains('profileService: getIt<ProfileService>()'));
      expect(source, contains('dispose: (controller) => controller.dispose()'));
      expect(source, isNot(contains('.revalidate(')));
      verifyZeroInteractions(profiles);
    },
  );
}
