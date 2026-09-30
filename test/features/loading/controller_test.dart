import 'package:clean_stream_laundry_app/features/loading/controller.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

Future<List<String>> _runInit(
    LoadingPageController controller, {
      bool mounted = true,
    }) async {
  final routes = <String>[];
  await controller.init(
    navigate: (route, {extra}) => routes.add(route),
    isMounted: () => mounted,
  );
  return routes;
}

void main() {
  late MockAuthService mockAuth;
  late MockAppLinks mockAppLinks;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    mockAuth = MockAuthService();
    mockAppLinks = MockAppLinks();

    when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => null);
    when(() => mockAuth.onAuthChange).thenAnswer((_) => const Stream.empty());
  });

  group('_automaticLogIn', () {
    test('navigates to /homePage when auth returns success', () async {
      when(() => mockAuth.isLoggedIn())
          .thenAnswer((_) async => AuthenticationResponses.success);

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      final routes = await _runInit(controller);

      expect(routes, ['/homePage']);
    });

    test('navigates to /login when auth returns non-success', () async {
      when(() => mockAuth.isLoggedIn())
          .thenAnswer((_) async => AuthenticationResponses.failure);

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      final routes = await _runInit(controller);

      expect(routes, ['/login']);
    });

    test('sets error and notifies listeners when auth throws', () async {
      when(() => mockAuth.isLoggedIn()).thenThrow(Exception('network error'));

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      bool notified = false;
      controller.addListener(() => notified = true);

      await _runInit(controller);

      expect(controller.error, isNotNull);
      expect(controller.error, contains('network error'));
      expect(notified, isTrue);
    });

    test('does not navigate when isMounted returns false', () async {
      when(() => mockAuth.isLoggedIn())
          .thenAnswer((_) async => AuthenticationResponses.success);

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      final routes = await _runInit(controller, mounted: false);

      expect(routes, isEmpty);
    });

    test('does not set error when unmounted and auth throws', () async {
      when(() => mockAuth.isLoggedIn()).thenThrow(Exception('oops'));

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      await _runInit(controller, mounted: false);

      expect(controller.error, isNull);
    });
  });

  group('_coldStartRedirect with no deep link', () {
    test('does not produce a cold-start navigation when initialUri is null',
            () async {
          when(() => mockAuth.isLoggedIn())
              .thenAnswer((_) async => AuthenticationResponses.success);
          when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => null);

          final controller = LoadingPageController(
            authService: mockAuth,
            appLinks: mockAppLinks,
          );

          final routes = await _runInit(controller);

          expect(routes, equals(['/homePage']));
        });
  });

  group('_coldStartRedirect – reset-protected URI', () {
    test('navigates to /reset-protected and passes URI as extra', () async {
      final uri = Uri.parse('clean-stream://reset-protected?token=abc');
      when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => uri);
      when(() => mockAuth.isLoggedIn())
          .thenAnswer((_) async => AuthenticationResponses.failure);

      final capturedExtras = <Object?>[];
      final routes = <String>[];

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      await controller.init(
        navigate: (route, {extra}) {
          routes.add(route);
          capturedExtras.add(extra);
        },
        isMounted: () => true,
      );

      expect(routes, ['/reset-protected?token=abc']);
      expect(capturedExtras, [uri]);
    });
  });

  group('_coldStartRedirect – email-verification URI', () {
    test('navigates to the OTP page for email-verification deep link', () async {
      final uri = Uri.parse('clean-stream://email-verification');
      when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => uri);
      when(() => mockAuth.isLoggedIn())
          .thenAnswer((_) async => AuthenticationResponses.failure);

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      final routes = await _runInit(controller);

      expect(routes, ['/email-verification']);
    });
  });

  group('_coldStartRedirect – change-email URI', () {
    test('rejects the wrong scheme for change-email deep link',
            () async {
          final uri = Uri.parse('https://change-email');
          when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => uri);
          when(() => mockAuth.isLoggedIn())
              .thenAnswer((_) async => AuthenticationResponses.failure);

          final controller = LoadingPageController(
            authService: mockAuth,
            appLinks: mockAppLinks,
          );

          final routes = await _runInit(controller);

          expect(routes, ['/login']);
        });
  });

  group('_coldStartRedirect – oauth URI', () {
    test('rejects OAuth success without a current user after one exchange',
            () async {
          final uri = Uri.parse('clean-stream://oauth?code=xyz');
          when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => uri);
          when(() => mockAuth.getSessionFromURI(uri)).thenAnswer((_) async {});
          when(() => mockAuth.isLoggedIn())
              .thenAnswer((_) async => AuthenticationResponses.success);

          final controller = LoadingPageController(
            authService: mockAuth,
            appLinks: mockAppLinks,
          );

          final routes = await _runInit(controller);

          verify(() => mockAuth.getSessionFromURI(uri)).called(1);
          expect(routes, ['/login']);
        });

    test('navigates to /login after oauth when session is not valid', () async {
      final uri = Uri.parse('clean-stream://oauth?code=xyz');
      when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => uri);
      when(() => mockAuth.getSessionFromURI(uri)).thenAnswer((_) async {});
      when(() => mockAuth.isLoggedIn())
          .thenAnswer((_) async => AuthenticationResponses.failure);

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      final routes = await _runInit(controller);

      expect(routes, ['/login']);
    });

    test('does not navigate oauth redirect when unmounted', () async {
      final uri = Uri.parse('clean-stream://oauth?code=xyz');
      when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => uri);
      when(() => mockAuth.getSessionFromURI(uri)).thenAnswer((_) async {});
      when(() => mockAuth.isLoggedIn())
          .thenAnswer((_) async => AuthenticationResponses.success);

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      final routes = await _runInit(controller, mounted: false);

      expect(routes, isEmpty);
    });
  });

  group('_coldStartRedirect error handling', () {
    test('swallows exceptions silently and does not expose error', () async {
      when(() => mockAppLinks.getInitialLink())
          .thenThrow(Exception('link error'));
      when(() => mockAuth.isLoggedIn())
          .thenAnswer((_) async => AuthenticationResponses.failure);

      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );

      await expectLater(_runInit(controller), completes);
      expect(controller.error, isNull);
    });
  });

  group('disposeController', () {
    test('can be called without throwing', () {
      final controller = LoadingPageController(
        authService: mockAuth,
        appLinks: mockAppLinks,
      );
      expect(() => controller.disposeController(), returnsNormally);
    });
  });
}
