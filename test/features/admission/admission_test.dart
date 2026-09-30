import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/admission/admission.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mocks.dart';

LoyaltyPolicyStatus policy({bool accepted = false}) =>
    LoyaltyPolicyStatus.fromJson({
      'required_version': 'review-only-v1',
      'policy_text': 'abc',
      'policy_sha256':
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
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
          ).copyWith(textScaler: TextScaler.linear(scale)),
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
    await tester.tap(find.byTooltip('Load current terms'));
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
      expect(find.text('Review-only draft'), findsOneWidget);
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
      await tester.tap(find.text('Accept terms'));
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
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Load current terms'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Load current terms',
              ),
            )
            .onPressed,
        isNull,
      );
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
      when(
        () => profiles.getLoyaltyPolicyStatus(),
      ).thenAnswer((_) async => policy());
      await tester.tap(find.byTooltip('Load current terms'));
      await tester.pumpAndSettle();
      expect(find.text('abc'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      verify(() => profiles.getLoyaltyPolicyStatus()).called(2);
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
    await tester.tap(find.text('Accept terms'));
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
          if (renderDir.isNotEmpty) {
            final font = File(
              '/private/tmp/cleanstream-flutter-3.38.10/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
            );
            await tester.runAsync(
              () =>
                  (FontLoader('Roboto')..addFont(
                        Future.value(
                          ByteData.sublistView(font.readAsBytesSync()),
                        ),
                      ))
                      .load(),
            );
            await tester.runAsync(
              () =>
                  (FontLoader('MaterialIcons')..addFont(
                        Future.value(
                          ByteData.sublistView(
                            File(
                              '/private/tmp/cleanstream-flutter-3.38.10/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                            ).readAsBytesSync(),
                          ),
                        ),
                      ))
                      .load(),
            );
          }
          final boundary = GlobalKey();
          await mount(
            tester,
            theme: theme,
            scale: small ? 2 : 1,
            boundary: boundary,
          );
          await load(tester);
          await tester.ensureVisible(find.byType(Checkbox));
          await tester.tap(find.byType(Checkbox));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Accept terms'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester
                .widget<FilledButton>(
                  find.byWidgetPredicate((widget) => widget is FilledButton),
                )
                .onPressed,
            isNotNull,
          );
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
