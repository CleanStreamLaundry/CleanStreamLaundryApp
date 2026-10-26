import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/email_form.dart';
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
          child: EmailFormField(
            controller: controller ?? TextEditingController(),
            enabled: enabled,
          ),
        ),
      ),
    );
  }

  for (final theme in [lightMode, darkMode]) {
    for (final value in ['', 'customer@example.test']) {
      for (final focused in [false, true]) {
        testWidgets(
          '${theme.brightness.name} ${value.isEmpty ? 'empty' : 'filled'} '
          '${focused ? 'focused' : 'unfocused'} email text has readable contrast',
          (tester) async {
            final controller = TextEditingController(text: value);
            addTearDown(controller.dispose);
            await tester.pumpWidget(MaterialApp(
              theme: theme,
              home: Scaffold(body: EmailFormField(
                controller: controller,
                enabled: true,
              )),
            ));
            if (focused) await tester.tap(find.byType(TextFormField));
            await tester.pumpAndSettle();
            final decoration = tester.widget<TextField>(find.byType(TextField)).decoration!;
            final fill = Color.alphaBlend(decoration.fillColor!, theme.colorScheme.surface);
            for (final label in [
              'New Email',
              if (value.isEmpty && focused) 'Enter your email address',
            ]) {
              final foreground = tester.renderObject<RenderParagraph>(
                find.descendant(of: find.text(label), matching: find.byType(RichText)),
              ).text.style!.color!;
              final a = Color.alphaBlend(foreground, fill).computeLuminance();
              final b = fill.computeLuminance();
              final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
              expect(ratio, greaterThanOrEqualTo(4.5), reason: label);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  group('EmailFormField', () {
    group('Rendering', () {
      testWidgets('displays label text', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('New Email'), findsOneWidget);
      });

      testWidgets('displays hint text', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Enter your email address'), findsOneWidget);
      });

      testWidgets('displays email prefix icon', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.byIcon(Icons.email_outlined), findsOneWidget);
      });

      testWidgets('is enabled by default', (tester) async {
        final controller = TextEditingController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.enterText(find.byType(TextFormField), 'test@example.com');

        expect(controller.text, 'test@example.com');
      });

      testWidgets('is disabled when enabled is false', (tester) async {
        await tester.pumpWidget(buildWidget(enabled: false));

        final field = tester.widget<TextFormField>(find.byType(TextFormField));
        expect(field.enabled, isFalse);
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
                child: EmailFormField(
                  controller: TextEditingController(text: ''),
                  enabled: true,
                ),
              ),
            ),
          ),
        );

        formKey.currentState!.validate();
        await tester.pump();

        expect(find.text('Email cannot be empty'), findsOneWidget);
      });

      testWidgets('shows error for whitespace-only value', (tester) async {
        final formKey = GlobalKey<FormState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Form(
                key: formKey,
                child: EmailFormField(
                  controller: TextEditingController(text: '   '),
                  enabled: true,
                ),
              ),
            ),
          ),
        );

        formKey.currentState!.validate();
        await tester.pump();

        expect(find.text('Email cannot be empty'), findsOneWidget);
      });

      testWidgets('shows error for value without @', (tester) async {
        final formKey = GlobalKey<FormState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Form(
                key: formKey,
                child: EmailFormField(
                  controller: TextEditingController(text: 'invalidemail'),
                  enabled: true,
                ),
              ),
            ),
          ),
        );

        formKey.currentState!.validate();
        await tester.pump();

        expect(find.text('Please enter a valid email'), findsOneWidget);
      });

      testWidgets('passes validation for valid email', (tester) async {
        final formKey = GlobalKey<FormState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Form(
                key: formKey,
                child: EmailFormField(
                  controller: TextEditingController(text: 'user@example.com'),
                  enabled: true,
                ),
              ),
            ),
          ),
        );

        final isValid = formKey.currentState!.validate();

        expect(isValid, isTrue);
        expect(find.text('Please enter a valid email'), findsNothing);
        expect(find.text('Email cannot be empty'), findsNothing);
      });
    });
  });
}
