import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/admission/admission.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/features/admission/gate.dart';
import 'package:clean_stream_laundry_app/features/loading/widgets/logo.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mocks.dart';

LoyaltyPolicyStatus policy({bool accepted = false, String text = 'abc'}) =>
    LoyaltyPolicyStatus.fromJson({
      'required_version': 'review-only-v1',
      'policy_text': text,
      'policy_sha256': sha256.convert(utf8.encode(text)).toString(),
      'accepted_version': accepted ? 'review-only-v1' : null,
      'accepted_at': accepted ? '2030-01-01T00:00:00Z' : null,
      'acceptance_required': !accepted,
    });

void main() {
  late MockAdmissionAuthService auth;
  late MockAdmissionProfileService profiles;
  late StreamController<AuthState> events;
  late AdmissionController controller;
  Session? session;
  var subscriptionCount = 1;
  final now = DateTime.utc(2030, 1, 1);

  setUp(() {
    subscriptionCount = 1;
    auth = MockAdmissionAuthService();
    profiles = MockAdmissionProfileService();
    events = StreamController<AuthState>.broadcast();
    session = admissionSession(expiresAt: now.add(const Duration(hours: 1)));
    when(() => auth.currentSession).thenAnswer((_) => session);
    when(() => auth.authStateChanges).thenAnswer((_) => events.stream);
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) async => admissionStatus(step: 'review_terms'));
    when(
      () => profiles.getLoyaltyPolicyStatus(),
    ).thenAnswer((_) async => policy());
    controller = AdmissionController(
      authService: auth,
      profileService: profiles,
      now: () => now,
    );
  });

  void pageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await events.close();
        verify(() => auth.currentSession).called(greaterThan(0));
        verify(() => auth.authStateChanges).called(subscriptionCount);
        verifyNoMoreInteractions(auth);
      }
    });
  }

  Future<void> mount(
    WidgetTester tester, {
    ThemeData? theme,
    double scale = 1,
    bool boldText = false,
    Key? boundary,
    Future<void> Function()? onRestore,
    VoidCallback? onSignInAgain,
    VoidCallback? onContactSupport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? lightMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale), boldText: boldText),
          child: child!,
        ),
        home: RepaintBoundary(
          key: boundary,
          child: AdmissionPage(
            controller: controller,
            onRestore: onRestore,
            onSignInAgain: onSignInAgain,
            onContactSupport: onContactSupport,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> load(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Check account access'));
    await tester.pumpAndSettle();
  }

  void pendingStatus({
    String step = 'blocked',
    String? reason = 'explicit_restore_required',
    String deadline = '2099-01-02T03:04:05.123456Z',
  }) {
    when(() => profiles.getAdmissionStatus()).thenAnswer(
      (_) async => AdmissionStatus.fromJson({
        'subject_id': accountA,
        'account_access': 'restricted',
        'next_step': step,
        'reason': reason,
        'account_state': 'pending_deletion',
        'restore_until': deadline,
      }),
    );
  }

  Future<void> checkAccess(WidgetTester tester) async {
    await tester.ensureVisible(find.byTooltip('Check account access'));
    await tester.tap(find.byTooltip('Check account access'));
    await tester.pumpAndSettle();
  }

  FilledButton restoreButton(WidgetTester tester) =>
      tester.widget<FilledButton>(
        find.byWidgetPredicate((widget) => widget is FilledButton),
      );

  for (final theme in [lightMode, darkMode]) {
    for (final outcome in ['error', 'restriction']) {
      pageTest(
        '${theme.brightness.name} unresolved check shows logo until $outcome',
        (tester) async {
          final response = Completer<AdmissionStatus>();
          when(
            () => profiles.getAdmissionStatus(),
          ).thenAnswer((_) => response.future);
          final check = controller.revalidate();
          var signs = 0;
          var support = 0;
          await mount(
            tester,
            theme: theme,
            onSignInAgain: () => signs++,
            onContactSupport: () => support++,
          );
          expect(controller.status, isNull);
          expect(controller.isChecking, isTrue);
          expect(controller.canEnterHome, isFalse);
          expect(find.byType(Logo), findsOneWidget);
          expect(
            tester
                .widget<Material>(
                  find
                      .ancestor(
                        of: find.byType(Logo),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .color,
            theme.colorScheme.surface,
          );
          expect(find.text('Account access'), findsNothing);
          expect(find.text('Checking account access.'), findsNothing);
          expect(find.text('Sign in again'), findsNothing);
          expect(find.text('Contact support'), findsNothing);
          expect(find.byTooltip('Check account access'), findsNothing);
          // The existing logo loops, so inspect pending frames without settling.
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byType(Logo), findsOneWidget);
          expect(find.text('Account access'), findsNothing);

          if (outcome == 'error') {
            response.completeError(Exception('SECRET admission failure'));
          } else {
            response.complete(
              admissionStatus(step: 'blocked', reason: 'account_restricted'),
            );
          }
          await tester.pumpAndSettle();
          await check;
          expect(controller.isChecking, isFalse);
          expect(controller.canEnterHome, isFalse);
          expect(find.byType(Logo), findsNothing);
          expect(find.text('Account access'), findsOneWidget);
          expect(
            find.text(
              outcome == 'error'
                  ? 'Unable to confirm account access. Please try again.'
                  : 'Account access is unavailable.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('SECRET'), findsNothing);
          expect(
            tester
                .widget<IconButton>(
                  find.ancestor(
                    of: find.byTooltip('Check account access'),
                    matching: find.byType(IconButton),
                  ),
                )
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.text('Sign in again'));
          await tester.tap(find.text('Contact support'));
          expect(signs, 1);
          expect(support, 1);
          verify(() => profiles.getAdmissionStatus()).called(1);
          verifyNoMoreInteractions(profiles);
        },
      );
    }

    pageTest(
      '${theme.brightness.name} cold gate waits for ready and retains known content',
      (tester) async {
        final response = Completer<AdmissionStatus>();
        when(
          () => profiles.getAdmissionStatus(),
        ).thenAnswer((_) => response.future);
        var builds = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: AdmissionGate(
              controller: controller,
              auth: auth,
              profiles: profiles,
              location: '/homePage',
              child: Builder(
                builder: (_) {
                  builds++;
                  return const Text('Protected home');
                },
              ),
            ),
          ),
        );
        expect(controller.status, isNull);
        expect(controller.isChecking, isTrue);
        expect(find.byType(Logo), findsOneWidget);
        expect(find.text('Account access'), findsNothing);
        expect(find.text('Protected home'), findsNothing);
        expect(builds, 0);
        response.complete(admissionStatus());
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.text('Account access'), findsNothing);
          expect(find.text('Your account is ready.'), findsNothing);
          if (controller.canEnterHome) break;
        }
        expect(controller.canEnterHome, isTrue);
        expect(find.text('Protected home'), findsOneWidget);
        expect(find.byType(AdmissionPage), findsNothing);
        expect(find.text('Your account is ready.'), findsNothing);
        await tester.pumpAndSettle();

        final refresh = Completer<AdmissionStatus>();
        when(
          () => profiles.getAdmissionStatus(),
        ).thenAnswer((_) => refresh.future);
        final check = controller.revalidate();
        await tester.pump();
        expect(find.text('Protected home'), findsOneWidget);
        expect(find.byType(Logo), findsNothing);
        expect(
          tester
              .widget<AbsorbPointer>(
                find
                    .ancestor(
                      of: find.text('Protected home'),
                      matching: find.byType(AbsorbPointer),
                    )
                    .first,
              )
              .absorbing,
          isTrue,
        );
        refresh.complete(
          admissionStatus(step: 'blocked', reason: 'account_restricted'),
        );
        await tester.pumpAndSettle();
        await check;
        expect(find.text('Protected home'), findsNothing);
        expect(find.byType(Logo), findsNothing);
        expect(find.text('Account access is unavailable.'), findsOneWidget);
        expect(find.text('Sign in again'), findsOneWidget);
        expect(find.text('Contact support'), findsOneWidget);
        verify(() => profiles.getAdmissionStatus()).called(2);
        verifyNoMoreInteractions(profiles);
      },
    );
  }

  for (final previous in ['terms', 'error']) {
    pageTest('recheck preserves displayed $previous without allowing access', (
      tester,
    ) async {
      if (previous == 'error') {
        when(
          () => profiles.getAdmissionStatus(),
        ).thenThrow(Exception('offline'));
      }
      await mount(tester, onSignInAgain: () {}, onContactSupport: () {});
      await checkAccess(tester);
      if (previous == 'terms') {
        expect(find.text('abc'), findsOneWidget);
      }
      final response = Completer<AdmissionStatus>();
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) => response.future);
      if (previous == 'terms') {
        expect(find.byTooltip('Check account access'), findsNothing);
        unawaited(controller.revalidate());
      } else {
        await tester.tap(find.byTooltip('Check account access'));
      }
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.isChecking, isTrue);
      expect(controller.canEnterHome, isFalse);
      expect(controller.canAcceptPolicy, isFalse);
      expect(find.byType(Logo), findsNothing);
      expect(
        find.text(previous == 'terms' ? 'Loyalty terms' : 'Account access'),
        findsOneWidget,
      );
      if (previous == 'terms') {
        expect(find.byTooltip('Back to login'), findsOneWidget);
        expect(find.text('Contact support'), findsNothing);
      } else {
        expect(find.text('Sign in again'), findsOneWidget);
        expect(find.text('Contact support'), findsOneWidget);
      }
      if (previous == 'terms') expect(find.text('abc'), findsOneWidget);
      if (previous == 'terms') {
        expect(find.byTooltip('Check account access'), findsNothing);
      } else {
        expect(
          tester
              .widget<IconButton>(
                find.ancestor(
                  of: find.byTooltip('Check account access'),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNull,
        );
      }
      response.complete(
        admissionStatus(step: 'blocked', reason: 'account_restricted'),
      );
      await tester.pumpAndSettle();
      expect(controller.canEnterHome, isFalse);
      expect(find.text('Account access is unavailable.'), findsOneWidget);
    });
  }

  pageTest('pending recovery is inert and requires configured callbacks', (
    tester,
  ) async {
    pendingStatus();
    await mount(tester);
    verifyZeroInteractions(profiles);
    await checkAccess(tester);
    expect(restoreButton(tester).onPressed, isNull);
    expect(find.textContaining('2099-01-02T03:04:05.123456Z'), findsOneWidget);
    expect(find.textContaining('(local time)'), findsOneWidget);
    expect(find.text('Sign in again'), findsNothing);
    expect(find.text('Contact support'), findsNothing);
    var signs = 0;
    var support = 0;
    await mount(
      tester,
      onSignInAgain: () => signs++,
      onContactSupport: () => support++,
    );
    await tester.tap(find.text('Sign in again'));
    await tester.tap(find.text('Contact support'));
    expect(signs, 1);
    expect(support, 1);
  });

  for (final step in ['verify_email', 'enroll_totp', 'challenge_totp']) {
    pageTest('pending $step retains prerequisites without restoration', (
      tester,
    ) async {
      pendingStatus(step: step, reason: null);
      var calls = 0;
      await mount(
        tester,
        onRestore: () async {
          calls++;
        },
      );
      await checkAccess(tester);
      expect(find.textContaining('pending deletion'), findsOneWidget);
      expect(find.text('Restore account'), findsNothing);
      expect(calls, 0);
      expect(
        find.textContaining(
          step == 'verify_email'
              ? 'Email verification'
              : step == 'enroll_totp'
              ? 'Authenticator setup'
              : 'An authenticator code',
        ),
        findsOneWidget,
      );
    });
  }

  for (final reason in ['restore_expired']) {
    pageTest('$reason past deadline never claims deletion or offers restore', (
      tester,
    ) async {
      pendingStatus(reason: reason, deadline: '2000-01-01T00:00:00Z');
      await mount(
        tester,
        onRestore: () async {
          fail('Must not restore');
        },
      );
      await checkAccess(tester);
      expect(
        find.textContaining(
          'does not confirm that the account has been deleted',
        ),
        findsOneWidget,
      );
      expect(find.text('Restore account'), findsNothing);
    });
  }

  pageTest('server explicit restore remains actionable past local deadline', (
    tester,
  ) async {
    pendingStatus(deadline: '2000-01-01T00:00:00Z');
    await mount(
      tester,
      onRestore: () async {
        fail('Presentation test must not dispatch restoration');
      },
    );
    await checkAccess(tester);
    expect(restoreButton(tester).onPressed, isNotNull);
    expect(find.textContaining('2000-01-01T00:00:00.000Z'), findsOneWidget);
    expect(find.textContaining('The recovery window has ended'), findsNothing);
    verify(() => profiles.getAdmissionStatus()).called(1);
    verifyNoMoreInteractions(profiles);
  });

  pageTest(
    'duplicate restoration blocked; unknown outcome requires successful status check',
    (tester) async {
      pendingStatus();
      final result = Completer<void>();
      var calls = 0;
      await mount(
        tester,
        onRestore: () {
          calls++;
          return result.future;
        },
      );
      await checkAccess(tester);
      final press = restoreButton(tester).onPressed!;
      press();
      press();
      await tester.pump();
      expect(calls, 1);
      expect(restoreButton(tester).onPressed, isNull);
      result.completeError(StateError('SECRET token'));
      await tester.pumpAndSettle();
      expect(find.textContaining('outcome is unknown'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(restoreButton(tester).onPressed, isNull);
      when(() => profiles.getAdmissionStatus()).thenThrow(Exception('SECRET'));
      await checkAccess(tester);
      expect(find.text('Restore account'), findsNothing);
      pendingStatus();
      await checkAccess(tester);
      expect(restoreButton(tester).onPressed, isNotNull);
      expect(calls, 1);
    },
  );

  pageTest('fresh session failure is sanitized and never retries', (
    tester,
  ) async {
    pendingStatus();
    await mount(
      tester,
      onRestore: () async {
        throw const PostgrestException(
          code: 'PT403',
          message: 'fresh_session_required',
          details: 'SECRET',
        );
      },
    );
    await checkAccess(tester);
    await tester.tap(find.text('Restore account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fresh session'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(restoreButton(tester).onPressed, isNull);
  });

  for (final transition in ['dispose', 'generation', 'controller', 'success']) {
    pageTest('restore completion respects $transition and never infers home', (
      tester,
    ) async {
      pendingStatus();
      final result = Completer<void>();
      await mount(tester, onRestore: () => result.future);
      await checkAccess(tester);
      await tester.tap(find.text('Restore account'));
      await tester.pump();
      if (transition == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else if (transition == 'generation') {
        controller.invalidate();
        unawaited(controller.revalidate());
        await tester.pump();
        await tester.pump();
      } else if (transition == 'controller') {
        final old = controller;
        controller = AdmissionController(
          authService: auth,
          profileService: profiles,
          now: () => now,
        );
        subscriptionCount++;
        await mount(tester, onRestore: () => result.future);
        old.dispose();
      }
      if (transition == 'success') {
        result.complete();
      } else {
        result.completeError(Exception('SECRET late completion'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('outcome is unknown'), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.text('Your account is ready.'), findsNothing);
      if (transition == 'success') {
        expect(
          find.textContaining('confirm the current restoration status'),
          findsOneWidget,
        );
        expect(restoreButton(tester).onPressed, isNull);
      }
    });
  }

  for (final theme in [lightMode, darkMode]) {
    pageTest('${theme.brightness.name} recovery at 320 and 200% fits', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      pendingStatus();
      await mount(
        tester,
        theme: theme,
        scale: 2,
        onRestore: () async {},
        onSignInAgain: () {},
        onContactSupport: () {},
      );
      await checkAccess(tester);
      await tester.ensureVisible(find.text('Restore account'));
      await tester.pumpAndSettle();
      expect(restoreButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Contact support'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  pageTest(
    'mount is inert; acceptance needs explicit checkbox and rechecks without navigation',
    (tester) async {
      await mount(tester);
      verifyZeroInteractions(profiles);
      expect(
        find.text('Account access has not been confirmed.'),
        findsOneWidget,
      );
      await load(tester);
      expect(find.text('abc'), findsOneWidget);
      expect(find.text('Review-only draft'), findsNothing);
      expect(
        find.text('I have read and agree to the loyalty card terms.'),
        findsOneWidget,
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((widget) => widget is FilledButton),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      when(
        () => profiles.acceptLoyaltyPolicy('review-only-v1'),
      ).thenAnswer((_) async => policy(accepted: true));
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) async => admissionStatus());
      await tester.tap(find.text('Agree and continue'));
      await tester.pumpAndSettle();
      expect(find.text('Your account is ready.'), findsOneWidget);
      expect(find.byType(AdmissionPage), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      verify(() => profiles.acceptLoyaltyPolicy('review-only-v1')).called(1);
      verify(() => profiles.getLoyaltyPolicyStatus()).called(1);
      verify(() => profiles.getAdmissionStatus()).called(2);
      verifyNoMoreInteractions(profiles);
    },
  );

  pageTest('terms load once per generation and login escape is separate', (
    tester,
  ) async {
    unawaited(controller.revalidate());
    var back = 0;
    await mount(tester, onSignInAgain: () => back++);
    await tester.pumpAndSettle();
    expect(find.text('abc'), findsOneWidget);
    expect(find.text('Account access'), findsNothing);
    expect(find.byTooltip('Load current terms'), findsNothing);
    await mount(tester, theme: darkMode, onSignInAgain: () => back++);
    await tester.pumpAndSettle();
    verify(() => profiles.getLoyaltyPolicyStatus()).called(1);
    await tester.tap(find.byTooltip('Back to login'));
    expect(back, 1);
    expect(find.byTooltip('Check account access'), findsNothing);
    unawaited(controller.revalidate());
    await tester.pumpAndSettle();
    verify(() => profiles.getLoyaltyPolicyStatus()).called(1);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  pageTest('failed access refresh retains text but disables stale acceptance', (
    tester,
  ) async {
    await mount(tester);
    await load(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    when(() => profiles.getAdmissionStatus()).thenThrow(Exception('offline'));
    unawaited(controller.revalidate());
    await tester.pumpAndSettle();
    expect(find.text('abc'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('Unable to confirm account access. Please try again.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
    verify(() => profiles.getLoyaltyPolicyStatus()).called(1);
    verifyNever(() => profiles.acceptLoyaltyPolicy(any()));
    expect(find.byTooltip('Check account access'), findsOneWidget);
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) async => admissionStatus(step: 'review_terms'));
    await checkAccess(tester);
    expect(find.byTooltip('Check account access'), findsNothing);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  for (final entry in {
    'verify_email': 'Email verification is required.',
    'enroll_totp': 'Authenticator setup is required.',
    'challenge_totp': 'An authenticator code is required.',
    'blocked': 'Account access is unavailable.',
  }.entries) {
    pageTest(
      '${entry.key} stays display-only without policy/Auth/provider calls',
      (tester) async {
        when(() => profiles.getAdmissionStatus()).thenAnswer(
          (_) async => admissionStatus(
            step: entry.key,
            reason: entry.key == 'blocked' ? 'account_restricted' : null,
          ),
        );
        await mount(tester);
        await tester.tap(find.byTooltip('Check account access'));
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        verify(() => profiles.getAdmissionStatus()).called(1);
        verifyNoMoreInteractions(profiles);
      },
    );
  }

  pageTest(
    'pending, error and retry remain honest without leaking raw errors',
    (tester) async {
      final pending = Completer<LoyaltyPolicyStatus>();
      when(
        () => profiles.getLoyaltyPolicyStatus(),
      ).thenAnswer((_) => pending.future);
      await mount(tester);
      await tester.tap(find.byTooltip('Check account access'));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Load current terms'), findsNothing);
      pending.completeError(
        const PostgrestException(
          message: 'synthetic internal detail',
          code: '22023',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The policy changed. Load the current terms and review them again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('synthetic internal detail'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      verify(() => profiles.getLoyaltyPolicyStatus()).called(1);
      when(
        () => profiles.getLoyaltyPolicyStatus(),
      ).thenAnswer((_) async => policy());
      await tester.tap(find.byTooltip('Load current terms'));
      await tester.pumpAndSettle();
      expect(find.text('abc'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      verify(() => profiles.getLoyaltyPolicyStatus()).called(1);
    },
  );

  pageTest('page disposal clears consent and rejects late write completion', (
    tester,
  ) async {
    await mount(tester);
    await load(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final pending = Completer<LoyaltyPolicyStatus>();
    when(
      () => profiles.acceptLoyaltyPolicy('review-only-v1'),
    ).thenAnswer((_) => pending.future);
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(policy(accepted: true));
    await tester.pumpAndSettle();
    expect(controller.policyDescriptor, isNull);
    expect(controller.canAcceptPolicy, isFalse);
    verify(() => profiles.getAdmissionStatus()).called(1);
    expect(tester.takeException(), isNull);
  });

  pageTest(
    'hard account invalidation clears terms even under a pushed public page',
    (tester) async {
      await mount(tester);
      await load(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      final navigator = Navigator.of(
        tester.element(find.byType(AdmissionPage)),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Public policy')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      session = null;
      events.add(const AuthState(AuthChangeEvent.signedOut, null));
      await tester.pumpAndSettle();
      expect(controller.policyDescriptor, isNull);
      expect(controller.canAcceptPolicy, isFalse);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(
        find.text('Account access has not been confirmed.'),
        findsOneWidget,
      );
    },
  );

  for (final theme in [lightMode, darkMode]) {
    for (final small in [true, false]) {
      pageTest(
        '${theme.brightness.name} terms ${small ? '320 at 200%' : '800 at 100%'} render',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(small ? 320 : 800, small ? 640 : 700);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const renderDir = String.fromEnvironment('RENDER_DIR');
          // Square test glyphs distort the fixed footer at large text sizes.
          await tester.runAsync(() async {
            final config = File('.dart_tool/package_config.json');
            final packages =
                jsonDecode(config.readAsStringSync())['packages'] as List;
            final flutter = config.absolute.uri.resolve(
              packages.singleWhere(
                    (entry) => entry['name'] == 'flutter',
                  )['rootUri']
                  as String,
            );
            for (final entry in {
              'Roboto': 'Roboto-Regular.ttf',
              'MaterialIcons': 'MaterialIcons-Regular.otf',
            }.entries) {
              final bytes = File.fromUri(
                Directory.fromUri(flutter).uri.resolve(
                  '../../bin/cache/artifacts/material_fonts/${entry.value}',
                ),
              ).readAsBytesSync();
              await (FontLoader(
                entry.key,
              )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
            }
          });
          final boundary = GlobalKey();
          when(() => profiles.getLoyaltyPolicyStatus()).thenAnswer(
            (_) async => policy(
              text: List.generate(
                24,
                (index) => index == 23
                    ? 'End of terms.'
                    : 'Terms paragraph $index. Purchased credit does not expire.',
              ).join('\n\n'),
            ),
          );
          await mount(
            tester,
            theme: theme,
            scale: small ? 2 : 1,
            boldText: small,
            boundary: boundary,
          );
          await load(tester);
          final checkbox = find.byType(Checkbox);
          final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
          expect(scrollbar.thumbVisibility, isTrue);
          expect(scrollbar.trackVisibility, isTrue);
          expect(scrollbar.interactive, isTrue);
          final action = find.byWidgetPredicate(
            (widget) => widget is FilledButton,
          );
          expect(checkbox.hitTestable(), findsOneWidget);
          expect(action.hitTestable(), findsOneWidget);
          final checkboxBounds = tester.getRect(checkbox);
          final actionBounds = tester.getRect(action);
          expect(tester.widget<FilledButton>(action).onPressed, isNull);
          expect(
            tester.getRect(find.byType(SingleChildScrollView)).bottom,
            lessThanOrEqualTo(checkboxBounds.top),
          );
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -1000),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .pixels,
            greaterThan(0),
          );
          expect(tester.getRect(checkbox), checkboxBounds);
          expect(tester.getRect(action), actionBounds);
          final lastParagraph = find.widgetWithText(
            SelectableText,
            'End of terms.',
          );
          await Scrollable.ensureVisible(
            tester.element(lastParagraph),
            alignment: 1,
          );
          await tester.pumpAndSettle();
          final viewport = tester.getRect(find.byType(SingleChildScrollView));
          final lastBounds = tester.getRect(lastParagraph);
          expect(lastBounds.top, greaterThanOrEqualTo(viewport.top));
          expect(lastBounds.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(tester.getRect(checkbox), checkboxBounds);
          expect(tester.getRect(action), actionBounds);
          await tester.tap(find.byType(Checkbox));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final appBar = tester.widget<AppBar>(find.byType(AppBar));
          expect(appBar.titleTextStyle!.fontSize, 16);
          final button = tester.widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          );
          expect(button.style!.minimumSize!.resolve({})!.height, 48);
          final shape =
              button.style!.shape!.resolve({})! as RoundedRectangleBorder;
          expect(shape.borderRadius, BorderRadius.circular(8));
          expect(button.onPressed, isNotNull);
          if (renderDir.isNotEmpty) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File(
                '$renderDir/${theme.brightness.name}-${small ? 320 : 800}.png',
              ).writeAsBytesSync(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}
