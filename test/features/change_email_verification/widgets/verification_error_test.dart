import 'package:clean_stream_laundry_app/features/change_email_verification/widgets/verification_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget() {
    return const MaterialApp(home: Scaffold(body: VerificationError()));
  }

  group('VerificationError', () {
    testWidgets('displays error message text', (tester) async {
      await tester.pumpWidget(buildWidget());

      expect(
        find.text('Please resend verification again at another time.'),
        findsOneWidget,
      );
    });

    testWidgets('error message uses center alignment', (tester) async {
      await tester.pumpWidget(buildWidget());

      final text = tester.widget<Text>(
        find.text('Please resend verification again at another time.'),
      );
      expect(text.textAlign, equals(TextAlign.center));
    });

    testWidgets('shows close icon', (tester) async {
      await tester.pumpWidget(buildWidget());

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('close icon has correct styling', (tester) async {
      await tester.pumpWidget(buildWidget());

      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(icon.size, equals(28));
      expect(icon.color, equals(Colors.white));
    });

    testWidgets('container has red circular decoration', (tester) async {
      await tester.pumpWidget(buildWidget());

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

    testWidgets('container has correct dimensions', (tester) async {
      await tester.pumpWidget(buildWidget());

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.close),
              matching: find.byType(Container),
            )
            .first,
      );

      expect(container.constraints?.maxWidth, equals(48));
      expect(container.constraints?.maxHeight, equals(48));
    });
  });
}
