import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/features/reset_protected/widgets/password_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({
    String label = 'New Password',
    bool obscureText = true,
    VoidCallback? onToggleVisibility,
    ValueChanged<String>? onChanged,
    Color iconColor = Colors.blue,
    Color labelColor = Colors.blue,
    TextEditingController? controller,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PasswordField(
          controller: controller ?? TextEditingController(),
          label: label,
          obscureText: obscureText,
          onToggleVisibility: onToggleVisibility ?? () {},
          onChanged: onChanged,
          iconColor: iconColor,
          labelColor: labelColor,
        ),
      ),
    );
  }

  group('PasswordField', () {
    group('Rendering', () {
      testWidgets('displays the label', (tester) async {
        await tester.pumpWidget(buildWidget(label: 'New Password'));
        expect(find.widgetWithText(TextField, 'New Password'), findsOneWidget);
      });

      testWidgets('displays lock icon', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byIcon(Icons.lock), findsOneWidget);
      });

      testWidgets('shows visibility_off icon when obscured', (tester) async {
        await tester.pumpWidget(buildWidget(obscureText: true));
        expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      });

      testWidgets('shows visibility icon when not obscured', (tester) async {
        await tester.pumpWidget(buildWidget(obscureText: false));
        expect(find.byIcon(Icons.visibility), findsOneWidget);
      });

      testWidgets('field is obscured when obscureText is true', (tester) async {
        await tester.pumpWidget(buildWidget(obscureText: true));
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.obscureText, isTrue);
      });

      testWidgets('field is not obscured when obscureText is false',
              (tester) async {
            await tester.pumpWidget(buildWidget(obscureText: false));
            final field = tester.widget<TextField>(find.byType(TextField));
            expect(field.obscureText, isFalse);
          });
    });

    group('Colors', () {
      testWidgets('lock icon uses provided iconColor', (tester) async {
        await tester.pumpWidget(buildWidget(iconColor: Colors.red));
        final icon = tester.widget<Icon>(find.byIcon(Icons.lock));
        expect(icon.color, Colors.red);
      });
    });

    group('Interaction', () {
      for (final confirmation in [false, true]) {
        testWidgets('${confirmation ? 'confirmation' : 'default'} action semantics '
            'follow visibility and preserve callbacks and text', (tester) async {
          final semantics = tester.ensureSemantics();
          try {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          final changed = <String>[];
          var obscured = true;
          var toggles = 0;
          final description = confirmation ? 'confirmation password' : 'password';
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(builder: (context, setState) {
                void toggle() => setState(() {
                  toggles++;
                  obscured = !obscured;
                });
                return confirmation
                    ? PasswordField(
                        controller: controller,
                        label: 'Confirm Password',
                        visibilityLabel: 'confirmation password',
                        obscureText: obscured,
                        onToggleVisibility: toggle,
                        onChanged: changed.add,
                        iconColor: Colors.blue,
                        labelColor: Colors.blue,
                      )
                    : PasswordField(
                        controller: controller,
                        label: 'New Password',
                        obscureText: obscured,
                        onToggleVisibility: toggle,
                        onChanged: changed.add,
                        iconColor: Colors.blue,
                        labelColor: Colors.blue,
                      );
              }),
            ),
          ));
          await tester.enterText(find.byType(TextField), 'synthetic-password');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();

          void expectAction(String verb, bool expectedObscurity) {
            final label = '$verb $description';
            final button = find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == label,
            );
            final data = tester.getSemantics(button).getSemanticsData();
            expect(data.tooltip, label);
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
            expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
                expectedObscurity);
            expect(controller.text, 'synthetic-password');
            expect(changed, ['synthetic-password']);
          }

          expectAction('Show', true);
          await tester.tap(find.byTooltip('Show $description'));
          await tester.pumpAndSettle();
          expectAction('Hide', false);
          await tester.tap(find.byTooltip('Hide $description'));
          await tester.pumpAndSettle();
          expectAction('Show', true);
          expect(toggles, 2);
          await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
          }
        });
      }

      testWidgets('calls onToggleVisibility when suffix icon tapped',
              (tester) async {
            var tapped = false;
            await tester.pumpWidget(
                buildWidget(onToggleVisibility: () => tapped = true));

            await tester.tap(find.byIcon(Icons.visibility_off));
            expect(tapped, isTrue);
          });

      testWidgets('calls onChanged when text is entered', (tester) async {
        String? changed;
        await tester.pumpWidget(
            buildWidget(onChanged: (v) => changed = v));

        await tester.enterText(find.byType(TextField), 'hello');
        expect(changed, 'hello');
      });

      testWidgets('accepts text input via controller', (tester) async {
        final controller = TextEditingController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.enterText(find.byType(TextField), 'MyPassword1!');
        expect(controller.text, 'MyPassword1!');
      });
    });
  });
}
