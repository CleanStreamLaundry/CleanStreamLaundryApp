import 'package:clean_stream_laundry_app/features/scanner/widgets/scanner_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({VoidCallback? onCancel}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(
          child: ScannerOverlay(onCancel: onCancel ?? () {}),
        ),
      ),
    );
  }

  group('ScannerOverlay', () {
    group('Rendering', () {
      testWidgets('displays instruction text', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('Center the machine QR code'), findsOneWidget);
      });

      testWidgets('displays Cancel button', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(
          find.widgetWithText(FloatingActionButton, 'Cancel'),
          findsOneWidget,
        );
      });

      testWidgets('displays close icon in Cancel button', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byIcon(Icons.close), findsOneWidget);
      });

      testWidgets('Cancel button has red background', (tester) async {
        await tester.pumpWidget(buildWidget());
        final fab = tester.widget<FloatingActionButton>(
          find.widgetWithText(FloatingActionButton, 'Cancel'),
        );
        expect(fab.backgroundColor, Colors.red);
      });

      testWidgets('displays scanning frame with correct size', (tester) async {
        await tester.pumpWidget(buildWidget());

        final frameFinder = find.byWidgetPredicate((widget) {
          if (widget is Container && widget.decoration is BoxDecoration) {
            final decoration = widget.decoration as BoxDecoration;
            final border = decoration.border as Border?;
            return border?.top.color == Colors.white &&
                border?.top.width == 3 &&
                decoration.borderRadius == BorderRadius.circular(12);
          }
          return false;
        });

        expect(frameFinder, findsOneWidget);

        final container = tester.widget<Container>(frameFinder);
        expect(container.constraints?.maxWidth, 250);
        expect(container.constraints?.maxHeight, 250);
      });
    });

    group('Interaction', () {
      testWidgets('calls onCancel when Cancel button is tapped', (
        tester,
      ) async {
        var tapped = false;
        await tester.pumpWidget(buildWidget(onCancel: () => tapped = true));

        await tester.tap(find.widgetWithText(FloatingActionButton, 'Cancel'));
        expect(tapped, isTrue);
      });
    });
  });
}
