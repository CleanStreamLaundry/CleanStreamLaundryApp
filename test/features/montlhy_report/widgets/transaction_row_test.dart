import 'package:clean_stream_laundry_app/features/monthly_report/widgets/transaction_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({
    String label = 'Direct Washer Payments',
    double amount = 2.50,
    Color color = Colors.black,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TransactionRow(label: label, amount: amount, color: color),
      ),
    );
  }

  group('TransactionBreakdownRow', () {
    testWidgets('large text stacks full amount below label on compact phones', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                boldText: true,
              ),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: TransactionRow(
                  label: 'Direct Washer Payments',
                  amount: 1234.56,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text(r'$1234.56')).top,
        greaterThan(tester.getRect(find.text('Direct Washer Payments')).bottom),
      );
    });
    testWidgets('displays the label', (tester) async {
      await tester.pumpWidget(buildWidget(label: 'Direct Washer Payments'));
      expect(find.text('Direct Washer Payments'), findsOneWidget);
    });

    testWidgets('displays amount formatted to two decimal places', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget(amount: 2.5));
      expect(find.text('\$2.50'), findsOneWidget);
    });

    testWidgets('displays zero amount correctly', (tester) async {
      await tester.pumpWidget(buildWidget(amount: 0));
      expect(find.text('\$0.00'), findsOneWidget);
    });

    testWidgets('applies color to label text', (tester) async {
      await tester.pumpWidget(buildWidget(color: Colors.blue));

      final labelText = tester.widget<Text>(
        find.text('Direct Washer Payments'),
      );
      expect(labelText.style?.color, Colors.blue);
    });

    testWidgets('applies color to amount text', (tester) async {
      await tester.pumpWidget(buildWidget(amount: 1.50, color: Colors.blue));

      final amountText = tester.widget<Text>(find.text('\$1.50'));
      expect(amountText.style?.color, Colors.blue);
    });

    testWidgets('amount text has bold weight', (tester) async {
      await tester.pumpWidget(buildWidget(amount: 5.00));

      final amountText = tester.widget<Text>(find.text('\$5.00'));
      expect(amountText.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('renders inside a Row', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.byType(Row), findsOneWidget);
    });
  });
}
