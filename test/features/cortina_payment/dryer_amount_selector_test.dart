import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/widgets/dryer_amount_selector.dart';
import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = [
  CortinaDryerOption(minutes: 10, amountCents: 50),
  CortinaDryerOption(minutes: 20, amountCents: 100),
  CortinaDryerOption(minutes: 30, amountCents: 150),
  CortinaDryerOption(minutes: 40, amountCents: 200),
  CortinaDryerOption(minutes: 60, amountCents: 300),
  CortinaDryerOption(minutes: 90, amountCents: 450),
];

void main() {
  for (final theme in [lightMode, darkMode]) {
    testWidgets(
      '${theme.brightness.name} selections stay readable and emit all six amounts',
      (tester) async {
        var amountCents = 150;
        final changes = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: StatefulBuilder(
                  builder: (context, setState) => DryerAmountSelector(
                    amountCents: amountCents,
                    options: _options,
                    onChanged: (value) {
                      changes.add(value);
                      setState(() => amountCents = value);
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        void expectSelection() {
          expect(find.byType(OutlinedButton), findsNWidgets(6));
          for (final option in _options) {
            final label = find.text(
              '${option.minutes} min\n'
              '\$${(option.amountCents / 100).toStringAsFixed(2)}',
            );
            expect(label, findsOneWidget);
            final element = tester.element(label);
            final button = element
                .findAncestorWidgetOfExactType<OutlinedButton>()!;
            if (option.amountCents == amountCents) {
              final foreground = DefaultTextStyle.of(element).style.color!;
              final background = element
                  .findAncestorWidgetOfExactType<Material>()!
                  .color!;
              expect(foreground, Colors.white);
              expect(background, theme.colorScheme.primaryContainer);
              final a = foreground.computeLuminance();
              final b = background.computeLuminance();
              final contrast = a > b
                  ? (a + 0.05) / (b + 0.05)
                  : (b + 0.05) / (a + 0.05);
              expect(contrast, greaterThanOrEqualTo(4.5));
              expect(
                find.text(
                  '${option.minutes} minutes for '
                  '\$${(amountCents / 100).toStringAsFixed(2)}',
                ),
                findsOneWidget,
              );
            } else {
              expect(button.style!.foregroundColor?.resolve({}), isNull);
              expect(button.style!.backgroundColor?.resolve({}), isNull);
              expect(
                DefaultTextStyle.of(element).style.color,
                theme.colorScheme.primary,
              );
            }
          }
        }

        expect(changes, isEmpty);
        expectSelection();
        for (var index = 0; index < _options.length; index++) {
          await tester.tap(find.byType(OutlinedButton).at(index));
          await tester.pumpAndSettle();
          expect(changes, _options.take(index + 1).map((o) => o.amountCents));
          expectSelection();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
