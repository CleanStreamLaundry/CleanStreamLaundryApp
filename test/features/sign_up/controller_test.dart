import 'dart:async';
import 'package:clean_stream_laundry_app/features/sign_up/controller.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
  });

  SignUpController buildController() =>
      SignUpController(authService: mockAuthService);

  group('Visibility toggles', () {
    test('togglePasswordVisibility flips obscurePassword', () {
      final c = buildController();
      expect(c.obscurePassword, isTrue);
      c.togglePasswordVisibility();
      expect(c.obscurePassword, isFalse);
      c.togglePasswordVisibility();
      expect(c.obscurePassword, isTrue);
    });

    test('toggleConfirmVisibility flips obscureConfirmPassword', () {
      final c = buildController();
      expect(c.obscureConfirmPassword, isTrue);
      c.toggleConfirmVisibility();
      expect(c.obscureConfirmPassword, isFalse);
    });

    test('togglePasswordVisibility notifies listeners', () {
      final c = buildController();
      var notified = false;
      c.addListener(() => notified = true);
      c.togglePasswordVisibility();
      expect(notified, isTrue);
    });
  });

  group('Color state', () {
    test('changeColorsToRed sets labels and colors', () {
      final c = buildController();
      c.changeColorsToRed('Some error');
      expect(c.passwordLabel, 'Some error');
      expect(c.confirmPasswordLabel, 'Some error');
      expect(c.iconColor, Colors.red);
      expect(c.labelColor, Colors.red);
    });

    test('changeColorsToDefault restores labels and colors', () {
      final c = buildController();
      c.changeColorsToRed('error');
      c.changeColorsToDefault();
      expect(c.passwordLabel, 'Password');
      expect(c.confirmPasswordLabel, 'Confirm Password');
      expect(c.iconColor, Colors.blue);
      expect(c.labelColor, Colors.blue);
    });

    test('changeColorsToRed notifies listeners', () {
      final c = buildController();
      var notified = false;
      c.addListener(() => notified = true);
      c.changeColorsToRed('error');
      expect(notified, isTrue);
    });
  });

  group('onPasswordChanged', () {
    test('resets colors when iconColor is red', () {
      final c = buildController();
      c.changeColorsToRed('error');
      c.onPasswordChanged();
      expect(c.iconColor, Colors.blue);
    });

    test('does nothing when iconColor is not red', () {
      final c = buildController();
      c.onPasswordChanged();
      expect(c.passwordLabel, 'Password');
    });
  });

  group('onConfirmChanged', () {
    test('sets red colors when passwords do not match', () {
      final c = buildController();
      c.passwordController.text = 'Password1!';
      c.confirmController.text = 'Different1!';
      c.onConfirmChanged();
      expect(c.iconColor, Colors.red);
    });

    test('resets colors when passwords match', () {
      final c = buildController();
      c.passwordController.text = 'Password1!';
      c.confirmController.text = 'Password1!';
      c.changeColorsToRed('mismatch');
      c.onConfirmChanged();
      expect(c.iconColor, Colors.blue);
    });

    test('does not call changeColorsToRed again if already red', () {
      final c = buildController();
      c.passwordController.text = 'Password1!';
      c.confirmController.text = 'Other1!';
      c.changeColorsToRed('mismatch');
      var notifyCount = 0;
      c.addListener(() => notifyCount++);
      c.onConfirmChanged();
      expect(notifyCount, 0);
    });
  });

  group('handleSignUp — validation', () {
    test('returns snackbar error when name is empty', () async {
      final c = buildController();
      c.emailController.text = 'a@b.com';
      c.passwordController.text = 'Password1!';
      c.confirmController.text = 'Password1!';

      final result = await c.handleSignUp();
      expect(result.success, isFalse);
      expect(result.message, 'Please fill in all fields.');
      verifyNever(() => mockAuthService.signUp(any(), any(), any()));
    });

    test('returns snackbar error when all fields are empty', () async {
      final c = buildController();
      final result = await c.handleSignUp();
      expect(result.message, 'Please fill in all fields.');
    });

    test('returns snackbar error when passwords do not match', () async {
      final c = buildController();
      c.nameController.text = 'Name';
      c.emailController.text = 'a@b.com';
      c.passwordController.text = 'Password1!';
      c.confirmController.text = 'Different1!';

      final result = await c.handleSignUp();
      expect(result.message, 'Passwords do not match.');
      verifyNever(() => mockAuthService.signUp(any(), any(), any()));
    });
  });

  group('handleSignUp — auth responses', () {
    void fillValidForm(SignUpController c) {
      c.nameController.text = 'Test User';
      c.emailController.text = 'test@example.com';
      c.passwordController.text = 'Password1!';
      c.confirmController.text = 'Password1!';
    }

    for (final entry in {
      AuthenticationResponses.compromisedPassword:
          'This password was found in a data breach. Choose a different password.',
      AuthenticationResponses.weakPassword:
          'This password does not meet security requirements. Choose a stronger password.',
    }.entries) {
      test('returns controlled message for ${entry.key}', () async {
        when(() => mockAuthService.signUp(any(), any(), any()))
            .thenAnswer((_) async => entry.key);
        final c = buildController();
        addTearDown(() { c.disposeControllers(); c.dispose(); });
        fillValidForm(c);
        final result = await c.handleSignUp();
        expect(result.success, isFalse);
        expect(result.message, entry.value);
        expect(c.isLoading, isFalse);
        verify(() => mockAuthService.signUp(
          'test@example.com', 'Password1!', 'Test User',
        )).called(1);
      });
    }

    test('returns success on AuthenticationResponses.success', () async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.success);

      final c = buildController();
      fillValidForm(c);

      final result = await c.handleSignUp();
      expect(result.success, isTrue);
      expect(result.message, isNull);
    });

    test('calls signUp with trimmed email and name', () async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.success);

      final c = buildController();
      c.nameController.text = '  Test User  ';
      c.emailController.text = '  test@example.com  ';
      c.passwordController.text = 'Password1!';
      c.confirmController.text = 'Password1!';

      await c.handleSignUp();

      verify(() => mockAuthService.signUp(
        'test@example.com',
        'Password1!',
        'Test User',
      )).called(1);
    });

    test('returns colorOnly and sets red on noDigit', () async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.noDigit);

      final c = buildController();
      fillValidForm(c);
      final result = await c.handleSignUp();

      expect(result.success, isFalse);
      expect(result.message, isNull);
      expect(c.iconColor, Colors.red);
      expect(c.passwordLabel, 'Please include a digit');
    });

    test('returns colorOnly and sets red on lessThanMinLength', () async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer(
              (_) async => AuthenticationResponses.lessThanMinLength);

      final c = buildController();
      fillValidForm(c);
      final result = await c.handleSignUp();

      expect(result.message, isNull);
      expect(c.passwordLabel, 'Password length is too short');
    });

    test('returns colorOnly and sets red on noSpecialCharacter', () async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer(
              (_) async => AuthenticationResponses.noSpecialCharacter);

      final c = buildController();
      fillValidForm(c);
      final result = await c.handleSignUp();

      expect(c.passwordLabel, 'Please include a special character');
      expect(result.message, isNull);
    });

    test('returns colorOnly and sets red on noUppercase', () async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.noUppercase);

      final c = buildController();
      fillValidForm(c);
      final result = await c.handleSignUp();

      expect(c.passwordLabel, 'Please include an uppercase letter');
      expect(result.message, isNull);
    });

    test('returns colorOnly and sets red on invalidSpecialCharacter',
            () async {
          when(() => mockAuthService.signUp(any(), any(), any()))
              .thenAnswer(
                  (_) async => AuthenticationResponses.invalidSpecialCharacter);

          final c = buildController();
          fillValidForm(c);
          final result = await c.handleSignUp();

          expect(c.passwordLabel, 'Please use a different special character');
          expect(result.message, isNull);
        });

    test('returns snackbar error on generic failure', () async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.failure);

      final c = buildController();
      fillValidForm(c);
      final result = await c.handleSignUp();

      expect(result.message, 'Sign-up failed. Try again.');
    });

    test('sets and clears isLoading around signUp call', () async {
      final completer = Completer<AuthenticationResponses>();
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) => completer.future);

      final c = buildController();
      fillValidForm(c);

      final future = c.handleSignUp();
      expect(c.isLoading, isTrue);

      completer.complete(AuthenticationResponses.success);
      await future;
      expect(c.isLoading, isFalse);
    });

    test('contains service errors and clears isLoading without raw details', () async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenThrow(Exception('network'));

      final c = buildController();
      fillValidForm(c);

      final result = await c.handleSignUp();
      expect(result.success, isFalse);
      expect(result.message, 'Sign-up failed. Try again.');
      expect(c.isLoading, isFalse);
    });

    test('notifies twice for isLoading transitions', () async {
      when(() => mockAuthService.signUp(any(), any(), any()))
          .thenAnswer((_) async => AuthenticationResponses.success);

      final c = buildController();
      fillValidForm(c);

      var notifyCount = 0;
      c.addListener(() => notifyCount++);

      await c.handleSignUp();

      expect(notifyCount, greaterThanOrEqualTo(2));
    });
  });
}
