import 'package:clean_stream_laundry_app/features/edit_profile/widgets/info_card.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({required String label, required String value}) {
    return MaterialApp(
      home: Scaffold(
        body: InfoCard(label: label, value: value),
      ),
    );
  }

  group('InfoCard', () {
    for (final theme in [lightMode, darkMode]) {
      for (final width in [320.0, 390.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('wraps complete values at $width/${scale}x '
              '${theme.brightness.name}', (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            const values = [
              'Example Customer',
              'customer@example.test',
              'Alexandria Catherine Example Person',
              'alexandria.catherine@laundry.example',
            ];

            await tester.pumpWidget(MaterialApp(
              theme: theme,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        for (final value in values)
                          InfoCard(label: 'Current:', value: value),
                      ],
                    ),
                  ),
                ),
              ),
            ));

            expect(tester.takeException(), isNull);
            for (final value in values) {
              final text = find.text(value);
              final card = find.ancestor(of: text, matching: find.byType(InfoCard));
              final bounds = tester.getRect(card);
              final textBounds = tester.getRect(text);
              final paragraph = tester.renderObject<RenderParagraph>(text);
              expect(paragraph.text.toPlainText(), value);
              expect(paragraph.didExceedMaxLines, isFalse);
              expect(textBounds.left, greaterThanOrEqualTo(bounds.left));
              expect(textBounds.right, lessThanOrEqualTo(bounds.right));
              for (var index = 0; index < value.length; index++) {
                // A wrapped line's trailing space can extend past its bounds.
                if (value[index].trim().isEmpty) continue;
                for (final box in paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: index, extentOffset: index + 1),
                )) {
                  expect(box.left, greaterThanOrEqualTo(-0.01));
                  expect(box.right.floorToDouble(), lessThanOrEqualTo(paragraph.size.width));
                }
              }
            }
          });
        }
      }
    }

    testWidgets('displays the label', (tester) async {
      await tester.pumpWidget(buildWidget(label: 'Current', value: 'John Doe'));

      expect(find.text('Current'), findsOneWidget);
    });

    testWidgets('displays the value', (tester) async {
      await tester.pumpWidget(buildWidget(label: 'Current', value: 'John Doe'));

      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('displays both label and value together', (tester) async {
      await tester.pumpWidget(
        buildWidget(label: 'Email Address', value: 'test@example.com'),
      );

      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('renders inside a Row', (tester) async {
      await tester.pumpWidget(buildWidget(label: 'Current', value: 'Jane'));

      expect(find.byType(Row), findsOneWidget);
    });

    testWidgets('handles empty value gracefully', (tester) async {
      await tester.pumpWidget(buildWidget(label: 'Current', value: ''));

      expect(find.text('Current'), findsOneWidget);
    });
  });
}
