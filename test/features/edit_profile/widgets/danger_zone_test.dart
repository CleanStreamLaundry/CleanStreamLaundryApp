import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/danger_zone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({bool isSaving = false, VoidCallback? onDeletePressed}) {
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
        testWidgets(
          'unknown outcome fits $width/${scale}x ${theme.brightness.name}',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            var checks = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: SingleChildScrollView(
                      child: DangerZoneSection(
                        isSaving: false,
                        needsStatusCheck: true,
                        message:
                            'The outcome could not be confirmed. Check account status before making another request.',
                        onDeletePressed: () => checks++,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.ensureVisible(find.text('Check Account Status'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Check Account Status'));
            expect(checks, 1);
          },
        );
      }
    }
    testWidgets('${theme.brightness.name} danger text has readable contrast', (
      tester,
    ) async {
      var callbacks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: DangerZoneSection(
              isSaving: false,
              onDeletePressed: () => callbacks++,
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DangerZoneSection),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(
        find.descendant(
          of: find.byWidget(container),
          matching: find.byType(OutlinedButton),
        ),
        findsNothing,
      );
      expect(decoration.color, Colors.red.withValues(alpha: 0.05));
      final fill = Color.alphaBlend(
        decoration.color!,
        theme.colorScheme.surface,
      );
      for (final label in [
        find.text('Danger Zone'),
        find.textContaining(
          'Request account deletion with a 90-day recovery window.',
        ),
        find.text('Delete Account'),
      ]) {
        final foreground = tester
            .renderObject<RenderParagraph>(label)
            .text
            .style!
            .color!;
        final background = tester.widget<Text>(label).data == 'Delete Account'
            ? theme.colorScheme.surface
            : fill;
        final a = Color.alphaBlend(foreground, background).computeLuminance();
        final b = background.computeLuminance();
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
            'Request account deletion with a 90-day recovery window. You must explicitly restore your account before the exact deadline; signing in alone does not cancel deletion. After expiry, your login and ordinary profile will be deleted. Free promotional credits and reward progress cancel on final deletion. Purchased credit never automatically expires or is forfeited. Minimal ownership and financial records remain until paid credit is used, refunded or legally remitted, and while payments or refunds are unresolved. Contact support@cleanstreamlaundry.com with your payment receipt for help reclaiming paid credit after deletion. Refund eligibility is unchanged.',
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

      testWidgets('shows CircularProgressIndicator in button while saving', (
        tester,
      ) async {
        await tester.pumpWidget(buildWidget(isSaving: true));

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('hides Delete Account text while saving', (tester) async {
        await tester.pumpWidget(buildWidget(isSaving: true));

        expect(find.text('Delete Account'), findsNothing);
      });

      testWidgets('does not call onDeletePressed when tapped while saving', (
        tester,
      ) async {
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
