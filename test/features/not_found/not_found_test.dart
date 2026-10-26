import 'dart:async';

import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/features/not_found/not_found.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();

    // Default stubs to prevent null errors
    when(
      () => mockAuthService.isLoggedIn(),
    ).thenAnswer((_) async => AuthenticationResponses.failure);
    when(() => mockAuthService.isEmailVerified()).thenReturn(false);
    when(
      () => mockAuthService.login(any(), any()),
    ).thenAnswer((_) async => AuthenticationResponses.failure);
    when(
      () => mockAuthService.signUp(any(), any(), any()),
    ).thenAnswer((_) async => AuthenticationResponses.failure);
    when(
      () => mockAuthService.resendVerification(),
    ).thenAnswer((_) async => AuthenticationResponses.failure);
    when(
      () => mockAuthService.logout(),
    ).thenAnswer((_) async => Future.value());
    when(() => mockAuthService.getCurrentUserId).thenReturn(null);
    when(
      () => mockAuthService.onAuthChange,
    ).thenAnswer((_) => const Stream<bool>.empty());

    final getIt = GetIt.instance;
    if (getIt.isRegistered<AuthService>()) {
      getIt.unregister<AuthService>();
    }

    getIt.registerSingleton<AuthService>(mockAuthService);
  });

  tearDown(() => GetIt.instance.reset());

  Widget createWidgetUnderTest() {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const NotFound()),
        GoRoute(
          path: '/homePage',
          builder: (context, state) => const Scaffold(body: Text('Home Page')),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(body: Text('Login Page')),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  void mockAuthResponse(AuthenticationResponses response) {
    when(() => mockAuthService.isLoggedIn()).thenAnswer((_) async => response);
  }

  group('NotFoundScreen Widget Tests', () {
    testWidgets('should display 404 error icon', (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.size, 48);
      expect(
        icon.color,
        Theme.of(tester.element(find.byType(NotFound))).colorScheme.error,
      );
    });

    testWidgets('should display 404 - Page Not Found text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('404 - Page Not Found'), findsOneWidget);

      final text = tester.widget<Text>(find.text('404 - Page Not Found'));
      expect(text.style?.fontSize, 22);
      expect(
        text.style?.color,
        Theme.of(tester.element(find.byType(NotFound))).colorScheme.onSurface,
      );
    });

    testWidgets('should display Go to Home button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('Go to Home'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('should navigate to home page when user is logged in', (
      WidgetTester tester,
    ) async {
      mockAuthResponse(AuthenticationResponses.success);

      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Go to Home'));
      await tester.pumpAndSettle();

      expect(find.text('Home Page'), findsOneWidget);
      verify(() => mockAuthService.isLoggedIn()).called(1);
    });

    testWidgets('should navigate to login page when user is not logged in', (
      WidgetTester tester,
    ) async {
      mockAuthResponse(AuthenticationResponses.failure);

      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Go to Home'));
      await tester.pumpAndSettle();

      expect(find.text('Login Page'), findsOneWidget);
      verify(() => mockAuthService.isLoggedIn()).called(1);
    });

    testWidgets('Go to Home button should be tappable', (
      WidgetTester tester,
    ) async {
      mockAuthResponse(AuthenticationResponses.success);

      await tester.pumpWidget(createWidgetUnderTest());

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('should handle auth check when button is pressed', (
      WidgetTester tester,
    ) async {
      mockAuthResponse(AuthenticationResponses.success);

      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Go to Home'));
      await tester.pump();

      verify(() => mockAuthService.isLoggedIn()).called(1);
    });
  });

  group('Deferred auth lifetime', () {
    late Completer<AuthenticationResponses> pending;
    GoRouter? router;
    late List<String> routeChanges;

    tearDown(() {
      router?.dispose();
      router = null;
    });

    Future<void> begin(WidgetTester tester, {bool press = true}) async {
      pending = Completer<AuthenticationResponses>();
      when(
        () => mockAuthService.isLoggedIn(),
      ).thenAnswer((_) => pending.future);
      routeChanges = [];
      router = GoRouter(
        initialLocation: '/unknown',
        errorBuilder: (_, _) => const NotFound(),
        routes: [
          GoRoute(
            path: '/homePage',
            builder: (_, _) => const Scaffold(body: Text('Home fixture')),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('Login fixture')),
          ),
          GoRoute(
            path: '/other',
            builder: (_, _) => const Scaffold(body: Text('Other fixture')),
          ),
        ],
      );
      router!.routerDelegate.addListener(() {
        routeChanges.add(router!.routerDelegate.currentConfiguration.uri.path);
      });
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      expect(find.byType(NotFound), findsOneWidget);
      if (press) {
        await tester.tap(find.text('Go to Home'));
        await tester.pump();
        verify(() => mockAuthService.isLoggedIn()).called(1);
        expect(pending.isCompleted, isFalse);
        expect(
          router!.routerDelegate.currentConfiguration.uri.path,
          '/unknown',
        );
      }
    }

    for (final response in AuthenticationResponses.values) {
      testWidgets('mounted deferred ${response.name} preserves routing', (
        tester,
      ) async {
        await begin(tester);
        pending.complete(response);
        await tester.pumpAndSettle();
        final success = response == AuthenticationResponses.success;
        expect(
          router!.routerDelegate.currentConfiguration.uri.path,
          success ? '/homePage' : '/login',
        );
        expect(
          find.text(success ? 'Home fixture' : 'Login fixture'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'mounted deferred exception retains the existing error contract',
      (tester) async {
        await begin(tester, press: false);
        final context = tester.element(find.byType(NotFound));
        final callback = tester
            .widget<ElevatedButton>(find.byType(ElevatedButton))
            .onPressed!;
        final operation = (callback as Future<void> Function())();
        verify(() => mockAuthService.isLoggedIn()).called(1);
        final notificationsBefore = routeChanges.length;
        final error = StateError('synthetic deferred auth failure');
        final reported = expectLater(operation, throwsA(same(error)));
        pending.completeError(error);
        await reported;
        await tester.pumpAndSettle();
        expect(context.mounted, isTrue);
        expect(
          router!.routerDelegate.currentConfiguration.uri.path,
          '/unknown',
        );
        expect(routeChanges.length, notificationsBefore);
        expect(find.byType(NotFound), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    for (final disposal in ['unmount', 'navigate away']) {
      for (final completion in ['success', 'failure', 'throw']) {
        testWidgets('$disposal then deferred $completion has no late effects', (
          tester,
        ) async {
          await begin(tester);
          final oldContext = tester.element(find.byType(NotFound));
          if (disposal == 'unmount') {
            await tester.pumpWidget(const SizedBox.shrink());
          } else {
            router!.go('/other');
            await tester.pumpAndSettle();
            expect(find.text('Other fixture'), findsOneWidget);
          }
          expect(oldContext.mounted, isFalse);
          final pathBefore =
              router!.routerDelegate.currentConfiguration.uri.path;
          final notificationsBefore = routeChanges.length;
          if (completion == 'throw') {
            pending.completeError(
              StateError('synthetic deferred auth failure'),
            );
          } else {
            pending.complete(
              completion == 'success'
                  ? AuthenticationResponses.success
                  : AuthenticationResponses.failure,
            );
          }
          await tester.pumpAndSettle();
          expect(
            router!.routerDelegate.currentConfiguration.uri.path,
            pathBefore,
          );
          expect(routeChanges.length, notificationsBefore);
          expect(find.byType(NotFound), findsNothing);
          if (disposal == 'navigate away') {
            expect(find.text('Other fixture'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          verifyNoMoreInteractions(mockAuthService);
        });
      }
    }
  });
}
