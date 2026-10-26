import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/mfa/controller.dart';
import 'package:clean_stream_laundry_app/features/mfa/mfa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures.dart';

void main() {
  late MfaFixture fixture;
  late MfaController controller;
  var supportCalls = 0;
  var notNowCalls = 0;
  var signInAgainCalls = 0;

  void pageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      fixture = MfaFixture();
      controller = MfaController(
        authService: fixture.auth,
        mode: MfaMode.enrollment,
      );
      supportCalls = 0;
      notNowCalls = 0;
      signInAgainCalls = 0;
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await fixture.close();
      }
    });
  }

  Future<void> mount(
    WidgetTester tester, {
    bool requiredForAccess = true,
    ThemeData? theme,
    double scale = 1,
    GlobalKey? boundary,
    Future<void> Function()? onVerified,
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
          child: MfaPage(
            controller: controller,
            requiredForAccess: requiredForAccess,
            onVerified: onVerified ?? fixture.revalidate,
            onSupport: () => supportCalls++,
            onNotNow: () => notNowCalls++,
            onSignInAgain: requiredForAccess ? () => signInAgainCalls++ : null,
            accountEmail: 'customer@example.test',
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  pageTest(
    'mount only lists; explicit optional setup renders private details on demand',
    (tester) async {
      await mount(tester, requiredForAccess: false);
      await tester.pumpAndSettle();
      verifyNever(() => fixture.auth.enrollTotp());
      expect(find.text('Not now'), findsOneWidget);
      await tap(tester, find.text('Not now'));
      expect(notNowCalls, 1);
      await tap(tester, find.text('Set up authenticator'));
      verify(() => fixture.auth.enrollTotp()).called(1);
      expect(find.text('Not now'), findsNothing);
      expect(find.text(enrollment.totp!.secret), findsNothing);
      await tap(tester, find.byTooltip('Show setup details'));
      expect(find.text(enrollment.totp!.secret), findsOneWidget);
      expect(find.text(enrollment.totp!.uri), findsOneWidget);
      await tap(tester, find.byTooltip('Hide setup details'));
      expect(find.text(enrollment.totp!.secret), findsNothing);
    },
  );

  pageTest(
    'required MFA identifies the session and offers login without skipping MFA',
    (tester) async {
      await mount(tester);
      await tester.pumpAndSettle();
      expect(find.text('Signed in as customer@example.test'), findsOneWidget);
      expect(find.text('Not now'), findsNothing);
      await tap(tester, find.byTooltip('Back to login'));
      expect(signInAgainCalls, 1);
      expect(fixture.revalidations, 0);
      verifyNever(() => fixture.auth.enrollTotp());
      verifyNever(
        () => fixture.auth.verifyTotp(
          factorId: any(named: 'factorId'),
          code: any(named: 'code'),
        ),
      );
    },
  );

  pageTest(
    'required setup has no skip and support invokes only supplied action',
    (tester) async {
      await mount(tester);
      await tester.pumpAndSettle();
      expect(find.text('Not now'), findsNothing);
      await tap(tester, find.text('Contact support'));
      expect(supportCalls, 1);
      expect(fixture.revalidations, 0);
      verifyNever(() => fixture.auth.enrollTotp());
      expect(find.textContaining('recovery code'), findsNothing);
    },
  );

  pageTest(
    'factor selection clears code and submits only selected verified factor',
    (tester) async {
      fixture.factors = [
        factor(id: 'pending', status: FactorStatus.unverified),
        factor(id: 'one'),
        factor(id: 'two'),
      ];
      await mount(tester);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tap(tester, find.byType(DropdownButtonFormField<String>));
      await tap(tester, find.text('Authenticator 2').last);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), '654321');
      await tap(tester, find.text('Verify code'));
      verify(
        () => fixture.auth.verifyTotp(factorId: 'two', code: '654321'),
      ).called(1);
      expect(fixture.revalidations, 1);
      expect(find.byType(MfaPage), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('Code verified. Account access requires a separate check.'),
        findsOneWidget,
      );
    },
  );

  pageTest(
    'invalid code sanitized error and callback failure/retry remain on page',
    (tester) async {
      fixture.factors = [factor()];
      var shouldFail = true;
      await mount(
        tester,
        onVerified: () async {
          fixture.revalidations++;
          if (shouldFail) throw StateError('private-revalidation-detail');
        },
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Verify code'));
      expect(
        find.text('Enter the six-digit authenticator code.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tap(tester, find.text('Verify code'));
      expect(find.textContaining('private-revalidation-detail'), findsNothing);
      expect(fixture.revalidations, 1);
      shouldFail = false;
      await tap(tester, find.byTooltip('Check account access'));
      expect(fixture.revalidations, 2);
      verify(
        () =>
            fixture.auth.verifyTotp(factorId: 'verified-totp', code: '123456'),
      ).called(1);
      expect(find.byType(MfaPage), findsOneWidget);
    },
  );

  pageTest('unsupported factor blocks mutations and retains support', (
    tester,
  ) async {
    fixture.factors = [factor(type: FactorType.unknown)];
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Set up authenticator'), findsNothing);
    await tap(tester, find.text('Contact support'));
    expect(supportCalls, 1);
  });

  for (final action in ['load', 'enroll', 'verify']) {
    pageTest(
      '$action stays single-flight beyond response wait and settles safely',
      (tester) async {
        final pending = Completer<dynamic>();
        if (action == 'verify') fixture.factors = [factor()];
        if (action == 'load') {
          when(() => fixture.auth.listMfaFactors()).thenAnswer((_) async {
            fixture.refreshForLoad();
            return await pending.future as AuthMFAListFactorsResponse;
          });
        }
        await mount(tester);
        if (action != 'load') await tester.pumpAndSettle();
        if (action == 'enroll') {
          when(() => fixture.auth.enrollTotp()).thenAnswer(
            (_) async => await pending.future as AuthMFAEnrollResponse,
          );
          await tester.tap(find.text('Set up authenticator'));
        }
        if (action == 'verify') {
          when(
            () => fixture.auth.verifyTotp(
              factorId: any(named: 'factorId'),
              code: any(named: 'code'),
            ),
          ).thenAnswer(
            (_) async => await pending.future as AuthMFAVerifyResponse,
          );
          await tester.enterText(find.byType(TextField), '123456');
          await tester.tap(find.text('Verify code'));
        }
        await tester.pump(const Duration(seconds: 11));
        expect(controller.isBusy, true);
        expect(controller.isWaiting, true);
        expect(controller.canEnroll, false);
        expect(controller.canVerify, false);
        expect(controller.canLoad, false);
        expect(find.textContaining('will not cancel'), findsOneWidget);
        if (action == 'enroll') {
          pending.completeError(StateError('unknown-secret'));
        } else if (action == 'load') {
          pending.complete(fixture.factorResponse);
        } else {
          pending.complete(fixture.adopt());
        }
        await tester.pumpAndSettle();
        expect(controller.isBusy, false);
        if (action == 'enroll') {
          expect(controller.canEnroll, false);
          expect(find.text('Set up authenticator'), findsNothing);
        }
        expect(tester.takeException(), null);
      },
    );
  }

  pageTest('A-B-A removes visible setup and typed code', (tester) async {
    await mount(tester);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Set up authenticator'));
    await tap(tester, find.byTooltip('Show setup details'));
    await tester.enterText(find.byType(TextField), '123456');
    final original = fixture.current;
    fixture.emit(AuthChangeEvent.signedIn, session(user: 'b'));
    fixture.emit(AuthChangeEvent.signedIn, original);
    await tester.pumpAndSettle();
    expect(find.text(enrollment.totp!.secret), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('session changed or expired'), findsOneWidget);
    expect(controller.setup, null);
  });

  pageTest('expiry clears setup without another user action', (tester) async {
    await mount(tester);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Set up authenticator'));
    await tester.pump(const Duration(hours: 1));
    expect(controller.stage, MfaStage.expired);
    expect(controller.setup, null);
  });

  for (final expiredOnArrival in [true, false]) {
    pageTest(
      'pending load rejects ${expiredOnArrival ? 'expired refresh' : 'expiry after refresh'} and late revival',
      (tester) async {
        final pending = Completer<AuthMFAListFactorsResponse>();
        when(
          () => fixture.auth.listMfaFactors(),
        ).thenAnswer((_) => pending.future);
        await mount(tester);
        final refreshed = session(token: 'loading-refresh')
          ..expiresAt = expiredOnArrival
              ? 1
              : DateTime.now()
                        .add(const Duration(seconds: 32))
                        .millisecondsSinceEpoch ~/
                    1000;
        fixture.emit(AuthChangeEvent.tokenRefreshed, refreshed);
        await tester.pump();
        if (!expiredOnArrival) {
          expect(controller.stage, MfaStage.idle);
          expect(controller.isBusy, true);
          await tester.pump(const Duration(seconds: 3));
        }
        expect(controller.stage, MfaStage.expired);
        fixture.refreshForLoad();
        pending.complete(fixture.factorResponse);
        await tester.pumpAndSettle();
        expect(controller.stage, MfaStage.expired);
        expect(controller.canEnroll, false);
        expect(controller.canVerify, false);
        expect(find.text('Set up authenticator'), findsNothing);
        expect(fixture.revalidations, 0);
      },
    );
  }

  pageTest('leaving page invalidates pending verify and prevents callback', (
    tester,
  ) async {
    fixture.factors = [factor()];
    await mount(tester);
    await tester.pumpAndSettle();
    final pending = Completer<AuthMFAVerifyResponse>();
    when(
      () => fixture.auth.verifyTotp(
        factorId: any(named: 'factorId'),
        code: any(named: 'code'),
      ),
    ).thenAnswer((_) => pending.future);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(fixture.adopt());
    await tester.pumpAndSettle();
    expect(fixture.revalidations, 0);
    expect(controller.stage, MfaStage.expired);
    expect(tester.takeException(), null);
  });

  pageTest(
    'controller replacement clears old setup and rejects its pending work',
    (tester) async {
      await mount(tester);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Set up authenticator'));
      final old = controller;
      fixture.factors = [factor()];
      controller = MfaController(
        authService: fixture.auth,
        mode: MfaMode.challenge,
      );
      await mount(tester);
      await tester.pumpAndSettle();
      expect(old.stage, MfaStage.expired);
      expect(old.setup, null);
      expect(controller.stage, MfaStage.challenge);
      old.dispose();
    },
  );

  for (final theme in [lightMode, darkMode]) {
    for (final narrow in [true, false]) {
      for (final screen in ['setup', 'challenge']) {
        pageTest(
          '${theme.brightness.name} $screen ${narrow ? '320 200%' : '800 100%'}',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(
              narrow ? 320 : 800,
              narrow ? 640 : 800,
            );
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            const renderDir = String.fromEnvironment('RENDER_DIR');
            if (renderDir.isNotEmpty) {
              await tester.runAsync(() async {
                for (final font in [
                  ('Roboto', 'Roboto-Regular.ttf'),
                  ('MaterialIcons', 'MaterialIcons-Regular.otf'),
                ]) {
                  await (FontLoader(font.$1)..addFont(
                        Future.value(
                          ByteData.sublistView(
                            File(
                              '/private/tmp/cleanstream-flutter-3.38.10/bin/cache/artifacts/material_fonts/${font.$2}',
                            ).readAsBytesSync(),
                          ),
                        ),
                      ))
                      .load();
                }
              });
            }
            if (screen == 'challenge') {
              fixture.factors = [factor(id: 'one'), factor(id: 'two')];
            }
            final boundary = GlobalKey();
            await mount(
              tester,
              theme: theme,
              scale: narrow ? 2 : 1,
              boundary: boundary,
            );
            await tester.pumpAndSettle();
            if (screen == 'setup') {
              await tap(tester, find.text('Set up authenticator'));
              await tap(tester, find.byTooltip('Show setup details'));
            }
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
                  '$renderDir/${theme.brightness.name}-$screen-${narrow ? 320 : 800}.png',
                ).writeAsBytesSync(data!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.ensureVisible(find.byType(TextField));
            await tester.enterText(find.byType(TextField), '123456');
            await tap(tester, find.text('Verify code'));
            expect(fixture.revalidations, 1);
            await tap(tester, find.text('Contact support'));
            expect(supportCalls, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
