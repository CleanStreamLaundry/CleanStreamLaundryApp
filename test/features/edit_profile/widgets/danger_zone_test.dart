import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/danger_zone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({
    bool isSaving = false,
    VoidCallback? onDeletePressed,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: DangerZoneSection(
          isSaving: isSaving,
          onDeletePressed: onDeletePressed ?? () {},
        ),
      ),
    );
  }

  for (final theme in [lightMode, darkMode]) {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('unknown outcome fits $width/${scale}x ${theme.brightness.name}', (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var checks = 0;
          await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Scaffold(body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SingleChildScrollView(child: DangerZoneSection(
                isSaving: false,
                needsStatusCheck: true,
                message: 'The outcome could not be confirmed. Check account status before making another request.',
                onDeletePressed: () => checks++,
              )),
            )),
          ));
          await tester.ensureVisible(find.text('Check Account Status'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Check Account Status'));
          expect(checks, 1);
        });
      }
    }
    testWidgets('${theme.brightness.name} danger text has readable contrast', (
      tester,
    ) async {
      var callbacks = 0;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(body: DangerZoneSection(
          isSaving: false,
          onDeletePressed: () => callbacks++,
        )),
      ));
      final container = tester.widget<Container>(find.descendant(
        of: find.byType(DangerZoneSection),
        matching: find.byType(Container),
      ).first);
      final fill = Color.alphaBlend(
        (container.decoration! as BoxDecoration).color!,
        theme.colorScheme.surface,
      );
      for (final label in [
        find.text('Danger Zone'),
        find.textContaining('Request account deletion with a 30-day recovery window.'),
        find.text('Delete Account'),
      ]) {
        final foreground = tester.renderObject<RenderParagraph>(label).text.style!.color!;
        final a = Color.alphaBlend(foreground, fill).computeLuminance();
        final b = fill.computeLuminance();
        final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
      await tester.tap(find.byType(OutlinedButton));
      expect(callbacks, 1);
    });
  }

  group('DangerZoneSection', () {
    group('Rendering', () {
      testWidgets('displays Danger Zone header', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Danger Zone'), findsOneWidget);
      });

      testWidgets('displays warning icon', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      });

      testWidgets('displays Delete Account button text', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Delete Account'), findsOneWidget);
      });

      testWidgets('displays delete_outline icon in button', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      });

      testWidgets('displays warning description text', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(
          find.text(
            'Request account deletion with a 30-day recovery window. Account access will be restricted until you sign in again and explicitly restore it before the deadline. Financial records and your Loyalty Card balance are not erased by this request.',
          ),
          findsOneWidget,
        );
      });
    });

    group('Idle state', () {
      testWidgets('delete button is enabled', (tester) async {
        await tester.pumpWidget(buildWidget());

        final button = tester.widget<OutlinedButton>(
          find.byType(OutlinedButton),
        );
        expect(button.onPressed, isNotNull);
      });

      testWidgets('calls onDeletePressed when tapped', (tester) async {
        var tapped = false;
        await tester.pumpWidget(
          buildWidget(onDeletePressed: () => tapped = true),
        );

        await tester.tap(find.byType(OutlinedButton));

        expect(tapped, isTrue);
      });
    });

    group('Saving state', () {
      testWidgets('delete button is disabled while saving', (tester) async {
        await tester.pumpWidget(buildWidget(isSaving: true));

        final button = tester.widget<OutlinedButton>(
          find.byType(OutlinedButton),
        );
        expect(button.onPressed, isNull);
      });

      testWidgets('shows CircularProgressIndicator in button while saving',
              (tester) async {
            await tester.pumpWidget(buildWidget(isSaving: true));

            expect(find.byType(CircularProgressIndicator), findsOneWidget);
          });

      testWidgets('hides Delete Account text while saving', (tester) async {
        await tester.pumpWidget(buildWidget(isSaving: true));

        expect(find.text('Delete Account'), findsNothing);
      });

      testWidgets('does not call onDeletePressed when tapped while saving',
              (tester) async {
            var tapped = false;
            await tester.pumpWidget(
              buildWidget(isSaving: true, onDeletePressed: () => tapped = true),
            );

            await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);

            expect(tapped, isFalse);
          });
    });
  });
}
