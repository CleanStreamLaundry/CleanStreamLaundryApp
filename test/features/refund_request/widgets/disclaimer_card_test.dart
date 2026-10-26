import 'package:clean_stream_laundry_app/features/refund_request/widgets/disclaimer_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget() {
    return const MaterialApp(home: Scaffold(body: DisclaimerCard()));
  }

  group('RefundDisclaimerCard', () {
    testWidgets('displays info icon', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    });

    testWidgets('displays same-day on-site reporting requirement', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(
        find.textContaining(
          'Report a machine failure while you are at the location and on the same local calendar day.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('explains replacement machine or wallet remedy', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(
        find.textContaining(
          'an available replacement machine for the same amount, or credit your wallet if you already completed a replacement load.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('preserves payment errors and mandatory rights', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(
        find.textContaining(
          'Payment errors and rights required by law are reviewed separately.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('has a restrained theme accent rule without a nested card', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget());

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.info_outline_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNull);
      expect(decoration.borderRadius, isNull);
      expect(
        (decoration.border! as Border).left.color,
        Theme.of(
          tester.element(find.byType(DisclaimerCard)),
        ).colorScheme.secondary,
      );
      expect((decoration.border! as Border).left.width, 3);
    });
  });
}
