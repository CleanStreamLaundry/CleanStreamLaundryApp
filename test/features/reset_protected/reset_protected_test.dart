import 'dart:async';

import 'package:clean_stream_laundry_app/features/reset_protected/reset_protected.dart';
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
        initialLocation: '/reset-protected',
        routes: [
          GoRoute(
            path: '/reset-protected',
            builder: (_, __) => const ResetProtectedPage(),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) =>
            const Scaffold(body: Text('Login Page')),
          ),
        ],
      ),
    );
  }

  Future<void> enterPassword(WidgetTester tester, String text) async {
    final field = find.widgetWithText(TextField, 'New Password');
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pump();
  }

  Future<void> enterConfirm(WidgetTester tester, String text) async {
    final field = find.byType(TextField).at(1);
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    final button = find.widgetWithText(ElevatedButton, 'Reset Password');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  group('Static UI', () {
    testWidgets('displays logo', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app_logo')), findsOneWidget);
    });

    testWidgets('displays Reset Password title', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.text('Reset Password'), findsWidgets);
    });

    testWidgets('displays subtitle text', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.text('Enter your new password below'), findsOneWidget);
    });

    testWidgets('displays both password fields', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'New Password'), findsOneWidget);
      expect(
          find.widgetWithText(TextField, 'Confirm Password'), findsOneWidget);
    });

    testWidgets('displays two lock icons', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock), findsNWidgets(2));
    });

    testWidgets('both fields obscured by default', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      for (final f in fields) {
        expect(f.obscureText, isTrue);
      }
    });

    testWidgets('displays two visibility_off icons initially', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_off), findsNWidgets(2));
    });
  });

  group('Password requirements hint', () {
    testWidgets('hint appears when password does not meet requirements',
            (tester) async {
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await enterPassword(tester, 'weak');

          expect(find.byType(Container), findsWidgets);
        });

    testWidgets('hint disappears when password meets requirements',
            (tester) async {
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await enterPassword(tester, 'StrongPass1!');

          expect(find.textContaining('Password must'), findsNothing);
        });
  });

  group('Validation', () {
    testWidgets('shows snackbar when fields are empty', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tapSubmit(tester);
      await tester.pump();

      expect(find.text('Please fill in all fields'), findsOneWidget);
    });

    testWidgets('shows red labels when passwords do not match', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterPassword(tester, 'StrongPass1!');
      await enterConfirm(tester, 'DifferentPass1!');

      await tapSubmit(tester);
      await tester.pump();

      expect(find.text("Passwords don't match"), findsWidgets);
    });

    testWidgets('colors reset when user starts typing after mismatch',
            (tester) async {
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await enterPassword(tester, 'StrongPass1!');
          await enterConfirm(tester, 'DifferentPass1!');

          await tapSubmit(tester);
          await tester.pump();

          expect(find.text("Passwords don't match"), findsWidgets);

          await enterConfirm(tester, 'StrongPass1!');

          expect(find.descendant(
            of: find.byType(TextField),
            matching: find.text("Passwords don't match"),
          ), findsNothing);
          expect(find.descendant(
            of: find.byType(SnackBar),
            matching: find.text("Passwords don't match"),
          ), findsOneWidget);
        });

    testWidgets('does not call service when validation fails', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tapSubmit(tester);
      await tester.pump();

      verifyNever(() => mockAuthService.updatePassword(any()));
    });
  });

  group('Submit', () {
    const validPassword = 'StrongPass1!';

    for (final entry in {
      AuthenticationResponses.compromisedPassword:
          'This password was found in a data breach. Choose a different password.',
      AuthenticationResponses.weakPassword:
          'This password does not meet security requirements. Choose a stronger password.',
    }.entries) {
      testWidgets('shows controlled password rejection for ${entry.key}', (tester) async {
        when(() => mockAuthService.updatePassword(any()))
            .thenAnswer((_) async => entry.key);
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();
        await enterPassword(tester, validPassword);
        await enterConfirm(tester, validPassword);
        await tapSubmit(tester);
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
        expect(find.text('Password reset successful'), findsNothing);
        expect(find.text('Login Page'), findsNothing);
        expect(tester.takeException(), isNull);
        verify(() => mockAuthService.updatePassword(validPassword)).called(1);
      });
    }

    testWidgets('calls updatePassword with correct value', (tester) async {
      when(() => mockAuthService.updatePassword(any()))
          .thenAnswer((_) async => AuthenticationResponses.success);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterPassword(tester, validPassword);
      await enterConfirm(tester, validPassword);

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      verify(() => mockAuthService.updatePassword(validPassword)).called(1);
    });

    testWidgets('shows success snackbar on success', (tester) async {
      when(() => mockAuthService.updatePassword(any()))
          .thenAnswer((_) async => AuthenticationResponses.success);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterPassword(tester, validPassword);
      await enterConfirm(tester, validPassword);

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Password reset successful'), findsOneWidget);
    });

    testWidgets('navigates to /login on success', (tester) async {
      when(() => mockAuthService.updatePassword(any()))
          .thenAnswer((_) async => AuthenticationResponses.success);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterPassword(tester, validPassword);
      await enterConfirm(tester, validPassword);

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Login Page'), findsOneWidget);
    });

    testWidgets('shows failure snackbar when service throws', (tester) async {
      when(() => mockAuthService.updatePassword(any()))
          .thenThrow(Exception('network'));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterPassword(tester, validPassword);
      await enterConfirm(tester, validPassword);

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Failed to reset password'), findsOneWidget);
      expect(find.text('network'), findsNothing);
    });

    testWidgets('shows loading indicator while submitting', (tester) async {
      final completer = Completer<AuthenticationResponses>();
      when(() => mockAuthService.updatePassword(any()))
          .thenAnswer((_) async => completer.future);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterPassword(tester, validPassword);
      await enterConfirm(tester, validPassword);

      await tapSubmit(tester);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Reset Password'), findsOneWidget);

      completer.complete(AuthenticationResponses.success);
      await tester.pumpAndSettle();
    });

    testWidgets('disables button while loading', (tester) async {
      final completer = Completer<AuthenticationResponses>();
      when(() => mockAuthService.updatePassword(any()))
          .thenAnswer((_) async => completer.future);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await enterPassword(tester, validPassword);
      await enterConfirm(tester, validPassword);

      await tapSubmit(tester);
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNull);

      completer.complete(AuthenticationResponses.success);
      await tester.pumpAndSettle();
    });
  });
}
