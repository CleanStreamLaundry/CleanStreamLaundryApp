import 'dart:async';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/login/login.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;

  setUp(() async {
    mockAuthService = MockAuthService();

    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Widget createWidget({ThemeData? theme}) {
    return MaterialApp.router(
      theme: theme,
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Login(),
          ),
          GoRoute(
            path: '/homePage',
            builder: (_, __) => const Scaffold(body: Text('Home Page')),
          ),
          GoRoute(
            path: '/email-verification',
            builder: (_, __) => const Scaffold(body: Text('Verify your email')),
          ),
          GoRoute(
            path: '/signup',
            builder: (_, __) => const Scaffold(body: Text('Sign Up Page')),
          ),
          GoRoute(
            path: '/password-reset',
            builder: (_, __) =>
                const Scaffold(body: Text('Password Reset Page')),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('Login Page')),
          ),
        ],
      ),
    );
  }

  void mockLoginResponse(AuthenticationResponses response) {
    when(
      () => mockAuthService.login(any(), any()),
    ).thenAnswer((_) async => response);
  }

  Future<void> enterCredentials(
    WidgetTester tester, {
    String email = 'test@example.com',
    String password = 'password123',
  }) async {
    await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      password,
    );
  }

  group('Apple sign-in completion', () {
    Future<void> tapApple(WidgetTester tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      final button = find.widgetWithText(ElevatedButton, 'Sign in with Apple');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'native success leaves Login for the protected home route',
      (tester) async {
        when(() => mockAuthService.appleSignIn()).thenAnswer((_) async => true);
        await tapApple(tester);
        expect(find.text('Home Page'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'cancellation stays on Login without an error',
      (tester) async {
        when(() => mockAuthService.appleSignIn()).thenAnswer((_) async => false);
        await tapApple(tester);
        expect(find.text('Home Page'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        final button = find.widgetWithText(ElevatedButton, 'Sign in with Apple');
        expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'provider failure is visible and retryable',
      (tester) async {
        when(() => mockAuthService.appleSignIn())
            .thenThrow(StateError('synthetic failure'));
        await tapApple(tester);
        expect(
          find.text('Apple sign-in could not finish. Please try again.'),
          findsOneWidget,
        );
        expect(find.text('Home Page'), findsNothing);
        final button = find.widgetWithText(ElevatedButton, 'Sign in with Apple');
        expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'pending sign-in blocks duplicate social requests and cancels on departure',
      (tester) async {
        final result = Completer<bool>();
        when(() => mockAuthService.appleSignIn()).thenAnswer((_) => result.future);
        await tapApple(tester);
        final apple = find.widgetWithText(ElevatedButton, 'Sign in with Apple');
        final google = find.widgetWithText(ElevatedButton, 'Sign in with Google');
        expect(tester.widget<ElevatedButton>(apple).onPressed, isNull);
        expect(tester.widget<ElevatedButton>(google).onPressed, isNull);
        await tester.tap(apple);
        verify(() => mockAuthService.appleSignIn()).called(1);
        await tester.pumpWidget(const SizedBox.shrink());
        verify(() => mockAuthService.cancelAppleSignIn()).called(1);
        result.complete(true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Home Page'), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  });

  group('Static UI', () {
    testWidgets('displays logo image with correct dimensions', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byKey(const Key('app_logo')));
      expect((image.image as AssetImage).assetName, 'assets/splash-logo.png');
      expect(image.height, 300);
      expect(image.width, 300);
    });

    testWidgets('displays email and password text fields', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    });

    testWidgets('displays email and lock icons', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.email), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('displays Log In button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ElevatedButton, 'Log In'), findsOneWidget);
    });

    testWidgets('displays Sign in with Google button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(ElevatedButton, 'Sign in with Google'),
        findsOneWidget,
      );
    });

    testWidgets(
      'displays Sign in with Apple button on iOS and macOS',
      (tester) async {
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(ElevatedButton, 'Sign in with Apple'),
          findsOneWidget,
        );
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }),
    );

    testWidgets('displays Create Account link', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('displays Reset Password link', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Reset Password'), findsOneWidget);
    });

    testWidgets('password field is obscured by default', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Password'),
      );
      expect(field.obscureText, isTrue);
    });

    testWidgets('page is scrollable', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('Login functionality', () {
    testWidgets('shows error snackbar when both fields are empty', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pump();

      expect(find.text('Please fill in both fields.'), findsOneWidget);
    });

    testWidgets('shows error snackbar when email is empty', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'password123',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pump();

      expect(find.text('Please fill in both fields.'), findsOneWidget);
    });

    testWidgets('shows error snackbar when password is empty', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'test@example.com',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pump();

      expect(find.text('Please fill in both fields.'), findsOneWidget);
    });

    testWidgets('shows logging in snackbar when credentials entered', (
      tester,
    ) async {
      mockLoginResponse(AuthenticationResponses.success);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pump();

      expect(find.text('Logging in as test@example.com...'), findsOneWidget);
    });

    testWidgets('navigates to home page on successful login', (tester) async {
      mockLoginResponse(AuthenticationResponses.success);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Home Page'), findsOneWidget);
      verify(
        () => mockAuthService.login('test@example.com', 'password123'),
      ).called(1);
    });

    testWidgets('navigates to email verification on unverified email', (
      tester,
    ) async {
      mockLoginResponse(AuthenticationResponses.emailNotVerified);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Verify your email'), findsOneWidget);
    });

    testWidgets('shows error colors on failed login', (tester) async {
      mockLoginResponse(AuthenticationResponses.failure);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid Password or Email'), findsNWidgets(2));

      final emailIcon = tester.widget<Icon>(find.byIcon(Icons.email));
      expect(emailIcon.color, Colors.red);

      final lockIcon = tester.widget<Icon>(find.byIcon(Icons.lock));
      expect(lockIcon.color, Colors.red);
    });

    testWidgets('trims email whitespace before calling login', (tester) async {
      mockLoginResponse(AuthenticationResponses.success);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterCredentials(tester, email: '  test@example.com  ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pumpAndSettle();

      verify(() => mockAuthService.login('test@example.com', any())).called(1);
    });

    testWidgets('error colors persist after subsequent input', (tester) async {
      mockLoginResponse(AuthenticationResponses.failure);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Invalid Password or Email').first,
        'new@example.com',
      );
      await tester.pump();

      final emailIcon = tester.widget<Icon>(find.byIcon(Icons.email));
      expect(emailIcon.color, Colors.red);
    });
  });

  group('Password visibility', () {
    testWidgets('toggles password visibility when suffix icon tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Password'))
            .obscureText,
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Password'))
            .obscureText,
        isFalse,
      );
    });

    testWidgets('shows visibility icon when password is hidden', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);
    });

    testWidgets('shows visibility_off icon when password is shown', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
    });
  });

  group('Navigation', () {
    testWidgets('navigates to sign_up on Create Account tap', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Sign Up Page'), findsOneWidget);
    });

    testWidgets('navigates to password reset on Reset Password tap', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Reset Password'));
      await tester.tap(find.text('Reset Password'));
      await tester.pumpAndSettle();

      expect(find.text('Password Reset Page'), findsOneWidget);
    });
  });

  group('Keyboard enter', () {
    testWidgets('pressing Enter triggers login', (tester) async {
      when(
        () => mockAuthService.login(any(), any()),
      ).thenAnswer((_) async => AuthenticationResponses.success);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'test@example.com');
      await tester.enterText(find.byType(TextField).last, 'password123');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Logging in as test@example.com'),
        findsOneWidget,
      );
    });
  });

  testWidgets('mounts with AuthService alone without consuming callbacks', (
    tester,
  ) async {
    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.text('Home Page'), findsNothing);
    verifyZeroInteractions(mockAuthService);
  });

  group('Styling', () {
    testWidgets('Log In button has primary background and white text', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget(theme: lightMode));
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Log In'),
      );
      expect(
        button.style?.backgroundColor?.resolve({}),
        lightMode.colorScheme.primary,
      );
      expect(button.style?.foregroundColor?.resolve({}), Colors.white);
    });

    for (final theme in [lightMode, darkMode]) {
      final mode = theme.brightness.name;

      void expectReadableButton(WidgetTester tester) {
        final button = find.widgetWithText(ElevatedButton, 'Log In');
        final material = tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)),
        );
        final foreground = DefaultTextStyle.of(
          tester.element(find.text('Log In')),
        ).style.color!;
        final backgroundLuminance = material.color!.computeLuminance();
        final foregroundLuminance = foreground.computeLuminance();
        expect(
          (foregroundLuminance + 0.05) / (backgroundLuminance + 0.05),
          greaterThanOrEqualTo(4.5),
        );
        expect(material.color, theme.colorScheme.primary);
        expect(foreground, Colors.white);
      }

      testWidgets('$mode enabled Log In button is readable', (tester) async {
        await tester.pumpWidget(createWidget(theme: theme));
        await tester.pumpAndSettle();

        final button = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Log In'),
        );
        expect(button.onPressed, isNotNull);
        expectReadableButton(tester);
        verifyZeroInteractions(mockAuthService);
      });

      testWidgets('$mode pending login preserves button and completion', (
        tester,
      ) async {
        final response = Completer<AuthenticationResponses>();
        when(() => mockAuthService.login(any(), any()))
            .thenAnswer((_) => response.future);
        await tester.pumpWidget(createWidget(theme: theme));
        await tester.pumpAndSettle();
        await enterCredentials(tester);
        final button = find.widgetWithText(ElevatedButton, 'Log In');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(button);
        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.getRect(button), bounds);
        expectReadableButton(tester);
        expect(find.text('Home Page'), findsNothing);
        verify(() => mockAuthService.login('test@example.com', 'password123'))
            .called(1);

        response.complete(AuthenticationResponses.success);
        await tester.pumpAndSettle();
        expect(find.text('Home Page'), findsOneWidget);
        verifyNoMoreInteractions(mockAuthService);
      });
    }

    testWidgets('Create Account text is blue and underlined', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('Create Account'));
      expect(text.style?.color, Colors.blue);
      expect(text.style?.decoration, TextDecoration.underline);
    });

    testWidgets('email field has rounded border', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Email'),
      );
      final border =
          (field.decoration as InputDecoration).border as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(12));
    });
  });
}
