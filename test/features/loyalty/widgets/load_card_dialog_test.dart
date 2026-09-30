import 'package:clean_stream_laundry_app/features/loyalty/widgets/load_card_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({Future<void> Function(double)? onPay}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => LoadCardDialog(onPay: onPay ?? (_) async {}),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    Future<void> Function(double)? onPay,
  }) async {
    await tester.pumpWidget(buildWidget(onPay: onPay));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('LoadCardDialog', () {
    group('Initial state', () {
      testWidgets('shows Load Loyalty Card title', (tester) async {
        await openDialog(tester);
        expect(find.text('Load Loyalty Card'), findsOneWidget);
      });

      testWidgets('initialises amount at \$1.00', (tester) async {
        await openDialog(tester);
        expect(find.text('\$1.00'), findsOneWidget);
      });

      testWidgets('shows loyalty terms guidance', (tester) async {
        await openDialog(tester);
        expect(
          find.textContaining('Loyalty Card loads are final sale'),
          findsOneWidget,
        );
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.text('View terms'), findsOneWidget);
        expect(find.text('I agree to the Loyalty Card Terms.'), findsNothing);
      });

      testWidgets('shows Cancel and Pay buttons', (tester) async {
        await openDialog(tester);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Pay'), findsOneWidget);
      });

      testWidgets('shows preset chip amounts', (tester) async {
        await openDialog(tester);
        expect(find.text('\$10'), findsOneWidget);
        expect(find.text('\$15'), findsOneWidget);
        expect(find.text('\$25'), findsOneWidget);
      });

      testWidgets('shows slider at initial value', (tester) async {
        await openDialog(tester);
        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.value, 1.0);
      });

      testWidgets('decrement button is disabled at minimum', (tester) async {
        await openDialog(tester);
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '-25¢'),
        );
        expect(button.onPressed, isNull);
      });
    });

    group('Amount controls', () {
      testWidgets('increments by 25¢ when +25¢ tapped', (tester) async {
        await openDialog(tester);
        await tester.tap(find.text('+25¢'));
        await tester.pumpAndSettle();
        expect(find.text('\$1.25'), findsOneWidget);
      });

      testWidgets('decrements by 25¢ when -25¢ tapped after increment', (
        tester,
      ) async {
        await openDialog(tester);
        await tester.tap(find.text('+25¢'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('-25¢'));
        await tester.pumpAndSettle();
        expect(find.text('\$1.00'), findsOneWidget);
      });

      testWidgets('selects \$10 chip', (tester) async {
        await openDialog(tester);
        await tester.tap(find.text('\$10'));
        await tester.pumpAndSettle();
        expect(find.text('\$10.00'), findsOneWidget);
      });

      testWidgets('selects \$15 chip', (tester) async {
        await openDialog(tester);
        await tester.tap(find.text('\$15'));
        await tester.pumpAndSettle();
        expect(find.text('\$15.00'), findsOneWidget);
      });

      testWidgets('selects \$25 chip', (tester) async {
        await openDialog(tester);
        await tester.tap(find.text('\$25'));
        await tester.pumpAndSettle();
        expect(find.text('\$25.00'), findsOneWidget);
      });

      testWidgets('does not go below \$1.00', (tester) async {
        await openDialog(tester);
        final decrementButton = find.widgetWithText(OutlinedButton, '-25¢');
        await tester.tap(decrementButton);
        await tester.pumpAndSettle();
        expect(find.text('\$1.00'), findsOneWidget);
      });

      testWidgets('caps at \$500.00 and disables increment', (tester) async {
        await openDialog(tester);

        final incrementButton = find.text('+25¢');
        for (int i = 0; i < 2000; i++) {
          await tester.tap(incrementButton);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.text('\$500.00'), findsOneWidget);
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '+25¢'),
        );
        expect(button.onPressed, isNull);
      });
    });

    group('Dialog actions', () {
      testWidgets('closes when Cancel tapped', (tester) async {
        await openDialog(tester);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Load Loyalty Card'), findsNothing);
      });

      testWidgets('calls onPay with correct amount', (tester) async {
        double? capturedAmount;
        await openDialog(
          tester,
          onPay: (amount) async => capturedAmount = amount,
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Pay'));
        await tester.pumpAndSettle();

        expect(capturedAmount, 1.0);
      });

      testWidgets('calls onPay with chip-selected amount', (tester) async {
        double? capturedAmount;
        await openDialog(
          tester,
          onPay: (amount) async => capturedAmount = amount,
        );

        await tester.tap(find.text('\$25'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Pay'));
        await tester.pumpAndSettle();

        expect(capturedAmount, 25.0);
      });

      testWidgets('closes dialog before calling onPay', (tester) async {
        await openDialog(tester, onPay: (_) async {});

        await tester.tap(find.widgetWithText(ElevatedButton, 'Pay'));
        await tester.pumpAndSettle();

        expect(find.text('Load Loyalty Card'), findsNothing);
      });
    });
  });
}
