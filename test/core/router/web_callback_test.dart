@TestOn('browser')
library;

import 'dart:async';
import 'dart:ui_web' as web;

import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/root_app.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/home/mocks.dart'
    show
        MockProfileService,
        MockLocationService,
        MockMachineService,
        MockWalletService;
import '../../features/loading/mocks.dart';
import '../../services/supabase/authentication/mocks.dart';

// All callback payloads below are inert fixtures. Auth is mocked throughout.
void main() {
  const browser = web.BrowserPlatformLocation();
  final originalDocument = Uri.base;
  final originalHistoryState = browser.state;
  late MockAuthService auth;
  late MockProfileService profile;
  late MockAppLinks links;
  late StreamController<Uri> incoming;
  late ThemeManager theme;
  GoRouter? router;

  setUpAll(() => registerFallbackValue(Uri()));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = MockAuthService();
    profile = MockProfileService();
    links = MockAppLinks();
    incoming = StreamController<Uri>.broadcast();
    when(() => links.uriLinkStream).thenAnswer((_) => incoming.stream);
    when(() => links.getInitialLink()).thenAnswer((_) async => Uri.base);
    when(
      () => auth.isLoggedIn(),
    ).thenAnswer((_) async => AuthenticationResponses.failure);
    when(() => auth.onAuthChange).thenAnswer((_) => const Stream.empty());
    when(() => auth.getSessionFromURI(any())).thenAnswer((_) async {});
    when(() => auth.getCurrentUser()).thenReturn(
      User(
        id: 'synthetic-user',
        appMetadata: {},
        userMetadata: {'full_name': 'Test Person'},
        aud: 'authenticated',
        createdAt: '',
      ),
    );
    when(
      () => profile.createAccount(
        id: any(named: 'id'),
        name: any(named: 'name'),
      ),
    ).thenAnswer((_) async {});
    final locations = MockLocationService();
    // Keep Home's map unbuilt so browser tests never request map tiles.
    when(
      () => locations.getLocations(),
    ).thenAnswer((_) => Completer<List<Map<String, dynamic>>>().future);
    GetIt.I.registerSingleton<AuthService>(auth);
    GetIt.I.registerSingleton<ProfileService>(profile);
    GetIt.I.registerSingleton<LocationService>(locations);
    GetIt.I.registerSingleton<MachineService>(MockMachineService());
    final wallet = MockWalletService();
    when(
      () => wallet.getBalance(),
    ).thenAnswer((_) async => WalletBalance.empty());
    GetIt.I.registerSingleton<WalletService>(wallet);
    theme = ThemeManager();
  });

  tearDown(() async {
    router?.dispose();
    router = null;
    await incoming.close();
    theme.dispose();
    await GetIt.I.reset();
    browser.replaceState(originalHistoryState, '', originalDocument.toString());
  });

  void document(String suffix) {
    browser.replaceState(
      'synthetic-history-state',
      '',
      '${originalDocument.origin}/embedded/app/index.html$suffix',
    );
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Read the real document through Flutter's production hash strategy.
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        const web.HashUrlStrategy().getPath();
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    router = RouterService().createRouter(auth, appLinks: links);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: RootApp(router: router!, appLinks: links),
      ),
    );
    await tester.pump();
  }

  String route() => router!.routerDelegate.currentConfiguration.uri.toString();

  Future<void> finishNavigation(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final signedIn in [false, true]) {
    for (final outcome in ['success', 'invalid-session', 'failure']) {
      for (final fragment in ['', '#/loading', '#/']) {
        testWidgets(
          'document PKCE $outcome signedIn=$signedIn with entry fragment "$fragment"',
          (tester) async {
            document('?tenant=demo&code=synthetic-code$fragment');
            final exchange = Completer<void>();
            final callback = Uri.parse(
              'clean-stream://oauth?tenant=demo&code=synthetic-code',
            );
            when(
              () => auth.getSessionFromURI(callback),
            ).thenAnswer((_) => exchange.future);
            // A stale cached session must never rescue a failed callback.
            when(() => auth.isLoggedIn()).thenAnswer(
              (_) async => signedIn
                  ? AuthenticationResponses.success
                  : AuthenticationResponses.failure,
            );
            await mount(tester);
            printOnFailure(
              'Pending callback route: ${router!.routerDelegate.currentConfiguration.uri.path}',
            );
            expect(route(), '/loading');
            verifyNever(() => auth.isLoggedIn());
            incoming.add(callback);
            await tester.pump();
            expect(route(), '/loading');
            expect(Uri.base.queryParameters, {'tenant': 'demo'});
            expect(Uri.base.path, '/embedded/app/index.html');

            when(() => auth.isLoggedIn()).thenAnswer(
              (_) async => outcome == 'invalid-session'
                  ? AuthenticationResponses.failure
                  : AuthenticationResponses.success,
            );
            if (outcome == 'failure') {
              exchange.completeError(StateError('Synthetic rejected exchange'));
            } else {
              exchange.complete();
            }
            await finishNavigation(tester);
            final destination = outcome == 'success' ? '/homePage' : '/login';
            expect(route(), destination);
            incoming.add(callback);
            await finishNavigation(tester);
            expect(route(), destination);
            verify(() => auth.getSessionFromURI(callback)).called(1);
            verifyNever(() => links.getInitialLink());
            if (outcome == 'failure') {
              verifyNever(() => auth.isLoggedIn());
            } else {
              verify(() => auth.isLoggedIn()).called(1);
            }
            if (outcome == 'success') {
              verify(
                () => profile.createAccount(
                  id: 'synthetic-user',
                  name: 'Test Person',
                ),
              ).called(1);
            } else {
              verifyNever(
                () => profile.createAccount(
                  id: any(named: 'id'),
                  name: any(named: 'name'),
                ),
              );
            }
            expect(Uri.base.queryParameters, {'tenant': 'demo'});
            expect(
              Uri.base.fragment,
              fragment.isEmpty ? '' : fragment.substring(1),
            );

            // A new router sees the cleaned document, not a replayable callback.
            await tester.pumpWidget(const SizedBox());
            router!.dispose();
            router = null;
            clearInteractions(auth);
            await mount(tester);
            await finishNavigation(tester);
            verifyNever(() => auth.getSessionFromURI(any()));
          },
        );
      }
    }
  }

  testWidgets('raw provider error is consumed once and fails closed', (
    tester,
  ) async {
    document('?tenant=demo#error=synthetic-error&error_description=denied');
    final callback = Uri.parse(
      'clean-stream://oauth?tenant=demo#error=synthetic-error&error_description=denied',
    );
    when(
      () => auth.getSessionFromURI(callback),
    ).thenThrow(StateError('Synthetic denied callback'));
    when(
      () => auth.isLoggedIn(),
    ).thenAnswer((_) async => AuthenticationResponses.success);
    await mount(tester);
    await finishNavigation(tester);
    printOnFailure(
      'Provider-error route: ${router!.routerDelegate.currentConfiguration.uri.path}',
    );
    expect(route(), '/login');
    verify(() => auth.getSessionFromURI(callback)).called(1);
    verifyNever(() => auth.isLoggedIn());
    expect(Uri.base.queryParameters, {'tenant': 'demo'});
    expect(Uri.base.fragment, '');
  });

  test('capture strips only auth fields and preserves history state', () {
    document(
      '?tenant=one%20two&tenant=three+four&code=synthetic-code&code=synthetic-code-2#/loading',
    );
    router = RouterService().createRouter(auth, appLinks: links);
    expect(Uri.base.query, 'tenant=one%20two&tenant=three+four');
    expect(Uri.base.path, '/embedded/app/index.html');
    expect(Uri.base.fragment, '/loading');
    expect(browser.state, 'synthetic-history-state');
  });

  for (final (label, payload) in [
    (
      'top-query-error',
      '?tenant=demo&error=synthetic-error&error_description=denied#/loading',
    ),
    (
      'top-query-tokens',
      '?tenant=demo&access_token=fake&refresh_token=fake&expires_in=60&expires_at=60&token_type=bearer&provider_token=fake&provider_refresh_token=fake&type=signup#/loading',
    ),
    (
      'fragment-tokens',
      '?tenant=demo#access_token=fake&refresh_token=fake&expires_in=60&token_type=bearer',
    ),
    ('hash-route-code', '?tenant=demo#/loading?code=synthetic-code'),
  ]) {
    testWidgets('$label is rejected once with cleanup', (tester) async {
      document(payload);
      final original = Uri.base;
      final hashRoute = original.fragment.startsWith('/')
          ? Uri.parse(original.fragment)
          : null;
      final query = [
        original.query,
        if (hashRoute != null) hashRoute.query,
      ].where((part) => part.isNotEmpty).join('&');
      final fragment = hashRoute?.fragment ?? original.fragment;
      final callback = Uri(
        scheme: 'clean-stream',
        host: 'oauth',
        query: query,
        fragment: fragment.isEmpty ? null : fragment,
      );
      when(
        () => auth.getSessionFromURI(callback),
      ).thenThrow(StateError('Synthetic rejected callback'));
      when(
        () => auth.isLoggedIn(),
      ).thenAnswer((_) async => AuthenticationResponses.success);
      await mount(tester);
      await finishNavigation(tester);
      expect(route(), '/login');
      verify(() => auth.getSessionFromURI(callback)).called(1);
      verifyNever(() => auth.isLoggedIn());
      expect(Uri.base.query, 'tenant=demo');
      expect(Uri.base.fragment, hashRoute?.path ?? '');
      await tester.pumpWidget(const SizedBox());
      router!.dispose();
      router = null;
      clearInteractions(auth);
      await mount(tester);
      await finishNavigation(tester);
      verifyNever(() => auth.getSessionFromURI(any()));
    });
  }

  testWidgets(
    'malformed auth value is cleaned and cannot use a cached session',
    (tester) async {
      document('?tenant=demo&code=%C0%AF#/loading');
      when(
        () => auth.isLoggedIn(),
      ).thenAnswer((_) async => AuthenticationResponses.success);
      await mount(tester);
      await finishNavigation(tester);
      expect(route(), '/login');
      verifyNever(() => auth.getSessionFromURI(any()));
      verifyNever(() => auth.isLoggedIn());
      expect(Uri.base.query, 'tenant=demo');
    },
  );

  for (final fails in [false, true]) {
    testWidgets('dispose during exchange, failure=$fails', (tester) async {
      document('?tenant=demo&code=synthetic-code#/loading');
      final exchange = Completer<void>();
      when(
        () => auth.getSessionFromURI(any()),
      ).thenAnswer((_) => exchange.future);
      await mount(tester);
      expect(route(), '/loading');
      expect(incoming.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(incoming.hasListener, isFalse);
      if (fails) {
        exchange.completeError(StateError('Synthetic late rejection'));
      } else {
        exchange.complete();
      }
      await finishNavigation(tester);
      expect(route(), '/loading');
      verify(() => auth.getSessionFromURI(any())).called(1);
      verifyNever(() => auth.isLoggedIn());
      expect(Uri.base.query, 'tenant=demo');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('leaving Loading during verification prevents late Home', (
    tester,
  ) async {
    document('?code=synthetic-code#/loading');
    final verified = Completer<AuthenticationResponses>();
    when(() => auth.isLoggedIn()).thenAnswer((_) => verified.future);
    await mount(tester);
    expect(route(), '/loading');
    router!.go('/login');
    await finishNavigation(tester);
    verified.complete(AuthenticationResponses.success);
    await finishNavigation(tester);
    expect(route(), '/login');
    verify(() => auth.getSessionFromURI(any())).called(1);
    verify(() => auth.isLoggedIn()).called(1);
    verifyNever(
      () => profile.createAccount(
        id: any(named: 'id'),
        name: any(named: 'name'),
      ),
    );
  });

  for (final signedIn in [false, true]) {
    testWidgets('normal web entry, signedIn=$signedIn', (tester) async {
      document('?tenant=demo#/loading');
      when(() => auth.isLoggedIn()).thenAnswer(
        (_) async => signedIn
            ? AuthenticationResponses.success
            : AuthenticationResponses.failure,
      );
      await mount(tester);
      await finishNavigation(tester);
      expect(route(), signedIn ? '/homePage' : '/login');
      verify(() => auth.isLoggedIn()).called(1);
      verify(() => links.getInitialLink()).called(1);
      verifyNever(() => auth.getSessionFromURI(any()));
      expect(Uri.base.query, 'tenant=demo');
    });
  }

  testWidgets('incoming HTTP auth URLs are not document callbacks', (
    tester,
  ) async {
    document('#/loading');
    await mount(tester);
    await finishNavigation(tester);
    clearInteractions(auth);
    for (final origin in [
      originalDocument.origin,
      'https://external.invalid',
    ]) {
      final external = Uri.parse('$origin/?code=synthetic-code');
      incoming.add(external);
      await finishNavigation(tester);
      expect(route(), '/login');
      router!.go(external.toString());
      await finishNavigation(tester);
      expect(route(), '/not-found');
      router!.go('/login');
      await finishNavigation(tester);
    }
    verifyNever(() => auth.getSessionFromURI(any()));
    verifyNever(() => auth.isLoggedIn());
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final path in ['/', '/embedded/app/', '/embedded/app/index.html']) {
      for (final provider in [OAuthProvider.google, OAuthProvider.apple]) {
        test(
          'web redirect preserves $path for $provider on $platform',
          () async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            browser.replaceState(
              null,
              '',
              '${originalDocument.origin}$path?tenant=demo#/login',
            );
            final client = SupabaseMock();
            final sdk = GoTrueMock();
            when(() => client.auth).thenReturn(sdk);
            final stopBeforeLaunch = StateError('Mocked OAuth URL boundary');
            final expected = '${originalDocument.origin}$path#/loading';
            when(
              () => sdk.getOAuthSignInUrl(
                provider: provider,
                redirectTo: expected,
              ),
            ).thenThrow(stopBeforeLaunch);
            final service = SupabaseAuthService(client: client);
            await expectLater(
              provider == OAuthProvider.google
                  ? service.googleSignIn()
                  : service.appleSignIn(),
              throwsA(same(stopBeforeLaunch)),
            );
            verify(
              () => sdk.getOAuthSignInUrl(
                provider: provider,
                redirectTo: expected,
              ),
            ).called(1);
          },
        );
      }
    }
  }

  for (final fragment in [
    'section',
    '/settings',
    '/loading/other',
    '/pay?machine=demo',
  ]) {
    test('unsupported document fragment is untouched: $fragment', () {
      document('?tenant=demo&code=synthetic-code#$fragment');
      final before = Uri.base;
      router = RouterService().createRouter(auth, appLinks: links);
      expect(Uri.base, before);
      verifyNever(() => auth.getSessionFromURI(any()));
      expect(browser.state, 'synthetic-history-state');
    });
  }
}
