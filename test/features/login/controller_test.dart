import 'package:clean_stream_laundry_app/features/login/controller.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
  });

  LoginController buildController() => LoginController(
    authService: mockAuthService,
  );

  Widget buildWithRouter({
    required void Function(LoginController) onControllerReady,
  }) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) {
              final controller = LoginController(
                authService: mockAuthService,
              );
              onControllerReady(controller);
              return const SizedBox();
            },
          ),
          GoRoute(
            path: '/homePage',
            builder: (_, __) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('Login')),
          ),
          GoRoute(
            path: '/email-Verification',
            builder: (_, __) =>
            const Scaffold(body: Text('Email Verification')),
          ),
        ],
      ),
    );
  }

  test('constructs with AuthService alone without consuming callbacks', () {
    final controller = LoginController(authService: mockAuthService);
    addTearDown(() {
      controller.disposeController();
      controller.dispose();
    });

    expect(controller.authService, same(mockAuthService));
    verifyZeroInteractions(mockAuthService);
  });

  group('handleLogin', () {
    testWidgets('calls auth service with trimmed email and password',
            (tester) async {
          when(() => mockAuthService.login(any(), any()))
              .thenAnswer((_) async => AuthenticationResponses.success);

          late LoginController controller;
          await tester.pumpWidget(
              buildWithRouter(onControllerReady: (c) => controller = c));

          controller.emailController.text = '  test@example.com  ';
          controller.passwordController.text = 'password123';

          await controller.handleLogin(
              tester.element(find.byType(SizedBox)), (_) {});

          verify(() => mockAuthService.login('test@example.com', 'password123'))
              .called(1);
        });

    testWidgets('does not call login when email is empty', (tester) async {
      late LoginController controller;
      await tester.pumpWidget(
          buildWithRouter(onControllerReady: (c) => controller = c));

      controller.emailController.text = '';
      controller.passwordController.text = 'password123';

      final messages = <String>[];
      await controller.handleLogin(
          tester.element(find.byType(SizedBox)), messages.add);

      expect(messages, contains('Please fill in both fields.'));
      verifyNever(() => mockAuthService.login(any(), any()));
    });

    testWidgets('does not call login when password is empty', (tester) async {
      late LoginController controller;
      await tester.pumpWidget(
          buildWithRouter(onControllerReady: (c) => controller = c));

      controller.emailController.text = 'test@example.com';
      controller.passwordController.text = '';

      final messages = <String>[];
      await controller.handleLogin(
          tester.element(find.byType(SizedBox)), messages.add);

      expect(messages, contains('Please fill in both fields.'));
      verifyNever(() => mockAuthService.login(any(), any()));
    });

    testWidgets('calls setErrorColors on failure response', (tester) async {
      when(() => mockAuthService.login(any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.failure);

      late LoginController controller;
      await tester.pumpWidget(
          buildWithRouter(onControllerReady: (c) => controller = c));

      controller.emailController.text = 'test@example.com';
      controller.passwordController.text = 'wrongpass';

      await controller.handleLogin(
          tester.element(find.byType(SizedBox)), (_) {});

      expect(controller.iconColor, Colors.red);
      expect(controller.labelColor, Colors.red);
      expect(controller.emailLabel, 'Invalid Password or Email');
      expect(controller.passwordLabel, 'Invalid Password or Email');
    });
  });

  group('setErrorColors', () {
    test('sets all color fields to red and updates labels', () {
      final controller = buildController();

      controller.setErrorColors();

      expect(controller.iconColor, Colors.red);
      expect(controller.enabledBorderColor, Colors.red);
      expect(controller.focusedBorderColor, Colors.red);
      expect(controller.labelColor, Colors.red);
      expect(controller.emailLabel, 'Invalid Password or Email');
      expect(controller.passwordLabel, 'Invalid Password or Email');
    });
  });

  group('togglePasswordVisibility', () {
    test('flips obscurePassword from true to false', () {
      final controller = buildController();

      expect(controller.obscurePassword, isTrue);
      controller.togglePasswordVisibility();
      expect(controller.obscurePassword, isFalse);
    });

    test('flips obscurePassword from false to true', () {
      final controller = buildController();

      controller.togglePasswordVisibility();
      controller.togglePasswordVisibility();

      expect(controller.obscurePassword, isTrue);
    });
  });

  group('Lifecycle', () {
    testWidgets('disposeController releases local controls without error',
            (tester) async {
          late LoginController controller;
          await tester.pumpWidget(
              buildWithRouter(onControllerReady: (c) => controller = c));

          expect(() => controller.disposeController(), returnsNormally);
        });
  });
}
