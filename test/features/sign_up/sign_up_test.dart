import 'package:clean_stream_laundry_app/features/sign_up/sign_up.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;
  late MockProfileService mockProfileService;
  late GoRouter router;

  setUp(() async {
    mockAuthService = MockAuthService();
    mockProfileService = MockProfileService();

    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
    GetIt.instance.registerSingleton<ProfileService>(mockProfileService);

    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const SignUpPage(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) =>
          const Scaffold(body: Text('Login Page')),
        ),
        GoRoute(
          path: '/email-verification',
          builder: (_, __) =>
          const Scaffold(body: Text('Email Verification Page')),
        ),
      ],
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  void setupViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());
  }

  Widget createWidget() {
    return MaterialApp.router(routerConfig: router);
  }

  group('Static UI', () {
    testWidgets('displays logo', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('displays all four input fields', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      expect(find.byType(TextField), findsNWidgets(4));
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
    });

    testWidgets('displays Create Account button', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      expect(
        find.widgetWithText(ElevatedButton, 'Create Account'),
        findsOneWidget,
      );
    });

    testWidgets('displays login link', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      expect(
        find.text('Already have an account? Login'),
        findsOneWidget,
      );
    });

    testWidgets('all text fields have prefix icons', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      for (int i = 0; i < 4; i++) {
        final field =
        tester.widget<TextField>(find.byType(TextField).at(i));
        expect(
          (field.decoration as InputDecoration).prefixIcon,
          isA<Icon>(),
        );
      }
    });

    testWidgets('password fields are obscured by default', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      final passwordField =
      tester.widget<TextField>(find.byType(TextField).at(2));
      final confirmField =
      tester.widget<TextField>(find.byType(TextField).at(3));

      expect(passwordField.obscureText, isTrue);
      expect(confirmField.obscureText, isTrue);
    });

    testWidgets('Create Account button has correct style', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      expect(button.style, isNotNull);
    });
  });

  group('Navigation', () {
    testWidgets('tapping login link navigates to /login', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      await tester.tap(find.text('Already have an account? Login'));
      await tester.pumpAndSettle();

      expect(find.text('Login Page'), findsOneWidget);
    });

    testWidgets('navigates to email-verification on success', (tester) async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.success);

      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      await tester.enterText(find.byType(TextField).at(0), 'Test User');
      await tester.enterText(
          find.byType(TextField).at(1), 'test@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'Password123!');
      await tester.enterText(find.byType(TextField).at(3), 'Password123!');

      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Email Verification Page'), findsOneWidget);
    });
  });

  group('Form validation', () {
    testWidgets('shows error when fields are empty', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Please fill in all fields.'), findsOneWidget);
    });

    testWidgets('shows error when passwords do not match', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      await tester.enterText(find.byType(TextField).at(0), 'Test User');
      await tester.enterText(
          find.byType(TextField).at(1), 'test@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'Password123!');
      await tester.enterText(find.byType(TextField).at(3), 'Password456!');

      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match.'), findsOneWidget);
    });
  });

  group('Auth response handling', () {
    Future<void> submitForm(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).at(0), 'Test User');
      await tester.enterText(
          find.byType(TextField).at(1), 'test@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'Password123!');
      await tester.enterText(find.byType(TextField).at(3), 'Password123!');
      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows error for noDigit response', (tester) async {
      setupViewport(tester);
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.noDigit);

      await tester.pumpWidget(createWidget());
      await submitForm(tester);

      expect(
        find.text('Please include a digit'),
        findsAtLeastNWidgets(1),
      );
    });

    for (final entry in {
      AuthenticationResponses.compromisedPassword:
          'This password was found in a data breach. Choose a different password.',
      AuthenticationResponses.weakPassword:
          'This password does not meet security requirements. Choose a stronger password.',
    }.entries) {
      testWidgets('shows controlled password rejection for ${entry.key}', (tester) async {
        setupViewport(tester);
        when(() => mockAuthService.signUp(any(), any(), any()))
            .thenAnswer((_) async => entry.key);
        await tester.pumpWidget(createWidget());
        await submitForm(tester);
        expect(find.text(entry.value), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Create Account'), findsOneWidget);
        expect(tester.takeException(), isNull);
        verify(() => mockAuthService.signUp(
          'test@example.com', 'Password123!', 'Test User',
        )).called(1);
      });
    }

    testWidgets('shows error for lessThanMinLength response', (tester) async {
      setupViewport(tester);
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer(
              (_) async => AuthenticationResponses.lessThanMinLength);

      await tester.pumpWidget(createWidget());
      await submitForm(tester);

      expect(
        find.text('Password length is too short'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('shows error for noSpecialCharacter response', (tester) async {
      setupViewport(tester);
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer(
              (_) async => AuthenticationResponses.noSpecialCharacter);

      await tester.pumpWidget(createWidget());
      await submitForm(tester);

      expect(
        find.text('Please include a special character'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('shows error for noUppercase response', (tester) async {
      setupViewport(tester);
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.noUppercase);

      await tester.pumpWidget(createWidget());
      await submitForm(tester);

      expect(
        find.text('Please include an uppercase letter'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('shows error for invalidSpecialCharacter response',
            (tester) async {
          setupViewport(tester);
          when(() => mockAuthService.signUp(any(), any(), any())).thenAnswer(
                  (_) async => AuthenticationResponses.invalidSpecialCharacter);

          await tester.pumpWidget(createWidget());
          await submitForm(tester);

          expect(
            find.text('Please use a different special character'),
            findsAtLeastNWidgets(1),
          );
        });
  });

  group('Password requirements hint', () {
    testWidgets('shows all requirements for completely weak password',
            (tester) async {
          setupViewport(tester);
          await tester.pumpWidget(createWidget());

          await tester.enterText(find.byType(TextField).at(2), 'abc');
          await tester.pump();

          expect(find.textContaining('Have 8 character length'), findsOneWidget);
          expect(find.textContaining('Include special character'), findsOneWidget);
          expect(find.textContaining('Include a digit'), findsOneWidget);
          expect(
            find.textContaining('Include an uppercase letter'),
            findsOneWidget,
          );
        });

    testWidgets('shows remaining requirements for partially valid password',
            (tester) async {
          setupViewport(tester);
          await tester.pumpWidget(createWidget());

          await tester.enterText(find.byType(TextField).at(2), 'Abcdefgh');
          await tester.pump();

          expect(find.textContaining('Have 8 character length'), findsNothing);
          expect(find.textContaining('Include special character'), findsOneWidget);
          expect(find.textContaining('Include a digit'), findsOneWidget);
          expect(
            find.textContaining('Include an uppercase letter'),
            findsNothing,
          );
        });

    testWidgets('shows no requirements for valid password', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      await tester.enterText(find.byType(TextField).at(2), 'Abc1234!');
      await tester.pump();

      expect(find.textContaining('Have 8 character length'), findsNothing);
      expect(find.textContaining('Include special character'), findsNothing);
      expect(find.textContaining('Include a digit'), findsNothing);
      expect(
        find.textContaining('Include an uppercase letter'),
        findsNothing,
      );
    });
  });

  group('Keyboard enter', () {
    testWidgets('pressing Enter triggers submission', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(createWidget());

      final keyboardListener =
      tester.widget<KeyboardListener>(find.byType(KeyboardListener));
      keyboardListener.focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Please fill in all fields.'), findsOneWidget);
    });
  });
}
