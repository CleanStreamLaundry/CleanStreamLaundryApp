import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/features/change_email_verification/controller.dart';
import 'package:clean_stream_laundry_app/features/change_email_verification/widgets/resend_verification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import '../mocks.dart';

void main() {
  late MockAuthService mockAuthService;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    mockAuthService = MockAuthService();
    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
  });

  tearDown(() {
    GetIt.instance.reset();
  });

  /// builds minimal widgets tree
  Widget buildWidget({
    required ChangeEmailVerificationController controller,
    VoidCallback? onStateChange,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            return ResendVerificationWidget(
              controller: controller,
              onStateChange: onStateChange ?? () => setState(() {}),
            );
          },
        ),
      ),
    );
  }

  group('Initial state', () {
    testWidgets('shows Resend Verification link text', (tester) async {
      final controller = ChangeEmailVerificationController();
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('Resend Verification'), findsOneWidget);
    });

    testWidgets('link text has correct styling', (tester) async {
      final controller = ChangeEmailVerificationController();
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('Resend Verification'));
      expect(
        textWidget.style?.color,
        Theme.of(
          tester.element(find.text('Resend Verification')),
        ).colorScheme.primary,
      );
      expect(textWidget.style?.decoration, equals(TextDecoration.underline));
    });

    testWidgets('link is wrapped in an InkWell', (tester) async {
      final controller = ChangeEmailVerificationController();
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      final inkWell = find.ancestor(
        of: find.text('Resend Verification'),
        matching: find.byType(InkWell),
      );
      expect(inkWell, findsOneWidget);
    });
  });

  group('Success state', () {
    testWidgets('shows check_circle icon after successful resend', (
      tester,
    ) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.success);

      final controller = ChangeEmailVerificationController();
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resend Verification'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Resend Verification'), findsNothing);
    });

    testWidgets('check_circle icon has correct styling', (tester) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.success);

      final controller = ChangeEmailVerificationController();
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resend Verification'));
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(icon.size, equals(40));
      expect(icon.color, equals(Colors.green));
    });

    testWidgets('tapping check_circle does not trigger another resend', (
      tester,
    ) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.success);

      final controller = ChangeEmailVerificationController();
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resend Verification'));
      await tester.pumpAndSettle();

      verify(() => mockAuthService.resendVerification()).called(1);

      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pumpAndSettle();

      verifyNever(() => mockAuthService.resendVerification());
    });
  });

  group('Failure state', () {
    testWidgets('shows VerificationError widgets on failure', (tester) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.failure);

      final controller = ChangeEmailVerificationController();
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resend Verification'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(
        find.text('Please resend verification again at another time.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping error icon does not trigger another resend', (
      tester,
    ) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.failure);

      final controller = ChangeEmailVerificationController();
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resend Verification'));
      await tester.pumpAndSettle();

      verify(() => mockAuthService.resendVerification()).called(1);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      verify(() => mockAuthService.resendVerification()).called(1);
    });
  });

  group('InkWell interaction', () {
    testWidgets('tapping InkWell calls resendVerification', (tester) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.success);

      final controller = ChangeEmailVerificationController();
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      final inkWell = find.ancestor(
        of: find.text('Resend Verification'),
        matching: find.byType(InkWell),
      );

      await tester.tap(inkWell);
      await tester.pumpAndSettle();

      verify(() => mockAuthService.resendVerification()).called(1);
    });
  });
}
