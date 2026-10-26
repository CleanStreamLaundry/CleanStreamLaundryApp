import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/features/admission/admission.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/features/admission/gate.dart';
import 'package:clean_stream_laundry_app/features/loading/loading.dart';
import 'package:clean_stream_laundry_app/features/loading/widgets/logo.dart';
import 'package:clean_stream_laundry_app/features/login/login.dart';
import 'package:clean_stream_laundry_app/features/home/home.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/edit_profile.dart';
import 'package:clean_stream_laundry_app/features/mfa/controller.dart';
import 'package:clean_stream_laundry_app/features/mfa/mfa.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../loading/mocks.dart' show MockAppLinks;
import '../loyalty/mocks.dart' show MockWalletService, MockPaymentProcessor;
import '../home/mocks.dart' show MockLocationService, MockMachineService;
import '../edit_profile/lifecycle_fixtures.dart' show lifecycleStatus;
import '../mfa/fixtures.dart' as mfa;
import 'mocks.dart';
import '../../fixtures/loyalty_action_context.dart';

void main() {
  late mfa.MfaFixture fixture;
  late MockAdmissionProfileService profiles;
  late AdmissionController admission;
  late AdmissionStatus result;
  Future<AdmissionStatus> Function()? read;
  var reads = 0;
  GoRouter? router;

  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(DateTime(2026));
  });
  setUp(() {
    fixture = mfa.MfaFixture()..current = mfa.session(user: accountA);
    when(() => fixture.auth.listMfaFactors()).thenAnswer((_) async {
      await Future<void>.delayed(Duration.zero);
      fixture.refreshForLoad();
      return fixture.factorResponse;
    });
    profiles = MockAdmissionProfileService();
    when(() => profiles.getLoyaltyActionContext('account_deletion'))
        .thenAnswer((_) async => actionContext(action: 'account_deletion', subject: accountA));
    result = admissionStatus();
    read = null;
    reads = 0;
    when(() => profiles.getAdmissionStatus()).thenAnswer((_) {
      reads++;
      return read?.call() ?? Future.value(result);
    });
    admission = AdmissionController(
      authService: fixture.auth,
      profileService: profiles,
    );
  });

  void qa(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        router?.dispose();
        router = null;
        admission.dispose();
        await fixture.close();
        await GetIt.I.reset();
      }
    });
  }

  Widget gate(String location) => AdmissionGate(
    controller: admission,
    auth: fixture.auth,
    profiles: profiles,
    location: location,
    child: const _ProtectedState(),
  );

  Future<void> mount(WidgetTester tester, {String path = '/homePage'}) async {
    await tester.pumpWidget(MaterialApp(home: gate(path)));
    await tester.pumpAndSettle();
  }

  Future<void> mountFlow(WidgetTester tester, String path) async {
    router = GoRouter(
      initialLocation: path,
      routes: [
        ShellRoute(
          builder: (_, state, child) => gate(state.uri.toString()),
          routes: [
            for (final path in ['/homePage', '/security/mfa', '/admission'])
              GoRoute(path: path, builder: (_, _) => const SizedBox()),
          ],
        ),
        for (final path in ['/settings', '/email-verification', '/login'])
          GoRoute(path: path, builder: (_, _) => Text('Destination $path')),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<void> mountProfile(
    WidgetTester tester, {
    String path = '/editProfile',
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    when(
      () => fixture.auth.getCurrentUserId,
    ).thenAnswer((_) => fixture.current?.user.id);
    when(
      () => fixture.auth.getCurrentUserEmail(),
    ).thenReturn('qa@example.test');
    when(
      () => fixture.auth.onAuthChange,
    ).thenAnswer((_) => const Stream.empty());
    when(() => profiles.getUserNameById(any())).thenAnswer((_) async => 'QA');
    when(
      () => profiles.getUserBalanceById(any()),
    ).thenAnswer((_) async => {'full_name': 'QA', 'reward_tracker': 0});
    final locations = MockLocationService();
    when(() => locations.getLocations()).thenAnswer((_) async => []);
    final wallet = MockWalletService();
    when(() => wallet.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet-a',
        status: 'active',
        paidBalanceCents: 1000,
        promoBalanceCents: 0,
        totalBalanceCents: 1000,
      ),
    );
    GetIt.I.registerSingleton<AuthService>(fixture.auth);
    GetIt.I.registerSingleton<ProfileService>(profiles);
    GetIt.I.registerSingleton<AdmissionController>(admission);
    GetIt.I.registerSingleton<LocationService>(locations);
    GetIt.I.registerSingleton<MachineService>(MockMachineService());
    GetIt.I.registerSingleton<WalletService>(wallet);
    router = RouterService().createRouter(
      fixture.auth,
      admission: admission,
      profiles: profiles,
    )..go(path);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<void> pumpLoginFrames(WidgetTester tester) async {
    // Inspect each frame: settling alone misses the ready/recovery flash.
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Your account is ready.'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  }

  Future<Completer<AdmissionStatus>> startPasswordLogin(
    WidgetTester tester,
  ) async {
    fixture.emit(AuthChangeEvent.signedOut, null);
    final password = Completer<AuthenticationResponses>();
    final server = Completer<AdmissionStatus>();
    when(
      () => fixture.auth.login('qa@example.test', 'synthetic-password'),
    ).thenAnswer((_) => password.future);
    read = () => server.future;
    await mountProfile(tester, path: '/login');
    expect(reads, 0);
    await tester.enterText(find.byType(TextField).at(0), 'qa@example.test');
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    await tester.ensureVisible(find.text('Log In'));
    await tester.tap(find.text('Log In'));
    await tester.pump();
    expect(find.byType(Login), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(reads, 0);

    fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountA));
    password.complete(AuthenticationResponses.success);
    await pumpLoginFrames(tester);
    expect(router!.routeInformationProvider.value.uri.path, '/homePage');
    expect(find.byType(Logo), findsOneWidget);
    expect(find.text('Checking account access.'), findsNothing);
    expect(find.text('Sign in again'), findsNothing);
    expect(find.text('Contact support'), findsNothing);
    expect(find.byType(HomePage), findsNothing);
    expect(reads, 1);
    verify(
      () => fixture.auth.login('qa@example.test', 'synthetic-password'),
    ).called(1);
    verifyNever(() => profiles.getUserBalanceById(any()));
    return server;
  }

  for (final step in ['home', 'blocked']) {
    qa('password login transition resolves $step without ready fallback', (
      tester,
    ) async {
      final server = await startPasswordLogin(tester);
      server.complete(
        admissionStatus(
          step: step,
          reason: step == 'blocked' ? 'account_restricted' : null,
        ),
      );
      await pumpLoginFrames(tester);
      expect(reads, 1);
      if (step == 'home') {
        expect(find.byType(HomePage), findsOneWidget);
        expect(find.byType(AdmissionPage), findsNothing);
        expect(find.text('Sign in again'), findsNothing);
        expect(find.text('Contact support'), findsNothing);
      } else {
        expect(find.byType(HomePage), findsNothing);
        expect(find.text('Account access is unavailable.'), findsOneWidget);
        expect(find.text('Sign in again'), findsOneWidget);
        expect(find.text('Contact support'), findsOneWidget);
        verifyNever(() => profiles.getUserBalanceById(any()));
      }
    });
  }

  for (final change in ['sign-out', 'account-B', 'A-B-A']) {
    qa('password login transition rejects late admission after $change', (
      tester,
    ) async {
      final stale = await startPasswordLogin(tester);
      final fresh = Completer<AdmissionStatus>();
      read = () => fresh.future;
      if (change == 'sign-out') {
        fixture.emit(AuthChangeEvent.signedOut, null);
      } else {
        fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountB));
        if (change == 'A-B-A') {
          fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountA));
        }
      }
      await pumpLoginFrames(tester);
      stale.complete(admissionStatus());
      await pumpLoginFrames(tester);
      expect(admission.canEnterHome, isFalse);
      expect(find.byType(HomePage), findsNothing);
      verifyNever(() => profiles.getUserBalanceById(any()));
      expect(reads, change == 'sign-out' ? 1 : 2);
      if (change == 'sign-out') {
        expect(find.text('Sign in again'), findsOneWidget);
      } else {
        expect(find.byType(Logo), findsNothing);
        expect(find.text('Checking account access.'), findsOneWidget);
        expect(find.text('Sign in again'), findsOneWidget);
        expect(find.text('Contact support'), findsOneWidget);
        fresh.complete(
          admissionStatus(
            id: change == 'account-B' ? accountB : accountA,
            step: 'blocked',
            reason: 'account_restricted',
          ),
        );
        await pumpLoginFrames(tester);
        expect(find.text('Account access is unavailable.'), findsOneWidget);
        expect(find.text('Sign in again'), findsOneWidget);
        expect(find.byType(HomePage), findsNothing);
        verifyNever(() => profiles.getUserBalanceById(any()));
      }
    });
  }

  Future<void> openDeletion(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Delete Account'));
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Request Deletion'),
          )
          .onPressed,
      isNotNull,
    );
  }

  for (final step in ['enroll_totp', 'challenge_totp']) {
    qa('$step preserves exact MFA controller across factor-load refresh', (
      tester,
    ) async {
      result = admissionStatus(step: step);
      if (step == 'challenge_totp') fixture.factors = [mfa.factor()];
      final factors = Completer<AuthMFAListFactorsResponse>();
      when(() => fixture.auth.listMfaFactors()).thenAnswer((_) async {
        await Future<void>.delayed(Duration.zero);
        fixture.refreshForLoad();
        return factors.future;
      });
      await tester.pumpWidget(MaterialApp(home: gate('/homePage')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final controller = tester
          .widget<MfaPage>(find.byType(MfaPage))
          .controller;
      factors.complete(fixture.factorResponse);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MfaPage>(find.byType(MfaPage)).controller,
        same(controller),
      );
      expect(
        controller.stage,
        step == 'enroll_totp' ? MfaStage.readyToEnroll : MfaStage.challenge,
      );
      expect(fixture.listRefreshes, 1);
      expect(reads, 2);
      expect(find.byType(_ProtectedState), findsNothing);
      verifyNever(() => fixture.auth.enrollTotp());
    });
  }

  qa('verified code waits for server read and retries read without reverify', (
    tester,
  ) async {
    result = admissionStatus(step: 'challenge_totp');
    fixture.factors = [mfa.factor()];
    await mount(tester);
    final server = Completer<AdmissionStatus>();
    read = () => server.future;
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify code'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(reads, 3);
    expect(find.byType(_ProtectedState), findsNothing);
    expect(
      tester.widget<MfaPage>(find.byType(MfaPage)).controller.stage,
      MfaStage.verified,
    );
    server.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Code verified, but account access could not be checked. Try checking again.',
      ),
      findsOneWidget,
    );
    final failedReads = reads;
    await tester.pump(const Duration(seconds: 2));
    expect(reads, failedReads);
    read = null;
    result = admissionStatus();
    await tester.tap(find.byTooltip('Check account access'));
    await tester.pumpAndSettle();
    expect(find.byType(_ProtectedState), findsOneWidget);
    expect(reads, failedReads + 1);
    verify(
      () => fixture.auth.verifyTotp(factorId: 'verified-totp', code: '123456'),
    ).called(1);
  });

  qa('optional MFA Not now returns to settings without enrollment', (
    tester,
  ) async {
    await mountFlow(tester, '/security/mfa');
    expect(find.text('Not now'), findsOneWidget);
    expect(
      tester.widget<MfaPage>(find.byType(MfaPage)).requiredForAccess,
      isFalse,
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Destination /settings'), findsOneWidget);
    verifyNever(() => fixture.auth.enrollTotp());
  });

  qa('optional MFA verification returns to settings only after admission', (
    tester,
  ) async {
    fixture.factors = [mfa.factor()];
    await mountFlow(tester, '/security/mfa');
    final server = Completer<AdmissionStatus>();
    read = () => server.future;
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify code'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(router!.routeInformationProvider.value.uri.path, '/security/mfa');
    server.complete(admissionStatus());
    await tester.pumpAndSettle();
    expect(find.text('Destination /settings'), findsOneWidget);
  });

  qa('required MFA on optional route has no dismissal', (tester) async {
    result = admissionStatus(step: 'enroll_totp');
    await mountFlow(tester, '/security/mfa');
    expect(find.text('Not now'), findsNothing);
    expect(
      tester.widget<MfaPage>(find.byType(MfaPage)).requiredForAccess,
      isTrue,
    );
  });

  qa('verify-email gate callback reaches the public verification route', (
    tester,
  ) async {
    result = admissionStatus(step: 'verify_email');
    await mountFlow(tester, '/homePage');
    await tester.tap(find.text('Verify email'));
    await tester.pumpAndSettle();
    expect(find.text('Destination /email-verification'), findsOneWidget);
    expect(reads, 1);
  });

  qa('restore response alone cannot unlock protected content', (tester) async {
    result = AdmissionStatus.fromJson({
      'subject_id': accountA,
      'account_access': 'restricted',
      'next_step': 'blocked',
      'reason': 'explicit_restore_required',
      'account_state': 'pending_deletion',
      'restore_until': '2099-01-01T00:00:00Z',
    });
    when(
      () => profiles.restoreAccount(),
    ).thenAnswer((_) async => admissionStatus());
    await mount(tester);
    expect(reads, 1);
    verifyNever(() => profiles.restoreAccount());
    await tester.tap(find.text('Restore account'));
    await tester.pumpAndSettle();
    expect(find.byType(_ProtectedState), findsNothing);
    expect(reads, 2);
    verify(() => profiles.restoreAccount()).called(1);
  });

  qa('queued A-B-A discards mounted state and rejects stale admission', (
    tester,
  ) async {
    await mount(tester);
    final old = tester.state(find.byType(_ProtectedState));
    final stale = Completer<AdmissionStatus>();
    read = () => stale.future;
    final check = admission.revalidate();
    fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountB));
    fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountA));
    await tester.pump();
    await tester.pump();
    expect(old.mounted, isFalse);
    read = null;
    result = admissionStatus(step: 'blocked', reason: 'account_restricted');
    stale.complete(admissionStatus());
    await tester.pumpAndSettle();
    await check;
    expect(find.byType(_ProtectedState), findsNothing);
    expect(find.text('Account access is unavailable.'), findsOneWidget);
    expect(reads, 3);
  });

  qa('MFA A-B-A replaces expired flow and rejects old factor completion', (
    tester,
  ) async {
    result = admissionStatus(step: 'enroll_totp');
    final stale = Completer<AuthMFAListFactorsResponse>();
    var loads = 0;
    when(() => fixture.auth.listMfaFactors()).thenAnswer((_) {
      loads++;
      return loads == 1 ? stale.future : Future.value(fixture.factorResponse);
    });
    await tester.pumpWidget(MaterialApp(home: gate('/homePage')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final old = tester.widget<MfaPage>(find.byType(MfaPage)).controller;
    fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountB));
    fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountA));
    await tester.pumpAndSettle();
    stale.complete(fixture.factorResponse);
    await tester.pumpAndSettle();
    final fresh = tester.widget<MfaPage>(find.byType(MfaPage)).controller;
    expect(fresh, isNot(same(old)));
    expect(old.stage, MfaStage.expired);
    expect(fresh.stage, MfaStage.readyToEnroll);
    expect(loads, 2);
  });

  qa(
    'soft network failure retains state but removes focus and semantics until explicit retry',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester);
      final state = tester.state<_ProtectedStateState>(
        find.byType(_ProtectedState),
      );
      state.focus.requestFocus();
      await tester.pump();
      expect(state.focus.hasFocus, isTrue);
      expect(find.bySemanticsLabel('Protected action'), findsOneWidget);
      read = () => Future.error(Exception('network unavailable'));
      final check = admission.revalidate();
      await tester.pumpAndSettle();
      await check;
      expect(state.mounted, isTrue);
      expect(state.focus.hasFocus, isFalse);
      expect(state.focus.canRequestFocus, isFalse);
      expect(
        tester
            .binding
            .renderViews
            .single
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!
            .toStringDeep(),
        isNot(contains('Protected action')),
      );
      await tester.tap(find.text('Protected action'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 2));
      expect(state.actions, 0);
      expect(reads, 2);
      read = null;
      await tester.tap(find.byTooltip('Retry account access'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(_ProtectedState)), same(state));
      expect(reads, 3);
      expect(state.focus.canRequestFocus, isTrue);
      await tester.tap(find.text('Protected action'));
      expect(state.actions, 1);
      semantics.dispose();
    },
  );

  qa('hard denial removes previously admitted state', (tester) async {
    await mount(tester);
    final state = tester.state(find.byType(_ProtectedState));
    read = () => Future.error(
      const PostgrestException(message: 'denied', code: 'PT403'),
    );
    final check = admission.revalidate();
    await tester.pumpAndSettle();
    await check;
    expect(state.mounted, isFalse);
    expect(find.byType(AdmissionPage), findsOneWidget);
    expect(reads, 2);
  });

  qa('soft invalidation suppresses actual open deletion confirmation', (
    tester,
  ) async {
    await mountProfile(tester);
    await openDeletion(tester);
    read = () => Future.error(Exception('offline'));
    final check = admission.revalidate();
    await tester.pumpAndSettle();
    await check;
    final action = find.widgetWithText(ElevatedButton, 'Request Deletion');
    if (action.evaluate().isNotEmpty) {
      await tester.tap(action, warnIfMissed: false);
      await tester.pump();
    }
    expect(admission.canEnterHome, isFalse);
    verifyNever(() => profiles.requestAccountDeletion(consent: any(named: 'consent')));
  });

  for (final path in [
    '/homePage',
    '/loyalty',
    '/settings',
    '/security/mfa',
    '/admission',
    '/scanner',
    '/pay?machine=synthetic',
    '/admin/wallets',
    '/paymentPage',
    '/startPage',
    '/monthlyTransactionHistory',
    '/refundPage',
    '/maintenancePage',
    '/editProfile',
  ]) {
    qa('production router denies blocked account at $path', (tester) async {
      result = admissionStatus(step: 'blocked', reason: 'account_restricted');
      router = RouterService().createRouter(
        fixture.auth,
        admission: admission,
        profiles: profiles,
      )..go(path);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byType(AdmissionGate), findsOneWidget);
      expect(find.text('Account access is unavailable.'), findsOneWidget);
      expect(reads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  qa('gated production router callback has exactly one exchange consumer', (
    tester,
  ) async {
    final uri = Uri.parse('clean-stream://oauth?code=synthetic');
    final exchange = Completer<void>();
    final links = MockAppLinks();
    when(() => links.getInitialLink()).thenAnswer((_) async => null);
    when(() => links.uriLinkStream).thenAnswer((_) => const Stream.empty());
    when(
      () => fixture.auth.getSessionFromURI(uri),
    ).thenAnswer((_) => exchange.future);
    when(
      () => fixture.auth.isLoggedIn(),
    ).thenAnswer((_) async => AuthenticationResponses.failure);
    when(
      () => fixture.auth.onAuthChange,
    ).thenAnswer((_) => const Stream.empty());
    GetIt.I.registerSingleton<AuthService>(fixture.auth);
    GetIt.I.registerSingleton<ProfileService>(profiles);
    router = RouterService().createRouter(
      fixture.auth,
      admission: admission,
      profiles: profiles,
      appLinks: links,
    )..go(uri.toString(), extra: uri);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LoadingPage), findsOneWidget);
    expect(find.byType(AdmissionGate), findsNothing);
    expect(reads, 0);
    exchange.complete();
    await tester.pumpAndSettle();
    expect(router!.routeInformationProvider.value.uri.path, '/login');
    verify(() => fixture.auth.getSessionFromURI(uri)).called(1);
    expect(reads, 0);
  });

  qa('actual SDK factor refresh preserves required MFA without a loop', (
    tester,
  ) async {
    var requests = 0;
    Map<String, dynamic> sessionJson(String revision) {
      String part(Object data) =>
          base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
      return {
        'access_token':
            '${part({'alg': 'none'})}.${part({'sub': accountA, 'aal': 'aal1', 'amr': [], 'exp': 4102444800, 'revision': revision})}.synthetic',
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': accountA,
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
          'factors': [],
        },
      };
    }

    final client = MockClient((request) async {
      requests++;
      expect(
        request.url.toString(),
        'https://offline.invalid/auth/v1/token?grant_type=refresh_token',
      );
      return http.Response(jsonEncode(sessionJson('refreshed')), 200);
    });
    final sdk = GoTrueClient(
      url: 'https://offline.invalid/auth/v1',
      httpClient: client,
      autoRefreshToken: false,
    );
    await sdk.setInitialSession(jsonEncode(sessionJson('initial')));
    admission.dispose();
    when(
      () => fixture.auth.currentSession,
    ).thenAnswer((_) => sdk.currentSession);
    when(
      () => fixture.auth.authStateChanges,
    ).thenAnswer((_) => sdk.onAuthStateChange);
    when(
      () => fixture.auth.listMfaFactors(),
    ).thenAnswer((_) => sdk.mfa.listFactors());
    when(
      () => fixture.auth.getMfaAssurance(),
    ).thenAnswer((_) => sdk.mfa.getAuthenticatorAssuranceLevel());
    admission = AdmissionController(
      authService: fixture.auth,
      profileService: profiles,
    );
    result = admissionStatus(step: 'enroll_totp');
    try {
      await mount(tester);
      expect(
        tester.widget<MfaPage>(find.byType(MfaPage)).controller.stage,
        MfaStage.readyToEnroll,
      );
      expect(requests, 1);
      expect(reads, 2);
      expect(find.byType(_ProtectedState), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      admission.dispose();
      sdk.dispose();
      client.close();
    }
  });

  qa('hard account switch removes actual deletion confirmation', (
    tester,
  ) async {
    await mountProfile(tester);
    final state = tester.state(find.byType(EditProfilePage));
    await openDeletion(tester);
    result = admissionStatus(
      id: accountB,
      step: 'blocked',
      reason: 'account_restricted',
    );
    fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountB));
    await tester.pumpAndSettle();
    expect(state.mounted, isFalse);
    expect(
      find.widgetWithText(ElevatedButton, 'Request Deletion'),
      findsNothing,
    );
    verifyNever(() => profiles.requestAccountDeletion(consent: any(named: 'consent')));
  });

  qa('actual Wallet Pay cannot dispatch while admission is unconfirmed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final wallet = MockWalletService();
    final payments = MockPaymentProcessor();
    when(
      () => fixture.auth.getCurrentUserId,
    ).thenAnswer((_) => fixture.current?.user.id);
    when(
      () => fixture.auth.onAuthChange,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => profiles.getUserBalanceById(any()),
    ).thenAnswer((_) async => {'full_name': 'QA', 'reward_tracker': 0});
    when(() => wallet.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet-a',
        status: 'active',
        paidBalanceCents: 1000,
        promoBalanceCents: 0,
        totalBalanceCents: 1000,
      ),
    );
    when(
      () => wallet.getLedger(
        userId: any(named: 'userId'),
        walletAccountId: any(named: 'walletAccountId'),
        since: any(named: 'since'),
        rewardsOnly: any(named: 'rewardsOnly'),
      ),
    ).thenAnswer((_) async => []);
    var paymentCalls = 0;
    when(() => payments.processPayment(any(), any())).thenAnswer((_) async {
      paymentCalls++;
      return PaymentResult.canceled;
    });
    GetIt.I.registerSingleton<AuthService>(fixture.auth);
    GetIt.I.registerSingleton<ProfileService>(profiles);
    GetIt.I.registerSingleton<WalletService>(wallet);
    GetIt.I.registerSingleton<PaymentProcessor>(payments);
    router = RouterService().createRouter(
      fixture.auth,
      admission: admission,
      profiles: profiles,
    )..go('/loyalty?loadCard=true');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    read = () => Future.error(Exception('offline'));
    final check = admission.revalidate();
    await tester.pumpAndSettle();
    await check;
    expect(admission.canEnterHome, isFalse);
    final pay = find.widgetWithText(ElevatedButton, 'Pay');
    if (pay.evaluate().isNotEmpty) {
      await tester.tap(pay, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    expect(
      paymentCalls,
      0,
      reason:
          'Real Wallet dispatched PaymentProcessor while admission was unconfirmed',
    );
  });

  for (final unknownOutcome in [false, true]) {
    qa(
      'actual deletion ${unknownOutcome ? 'status recovery' : 'acknowledgment'} revalidates gate before routing',
      (tester) async {
        var mutations = 0;
        when(() => profiles.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) async {
          mutations++;
          result = lifecycleStatus(id: accountA);
          if (unknownOutcome) throw Exception('response lost');
          return result;
        });
        await mountProfile(tester);
        await openDeletion(tester);
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Request Deletion'),
        );
        await tester.pumpAndSettle();
        if (unknownOutcome) {
          expect(find.text('Check Account Status'), findsOneWidget);
          await tester.ensureVisible(find.text('Check Account Status'));
          await tester.tap(find.text('Check Account Status'));
          await tester.pumpAndSettle();
        }
        expect(mutations, 1);
        expect(
          router!.routeInformationProvider.value.uri.path,
          '/admission',
          reason:
              'Confirmed pending deletion must not reuse cached Home permission (status reads: $reads)',
        );
        expect(
          reads,
          unknownOutcome ? 4 : 3,
          reason:
              'The shared route gate needs its own fresh status, not cached Home admission',
        );
        expect(admission.canEnterHome, isFalse);
        expect(find.byType(HomePage), findsNothing);
        expect(find.text('Restore account'), findsOneWidget);
        verifyNever(() => fixture.auth.logout());
        expect(tester.takeException(), isNull);
      },
    );
  }

  qa(
    'confirmed deletion stays closed on admission read error until explicit retry',
    (tester) async {
      when(() => profiles.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) async {
        result = lifecycleStatus(id: accountA);
        read = () => Future.error(Exception('admission unavailable'));
        return result;
      });
      await mountProfile(tester);
      await openDeletion(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Request Deletion'));
      await tester.pumpAndSettle();
      expect(router!.routeInformationProvider.value.uri.path, '/admission');
      expect(reads, 3);
      expect(admission.canEnterHome, isFalse);
      expect(admission.retainSafePresentation, isFalse);
      expect(find.byType(HomePage), findsNothing);
      expect(find.byType(EditProfilePage), findsNothing);
      expect(
        find.text('Unable to confirm account access. Please try again.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(reads, 3);
      read = null;
      await tester.tap(find.byTooltip('Check account access'));
      await tester.pumpAndSettle();
      expect(reads, 4);
      expect(find.text('Restore account'), findsOneWidget);
      expect(admission.canEnterHome, isFalse);
      verify(() => profiles.requestAccountDeletion(consent: any(named: 'consent'))).called(1);
      verifyNever(() => fixture.auth.logout());
      expect(tester.takeException(), isNull);
    },
  );

  for (final leaveRoute in [false, true]) {
    for (final fail in [false, true]) {
      qa(
        'actual deletion late ${fail ? 'failure' : 'success'} after ${leaveRoute ? 'route exit' : 'A-B-A'} cannot invalidate or navigate',
        (tester) async {
          final response = Completer<AdmissionStatus>();
          when(
            () => profiles.requestAccountDeletion(consent: any(named: 'consent')),
          ).thenAnswer((_) => response.future);
          await mountProfile(tester);
          await openDeletion(tester);
          await tester.tap(
            find.widgetWithText(ElevatedButton, 'Request Deletion'),
          );
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          verify(() => profiles.requestAccountDeletion(consent: any(named: 'consent'))).called(1);
          if (leaveRoute) {
            router!.go('/legal/terms');
          } else {
            fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountB));
            fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountA));
          }
          // The held deletion still animates; settle only after releasing it.
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final generation = admission.generation;
          final priorReads = reads;
          final location = router!.routeInformationProvider.value.uri;
          if (fail) {
            response.completeError(Exception('late failure'));
          } else {
            response.complete(lifecycleStatus(id: accountA));
          }
          await tester.pumpAndSettle();
          expect(router!.routeInformationProvider.value.uri, location);
          expect(location.path, leaveRoute ? '/legal/terms' : '/editProfile');
          expect(admission.generation, generation);
          expect(reads, priorReads);
          expect(
            find.textContaining('The outcome could not be confirmed.'),
            findsNothing,
          );
          verifyNever(() => fixture.auth.logout());
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  qa(
    'actual recovery route requires fresh server admission after restoration',
    (tester) async {
      result = lifecycleStatus(id: accountA);
      when(() => profiles.restoreAccount()).thenAnswer((_) async {
        result = admissionStatus();
        return result;
      });
      await mountProfile(tester, path: '/admission');
      expect(find.byType(HomePage), findsNothing);
      verifyNever(() => profiles.restoreAccount());
      await tester.tap(find.text('Restore account'));
      await tester.pumpAndSettle();
      verify(() => profiles.restoreAccount()).called(1);
      expect(reads, 2);
      expect(router!.routeInformationProvider.value.uri.path, '/homePage');
      expect(find.byType(HomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final hard in [false, true]) {
    qa(
      'contained dialog control suppresses actions on ${hard ? 'hard' : 'soft'} invalidation',
      (tester) async {
        router = GoRouter(
          initialLocation: '/protected',
          routes: [
            ShellRoute(
              builder: (_, state, child) => AdmissionGate(
                controller: admission,
                auth: fixture.auth,
                profiles: profiles,
                location: state.uri.toString(),
                child: child,
              ),
              routes: [
                GoRoute(
                  path: '/protected',
                  builder: (_, _) =>
                      const _ProtectedState(useRootNavigator: false),
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        final state = tester.state<_ProtectedStateState>(
          find.byType(_ProtectedState),
        );
        await tester.tap(find.text('Open protected dialog'));
        await tester.pumpAndSettle();
        if (hard) {
          result = admissionStatus(
            id: accountB,
            step: 'blocked',
            reason: 'account_restricted',
          );
          fixture.emit(AuthChangeEvent.signedIn, mfa.session(user: accountB));
        } else {
          read = () => Future.error(Exception('offline'));
          unawaited(admission.revalidate());
        }
        await tester.pumpAndSettle();
        final action = find.text('Confirm protected mutation');
        if (action.evaluate().isNotEmpty) {
          await tester.tap(action, warnIfMissed: false);
        }
        expect(state.actions, 0);
        expect(state.mounted, !hard);
      },
    );
  }
}

class _ProtectedState extends StatefulWidget {
  final bool useRootNavigator;
  const _ProtectedState({this.useRootNavigator = true});
  @override
  State<_ProtectedState> createState() => _ProtectedStateState();
}

class _ProtectedStateState extends State<_ProtectedState> {
  final focus = FocusNode();
  int actions = 0;
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          focusNode: focus,
          onPressed: () => actions++,
          child: const Text('Protected action'),
        ),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            useRootNavigator: widget.useRootNavigator,
            builder: (_) => AlertDialog(
              actions: [
                TextButton(
                  onPressed: () => actions++,
                  child: const Text('Confirm protected mutation'),
                ),
              ],
            ),
          ),
          child: const Text('Open protected dialog'),
        ),
      ],
    ),
  );
}
