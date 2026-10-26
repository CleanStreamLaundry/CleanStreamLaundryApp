import 'package:clean_stream_laundry_app/features/email_verification/controller.dart';
import 'package:clean_stream_laundry_app/features/email_verification/widgets/resend_verification.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
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

  Future<EmailVerificationController> buildController(
    WidgetTester tester,
  ) async {
    late EmailVerificationController controller;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            controller = EmailVerificationController();
            return const SizedBox();
          },
        ),
      ),
    );

    return controller;
  }

  Widget buildWidget({
    required EmailVerificationController controller,
    VoidCallback? onStateChange,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ResendVerificationWidget(
            controller: controller,
            onStateChange: onStateChange ?? () => setState(() {}),
          ),
        ),
      ),
    );
  }

  group('Initial state', () {
    testWidgets('shows Resend Verification link text', (tester) async {
      final controller = await buildController(tester);
      await tester.pumpWidget(buildWidget(controller: controller));

      expect(find.text('Resend Verification'), findsOneWidget);
    });

    testWidgets('link text has correct styling', (tester) async {
      final controller = await buildController(tester);
      await tester.pumpWidget(buildWidget(controller: controller));

      final text = tester.widget<Text>(find.text('Resend Verification'));
      expect(
        text.style?.color,
        Theme.of(
          tester.element(find.text('Resend Verification')),
        ).colorScheme.primary,
      );
      expect(text.style?.decoration, equals(TextDecoration.underline));
    });

    testWidgets('link is wrapped in an InkWell', (tester) async {
      final controller = await buildController(tester);
      await tester.pumpWidget(buildWidget(controller: controller));

      expect(
        find.ancestor(
          of: find.text('Resend Verification'),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });
  });

  group('Success state', () {
    testWidgets('shows check_circle icon after successful resend', (
      tester,
    ) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.success);

      final controller = await buildController(tester);
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

      final controller = await buildController(tester);
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

      final controller = await buildController(tester);
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
    testWidgets('shows close icon and error text on failure', (tester) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.failure);

      final controller = await buildController(tester);
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

    testWidgets('error container has red circular decoration', (tester) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.failure);

      final controller = await buildController(tester);
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resend Verification'));
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.close),
              matching: find.byType(Container),
            )
            .first,
      );

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFB3261E));
      expect(decoration.shape, equals(BoxShape.circle));
    });

    testWidgets('does not trigger another resend after failure', (
      tester,
    ) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.failure);

      final controller = await buildController(tester);
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resend Verification'));
      await tester.pumpAndSettle();

      verify(() => mockAuthService.resendVerification()).called(1);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      verifyNever(() => mockAuthService.resendVerification());
    });
  });

  group('InkWell interaction', () {
    testWidgets('tapping InkWell calls resendVerification', (tester) async {
      when(
        () => mockAuthService.resendVerification(),
      ).thenAnswer((_) async => AuthenticationResponses.success);

      final controller = await buildController(tester);
      await tester.pumpWidget(buildWidget(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.ancestor(
          of: find.text('Resend Verification'),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => mockAuthService.resendVerification()).called(1);
    });
  });
}
