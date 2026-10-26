import 'dart:async';
import 'package:clean_stream_laundry_app/features/password_reset/password_reset.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:flutter/material.dart';
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

  Widget createWidget() {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/password-reset',
        routes: [
          GoRoute(
            path: '/password-reset',
            builder: (_, __) => const PasswordResetPage(),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) =>
            const Scaffold(body: Text('Login Page')),
          ),
          GoRoute(
            path: '/verify-code',
            builder: (_, __) =>
            const Scaffold(body: Text('Verify Code Page')),
          ),
        ],
      ),
    );
  }

  group('Static UI', () {
    testWidgets('displays Reset Password appbar title', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.text('Reset Password'), findsOneWidget);
    });

    testWidgets('displays Forgot your password heading', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.text('Forgot your password?'), findsOneWidget);
    });

    testWidgets('displays instruction text', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(
        find.text('Enter your email address and we\'ll send you a 6-digit reset code.'),
        findsOneWidget,
      );
    });

    testWidgets('displays email text field', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('displays Send Reset Code button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.text('Send Reset Code'), findsOneWidget);
    });

    testWidgets('displays Back to Login text button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.text('Back to Login'), findsOneWidget);
    });

    testWidgets('displays lock_reset icon', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_reset), findsOneWidget);
    });

    testWidgets('displays email prefix icon', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.email), findsOneWidget);
    });

    testWidgets('displays back arrow', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('Form validation', () {
    testWidgets('shows error for empty email', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('shows error for invalid email format', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter a valid email address'),
        findsOneWidget,
      );
    });

    testWidgets('does not call service when email is invalid', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();

      verifyNever(() => mockAuthService.resetPassword(any()));
    });
  });


  group('Send reset email', () {
    testWidgets('calls resetPassword with trimmed email on valid submit',
            (tester) async {
          when(() => mockAuthService.resetPassword(any()))
              .thenAnswer((_) async => AuthenticationResponses.success);

          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await tester.enterText(
              find.byType(TextFormField), '  test@example.com  ');
          await tester.tap(find.text('Send Reset Code'));
          await tester.pumpAndSettle();

          verify(() => mockAuthService.resetPassword('test@example.com'))
              .called(1);
        });

    testWidgets('shows success snackbar on success', (tester) async {
      when(() => mockAuthService.resetPassword(any()))
          .thenAnswer((_) async => AuthenticationResponses.success);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'test@example.com');
      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();

      expect(
        find.text('Password reset email sent! Check your email.'),
        findsOneWidget,
      );
    });

    testWidgets('navigates to /verify-code on success', (tester) async {
      when(() => mockAuthService.resetPassword(any()))
          .thenAnswer((_) async => AuthenticationResponses.success);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'test@example.com');
      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();

      expect(find.text('Verify Code Page'), findsOneWidget);
    });

    testWidgets('shows failure snackbar when service returns failure',
            (tester) async {
          when(() => mockAuthService.resetPassword(any()))
              .thenAnswer((_) async => AuthenticationResponses.failure);

          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await tester.enterText(
              find.byType(TextFormField), 'test@example.com');
          await tester.tap(find.text('Send Reset Code'));
          await tester.pumpAndSettle();

          expect(find.text('Failed to send reset email.'), findsOneWidget);
        });

    testWidgets('shows error snackbar when service throws', (tester) async {
      when(() => mockAuthService.resetPassword(any()))
          .thenThrow(Exception('network'));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'test@example.com');
      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('shows loading indicator while request is in flight',
            (tester) async {
          final completer = Completer<AuthenticationResponses>();
          when(() => mockAuthService.resetPassword(any()))
              .thenAnswer((_) => completer.future);

          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await tester.enterText(
              find.byType(TextFormField), 'test@example.com');
          await tester.tap(find.text('Send Reset Code'));
          await tester.pump();

          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text('Send Reset Code'), findsNothing);

          completer.complete(AuthenticationResponses.success);
          await tester.pumpAndSettle();
        });

    testWidgets('disables text field while loading', (tester) async {
      final completer = Completer<AuthenticationResponses>();
      when(() => mockAuthService.resetPassword(any()))
          .thenAnswer((_) => completer.future);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'test@example.com');
      await tester.tap(find.text('Send Reset Code'));
      await tester.pump();

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.enabled, isFalse);

      completer.complete(AuthenticationResponses.success);
      await tester.pumpAndSettle();
    });

    testWidgets('disables Back to Login while loading', (tester) async {
      final completer = Completer<AuthenticationResponses>();
      when(() => mockAuthService.resetPassword(any()))
          .thenAnswer((_) => completer.future);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'test@example.com');
      await tester.tap(find.text('Send Reset Code'));
      await tester.pump();

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Back to Login'),
      );
      expect(button.onPressed, isNull);

      completer.complete(AuthenticationResponses.success);
      await tester.pumpAndSettle();
    });
  });

  group('Navigation', () {
    testWidgets('Back to Login button navigates to /login', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to Login'));
      await tester.pumpAndSettle();

      expect(find.text('Login Page'), findsOneWidget);
    });

    testWidgets('back arrow navigates to /login', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Login Page'), findsOneWidget);
    });
  });
}