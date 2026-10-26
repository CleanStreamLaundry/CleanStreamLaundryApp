import 'package:clean_stream_laundry_app/features/sign_up/widgets/info_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget() =>
      const MaterialApp(home: Scaffold(body: SignUpInfoBanner()));

  group('SignUpInfoBanner', () {
    testWidgets('displays instruction text', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(
        find.textContaining('Enter your info to create your account'),
        findsOneWidget,
      );
    });

    testWidgets('displays confirmation email text', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.textContaining('confirmation email'), findsOneWidget);
    });

    testWidgets('text is centered', (tester) async {
      await tester.pumpWidget(buildWidget());
      final text = tester.widget<Text>(find.textContaining('Enter your info'));
      expect(text.textAlign, TextAlign.center);
    });

    testWidgets('has restrained theme accent rule', (tester) async {
      await tester.pumpWidget(buildWidget());
      final container = tester.widget<Container>(
        find.ancestor(
          of: find.textContaining('Enter your info'),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border?;
      expect(
        border?.bottom.color,
        Theme.of(
          tester.element(find.byType(SignUpInfoBanner)),
        ).colorScheme.secondary,
      );
      expect(border?.bottom.width, 3);
      expect(border?.top.style, BorderStyle.none);
    });
  });
}
