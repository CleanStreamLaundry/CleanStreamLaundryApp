import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/verify_code/widgets/code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget({
    TextEditingController? controller,
    String? error,
    ValueChanged<String>? onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: VerificationCodeField(
          controller: controller ?? TextEditingController(),
          error: error,
          onChanged: onChanged,
        ),
      ),
    );
  }

  group('VerificationCodeField', () {
    for (final theme in [lightMode, darkMode]) {
      testWidgets('keeps six-digit input at 2x in ${theme.brightness}', (
        tester,
      ) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        String? changed;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                boldText: true,
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: 280,
                    child: VerificationCodeField(
                      controller: controller,
                      onChanged: (value) => changed = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), '123456');
        expect(controller.text, '123456');
        expect(changed, '123456');
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.maxLength, 6);
        expect(field.style?.letterSpacing, 0);
        expect(
          tester.getSize(find.byType(TextField)).height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
      });
    }

    group('Rendering', () {
      testWidgets('displays default label when no error', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('6-digit code'), findsOneWidget);
      });

      testWidgets('displays error text as label when error is set', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildWidget(error: 'Please enter the 6-digit code'),
        );
        expect(find.text('Please enter the 6-digit code'), findsOneWidget);
      });

      testWidgets('displays lock icon', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byIcon(Icons.lock), findsOneWidget);
      });

      testWidgets('is centered text', (tester) async {
        await tester.pumpWidget(buildWidget());
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.textAlign, TextAlign.center);
      });

      testWidgets('has max length of 6', (tester) async {
        await tester.pumpWidget(buildWidget());
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.maxLength, 6);
      });

      testWidgets('uses numeric keyboard', (tester) async {
        await tester.pumpWidget(buildWidget());
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.keyboardType, TextInputType.number);
      });

      testWidgets('lock icon is red when error is set', (tester) async {
        await tester.pumpWidget(buildWidget(error: 'Some error'));
        final icon = tester.widget<Icon>(find.byIcon(Icons.lock));
        expect(icon.color, Colors.red);
      });
    });

    group('Interaction', () {
      testWidgets('accepts text input via controller', (tester) async {
        final controller = TextEditingController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.enterText(find.byType(TextField), '123456');
        expect(controller.text, '123456');
      });

      testWidgets('calls onChanged when text is entered', (tester) async {
        String? changed;
        await tester.pumpWidget(buildWidget(onChanged: (v) => changed = v));

        await tester.enterText(find.byType(TextField), '1');
        expect(changed, '1');
      });
    });
  });
}
