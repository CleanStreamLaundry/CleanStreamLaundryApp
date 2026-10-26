import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/name_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({
    TextEditingController? controller,
    bool enabled = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Form(
          child: NameFormField(
            controller: controller ?? TextEditingController(),
            enabled: enabled,
          ),
        ),
      ),
    );
  }

  for (final theme in [lightMode, darkMode]) {
    for (final value in ['', 'Example Customer']) {
      for (final focused in [false, true]) {
        testWidgets(
          '${theme.brightness.name} ${value.isEmpty ? 'empty' : 'filled'} '
          '${focused ? 'focused' : 'unfocused'} name text has readable contrast',
          (tester) async {
            final controller = TextEditingController(text: value);
            addTearDown(controller.dispose);
            await tester.pumpWidget(MaterialApp(
              theme: theme,
              home: Scaffold(body: NameFormField(
                controller: controller,
                enabled: true,
              )),
            ));
            if (focused) await tester.tap(find.byType(TextFormField));
            await tester.pumpAndSettle();
            final decoration = tester.widget<TextField>(find.byType(TextField)).decoration!;
            final surface = theme.colorScheme.surface;
            final fill = Color.alphaBlend(decoration.fillColor!, surface);
            final pairs = {
              'New Full Name': fill,
              if (value.isEmpty && focused) 'Enter your full name': fill,
            };
            for (final pair in pairs.entries) {
              final foreground = tester.renderObject<RenderParagraph>(
                find.descendant(of: find.text(pair.key), matching: find.byType(RichText)),
              ).text.style!.color!;
              final a = Color.alphaBlend(foreground, pair.value).computeLuminance();
              final b = pair.value.computeLuminance();
              final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
              expect(ratio, greaterThanOrEqualTo(4.5), reason: pair.key);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  group('NameFormField', () {
    group('Rendering', () {
      testWidgets('displays label text', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('New Full Name'), findsOneWidget);
      });

      testWidgets('displays hint text', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Enter your full name'), findsOneWidget);
      });

      testWidgets('displays person outline prefix icon', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.byIcon(Icons.person_outline), findsOneWidget);
      });

      testWidgets('is enabled by default', (tester) async {
        final controller = TextEditingController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.enterText(find.byType(TextFormField), 'Test');

        expect(controller.text, 'Test');
      });

      testWidgets('is disabled when enabled is false', (tester) async {
        final controller = TextEditingController();
        await tester.pumpWidget(
          buildWidget(controller: controller, enabled: false),
        );

        final field = tester.widget<TextFormField>(find.byType(TextFormField));
        expect(field.enabled, isFalse);
      });
    });

    group('Input formatters', () {
      testWidgets('allows long names without a length cap or counter', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(buildWidget(controller: controller));
        final name = 'A' * 200;
        await tester.enterText(
          find.byType(TextFormField),
          name,
        );
        await tester.pump();

        expect(controller.text, name);
        expect(tester.widget<TextField>(find.byType(TextField)).maxLength, isNull);
        expect(find.text('200/36'), findsNothing);
      });

      testWidgets('strips special characters', (tester) async {
        final controller = TextEditingController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.enterText(find.byType(TextFormField), 'Test@#\$%');
        await tester.pump();

        expect(controller.text, 'Test');
      });

      testWidgets('allows letters, numbers, and spaces', (tester) async {
        final controller = TextEditingController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.enterText(find.byType(TextFormField), 'John Doe 123');
        await tester.pump();

        expect(controller.text, 'John Doe 123');
      });
    });

    group('Validation', () {
      testWidgets('shows error for empty value', (tester) async {
        final formKey = GlobalKey<FormState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Form(
                key: formKey,
                child: NameFormField(
                  controller: TextEditingController(text: ''),
                  enabled: true,
                ),
              ),
            ),
          ),
        );

        formKey.currentState!.validate();
        await tester.pump();

        expect(find.text('Name cannot be empty'), findsOneWidget);
      });

      testWidgets('shows error for whitespace-only value', (tester) async {
        final formKey = GlobalKey<FormState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Form(
                key: formKey,
                child: NameFormField(
                  controller: TextEditingController(text: '   '),
                  enabled: true,
                ),
              ),
            ),
          ),
        );

        formKey.currentState!.validate();
        await tester.pump();

        expect(find.text('Name cannot be empty'), findsOneWidget);
      });

      testWidgets('passes validation for non-empty value', (tester) async {
        final formKey = GlobalKey<FormState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Form(
                key: formKey,
                child: NameFormField(
                  controller: TextEditingController(text: 'John Doe'),
                  enabled: true,
                ),
              ),
            ),
          ),
        );

        final isValid = formKey.currentState!.validate();

        expect(isValid, isTrue);
        expect(find.text('Name cannot be empty'), findsNothing);
      });
    });
  });
}
