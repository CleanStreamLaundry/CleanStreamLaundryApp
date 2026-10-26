import 'dart:async';

import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/loading/loading.dart';
import 'package:clean_stream_laundry_app/features/login/login.dart';
import 'package:clean_stream_laundry_app/features/not_found/not_found.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../features/loading/mocks.dart';

class MockProfileService extends Mock implements ProfileService {}

void main() {
  late MockAuthService auth;
  late GoRouter router;
  const messages = MethodChannel('com.llfbandit.app_links/messages');
  const events = MethodChannel('com.llfbandit.app_links/events');

  setUpAll(() => registerFallbackValue(Uri()));
  setUp(() {
    auth = MockAuthService();
    when(
      () => auth.isLoggedIn(),
    ).thenAnswer((_) async => AuthenticationResponses.failure);
    when(() => auth.getSessionFromURI(any())).thenAnswer((_) async {});
    when(() => auth.onAuthChange).thenAnswer((_) => const Stream.empty());
    GetIt.I.registerSingleton<AuthService>(auth);
    GetIt.I.registerSingleton<ProfileService>(MockProfileService());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(messages, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (_) async => null);
    router = RouterService().createRouter(auth);
  });
  tearDown(() async {
    router.dispose();
    await GetIt.I.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(messages, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, null);
  });

  Future<RouteMatchList> parse(
    WidgetTester tester,
    String location, {
    Object? extra,
  }) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    router.go(location, extra: extra);
    return router.routeInformationParser.parseRouteInformationWithDependencies(
      router.routeInformationProvider.value,
      context,
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final theme in [lightMode, darkMode]) {
      for (final location in ['/loading', 'clean-stream://oauth?code=startup']) {
        testWidgets(
          'startup handoff has no outgoing transition: '
          '${platform.name}/${theme.brightness.name}/$location',
          (tester) async {
            final session = Completer<AuthenticationResponses>();
            when(() => auth.isLoggedIn()).thenAnswer((_) => session.future);
            router.go(location);
            await tester.pumpWidget(
              MaterialApp.router(
                theme: theme.copyWith(platform: platform),
                routerConfig: router,
              ),
            );
            await tester.pump();
            final loadingRoute = ModalRoute.of(
              tester.element(find.byType(LoadingPage)),
            )!;
            final forward = loadingRoute.transitionDuration;
            final reverse = loadingRoute.reverseTransitionDuration;

            session.complete(AuthenticationResponses.failure);
            await tester.pump();
            await tester.pump();

            expect(forward, Duration.zero);
            expect(reverse, Duration.zero);
            expect(find.byType(LoadingPage, skipOffstage: false), findsNothing);
            expect(find.byType(Login), findsOneWidget);
            final loginRoute = ModalRoute.of(tester.element(find.byType(Login)))!;
            expect(loginRoute.animation!.status, AnimationStatus.completed);
            expect(router.routeInformationProvider.value.uri.path, '/login');
            verify(() => auth.isLoggedIn()).called(1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'prelogin legal route uses only the public descriptor without auth navigation',
    (tester) async {
      final profile = GetIt.I<ProfileService>() as MockProfileService;
      when(() => profile.getLoyaltyPolicyDescriptor()).thenAnswer(
        (_) async => LoyaltyPolicyDescriptor.fromJson({
          'required_version': 'review-only-synthetic',
          'policy_text': 'abc',
          'policy_sha256':
              'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        }),
      );
      router.go('/legal/loyalty-card');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/legal/loyalty-card',
      );
      expect(find.text('abc'), findsOneWidget);
      expect(find.byType(Login), findsNothing);
      verify(() => profile.getLoyaltyPolicyDescriptor()).called(1);
      verifyNoMoreInteractions(profile);
      verifyZeroInteractions(auth);
    },
  );

  for (final entry in {
    '/': '/loading',
    '/loading': '/loading',
    'clean-stream://oauth?code=a%2Bb#provider_token=fake':
        '/auth-callback/oauth',
    'clean-stream://reset-protected?code=a%2Bb#access_token=fake':
        '/auth-callback/reset-protected',
    'clean-stream://email-verification?code=a%2Bb#access_token=fake':
        '/auth-callback/email-verification',
    'clean-stream://change-email?type=email_change&code=a%2Bb#access_token=fake':
        '/auth-callback/change-email',
    'https://cleanstreamlaundry.com/pay?machine=a%2Bb&terminal=12&uniqr=fake':
        '/pay',
    '/loading?code=web-code': '/auth-callback/oauth',
    '/loading?error=access_denied&error_description=canceled':
        '/auth-callback/oauth',
  }.entries) {
    testWidgets(
      'real router resolves ${entry.key} without 404 or payload loss',
      (tester) async {
        final original = Uri.parse(entry.key);
        final matches = await parse(tester, entry.key);
        expect(matches.isError, isFalse);
        expect(matches.uri.path, entry.value);
        expect(matches.uri.query, original.query);
        expect(matches.uri.fragment, original.fragment);
      },
    );
  }

  for (final location in [
    'https://oauth?code=abc',
    'https://change-email/editProfile',
    'https://cleanstreamlaundry.com/homePage',
    'https://evil.example/pay?machine=fake',
    'http://cleanstreamlaundry.com/pay?machine=fake',
    'clean-stream://oauth.evil/homePage',
    'clean-stream://user@oauth?code=abc',
    'clean-stream://oauth:123?code=abc',
    'clean-stream://oauth/homePage',
    'clean-stream://change-email?type=recovery',
    'clean-stream://change-email#type=recovery',
    'clean-stream://change-email?type=recovery&type=email_change',
    'clean-stream://change-email?type=email_change#type=recovery',
    '/unknown-route',
  ]) {
    testWidgets(
      'invalid route does not enter an auth/protected flow: $location',
      (tester) async {
        final matches = await parse(tester, location);
        expect(matches.isError, isTrue);
        verifyNever(() => auth.getSessionFromURI(any()));
        verifyNever(() => auth.isLoggedIn());
      },
    );
  }

  for (final location in [
    '/reset-protected',
    '/email-verification',
    '/verify-code',
    '/change-email-verification',
    '/password-reset',
    '/login',
    '/pay?machine=a%2Bb&terminal=12&uniqr=fake',
    '/loyalty?loadCard=true',
  ]) {
    testWidgets('existing internal flow and extra survive: $location', (
      tester,
    ) async {
      final matches = await parse(
        tester,
        location,
        extra: 'person@example.test',
      );
      expect(matches.isError, isFalse);
      expect(matches.uri, Uri.parse(location));
      expect(matches.extra, 'person@example.test');
    });
  }

  for (final warm in [false, true]) {
    testWidgets(
      '${warm ? 'warm' : 'cold'} router OAuth stays loading until exchange then checks session',
      (tester) async {
        final uri = Uri.parse(
          'clean-stream://oauth?code=a%2Bb#provider_token=fake',
        );
        final exchange = Completer<void>();
        when(
          () => auth.getSessionFromURI(uri),
        ).thenAnswer((_) => exchange.future);
        router.go(warm ? '/login' : uri.toString(), extra: warm ? null : uri);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump();
        if (warm) {
          router.go(uri.toString(), extra: uri);
          await tester.pump();
          await tester.pump();
        }
        final loading = find.byType(LoadingPage).evaluate().length;
        final notFound = find.byType(NotFound).evaluate().length;
        exchange.complete();
        await tester.pump();
        await tester.pump();
        expect(loading, 1);
        expect(notFound, 0);
        expect(find.byType(Login), findsOneWidget);
        expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
        verify(() => auth.getSessionFromURI(uri)).called(1);
        verify(() => auth.isLoggedIn()).called(1);
      },
    );
  }

  testWidgets('navigation away during OAuth prevents late redirect', (
    tester,
  ) async {
    final exchange = Completer<void>();
    exchange.future.ignore();
    when(
      () => auth.getSessionFromURI(any()),
    ).thenAnswer((_) => exchange.future);
    router.go('clean-stream://oauth?code=abc');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    router.go('/password-reset');
    await tester.pump();
    exchange.completeError(Exception('late exchange failure'));
    await tester.pump();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/password-reset',
    );
    expect(tester.takeException(), isNull);
  });
}
