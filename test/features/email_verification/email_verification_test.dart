import 'package:clean_stream_laundry_app/features/email_verification/email_verification.dart';
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

  setUpAll(() {
    registerFallbackValue(FakeAuthService());
    registerFallbackValue('');
  });

  setUp(() {
    mockAuthService = MockAuthService();

    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
    when(() => mockAuthService.getCurrentUserEmail()).thenReturn(null);
  });

  tearDown(() {
    GetIt.instance.reset();
  });

  Widget createTestWidget({String? email}) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/email-verification',
        routes: [
          GoRoute(
            path: '/email-verification',
            builder: (context, state) => EmailVerificationPage(email: email),
          ),
          GoRoute(
            path: '/homePage',
            builder: (context, state) =>
                const Scaffold(body: Text('Home Page')),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) =>
                const Scaffold(body: Text('Login Page')),
          ),
        ],
      ),
    );
  }

  group('Static UI', () {
    testWidgets('displays all required UI elements', (tester) async {
      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(
        find.text(
          'Enter the 6-digit verification code we sent to your email address.',
        ),
        findsOneWidget,
      );
      expect(find.text('Verify Email'), findsNWidgets(2));
      expect(find.text('Resend code'), findsOneWidget);
      expect(find.text('Back to Login'), findsOneWidget);
    });

    testWidgets('email icon has correct sizing', (tester) async {
      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.mark_email_read_outlined),
      );
      expect(icon.size, equals(40));
    });

    testWidgets('shows route email when provided', (tester) async {
      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      expect(find.text('route@example.com'), findsOneWidget);
    });

    testWidgets('shows current user email when route email is missing', (
      tester,
    ) async {
      when(
        () => mockAuthService.getCurrentUserEmail(),
      ).thenReturn('session@example.com');

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('session@example.com'), findsOneWidget);
    });

    testWidgets('shows fallback email placeholder when none available', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('your email'), findsOneWidget);
    });
  });

  group('Actions', () {
    testWidgets(
      'shows missing email message when verify is pressed without email',
      (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Verify Email'));
        await tester.pumpAndSettle();

        expect(
          find.text('Missing account email. Please log in and try again.'),
          findsOneWidget,
        );
        verifyNever(
          () => mockAuthService.verifyEmailCode(
            email: any(named: 'email'),
            code: any(named: 'code'),
          ),
        );
      },
    );

    testWidgets('navigates to home after successful code verification', (
      tester,
    ) async {
      when(
        () => mockAuthService.verifyEmailCode(
          email: 'route@example.com',
          code: '123456',
        ),
      ).thenAnswer((_) async => AuthenticationResponses.success);

      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify Email'));
      await tester.pumpAndSettle();

      expect(find.text('Home Page'), findsOneWidget);
    });

    testWidgets('shows invalid code error when verification fails', (
      tester,
    ) async {
      when(
        () => mockAuthService.verifyEmailCode(
          email: 'route@example.com',
          code: '123456',
        ),
      ).thenAnswer((_) async => AuthenticationResponses.failure);

      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify Email'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid or expired code'), findsWidgets);
    });

    testWidgets('resends code and shows success snackbar', (tester) async {
      when(
        () => mockAuthService.resendVerification(email: 'route@example.com'),
      ).thenAnswer((_) async => AuthenticationResponses.success);

      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();

      verify(
        () => mockAuthService.resendVerification(email: 'route@example.com'),
      ).called(1);
      expect(
        find.text('Verification code sent! Check your email.'),
        findsOneWidget,
      );
    });

    testWidgets('shows resend failure message', (tester) async {
      when(
        () => mockAuthService.resendVerification(email: 'route@example.com'),
      ).thenAnswer((_) async => AuthenticationResponses.failure);

      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to send verification code.'), findsOneWidget);
    });

    testWidgets('navigates to login when back to login is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Back to Login'),
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.tap(find.text('Back to Login'));
      await tester.pumpAndSettle();

      expect(find.text('Login Page'), findsOneWidget);
    });
  });

  group('Layout', () {
    testWidgets('uses theme surface color as scaffold background', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, isNotNull);
    });

    testWidgets('title text is centered', (tester) async {
      await tester.pumpWidget(createTestWidget(email: 'route@example.com'));
      await tester.pumpAndSettle();

      final titleText = tester.widget<Text>(find.text('Verify your email'));
      expect(titleText.textAlign, TextAlign.center);
    });
  });
}
