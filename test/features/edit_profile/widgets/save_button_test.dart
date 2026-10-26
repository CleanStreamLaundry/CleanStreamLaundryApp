import 'package:clean_stream_laundry_app/features/edit_profile/widgets/save_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({bool isSaving = false, VoidCallback? onPressed}) {
    return MaterialApp(
      home: Scaffold(
        body: SaveButton(isSaving: isSaving, onPressed: onPressed ?? () {}),
      ),
    );
  }

  group('SaveButton', () {
    testWidgets('reflows at narrow width with doubled bold text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              boldText: true,
            ),
            child: Scaffold(
              body: SizedBox(
                width: 240,
                child: SaveButton(isSaving: false, onPressed: () {}),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(
        tester.getSize(find.byType(ElevatedButton)).height,
        greaterThanOrEqualTo(48),
      );
    });

    group('Idle state', () {
      testWidgets('displays Save Changes text', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Save Changes'), findsOneWidget);
      });

      testWidgets('displays check_circle_outline icon', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      });

      testWidgets('button is enabled', (tester) async {
        await tester.pumpWidget(buildWidget());

        final button = tester.widget<ElevatedButton>(
          find.byType(ElevatedButton),
        );
        expect(button.onPressed, isNotNull);
      });

      testWidgets('calls onPressed when tapped', (tester) async {
        var tapped = false;
        await tester.pumpWidget(buildWidget(onPressed: () => tapped = true));

        await tester.tap(find.byType(ElevatedButton));

        expect(tapped, isTrue);
      });
    });

    group('Saving state', () {
      testWidgets('displays CircularProgressIndicator', (tester) async {
        await tester.pumpWidget(buildWidget(isSaving: true));

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('hides Save Changes text', (tester) async {
        await tester.pumpWidget(buildWidget(isSaving: true));

        expect(find.text('Save Changes'), findsNothing);
      });

      testWidgets('button is disabled', (tester) async {
        await tester.pumpWidget(buildWidget(isSaving: true));

        final button = tester.widget<ElevatedButton>(
          find.byType(ElevatedButton),
        );
        expect(button.onPressed, isNull);
      });

      testWidgets('does not call onPressed when tapped while saving', (
        tester,
      ) async {
        var tapped = false;
        await tester.pumpWidget(
          buildWidget(isSaving: true, onPressed: () => tapped = true),
        );

        await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);

        expect(tapped, isFalse);
      });
    });
  });
}
