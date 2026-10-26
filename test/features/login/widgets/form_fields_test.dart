import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/features/login/controller.dart';
import 'package:clean_stream_laundry_app/features/login/widgets/form_fields.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks.dart';

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
  });

  Widget buildWidget(LoginController controller) {
    return MaterialApp(
      home: Scaffold(body: _ControllerWrapper(controller: controller)),
    );
  }

  LoginController buildController() => LoginController(
    authService: mockAuthService,
  );

  for (final theme in [lightMode, darkMode]) {
    for (final error in [false, true]) {
      testWidgets('${theme.brightness.name} ${error ? 'error' : 'normal'} labels '
          'remain readable through focus, typing and obscurity changes',
          (tester) async {
        final controller = buildController();
        addTearDown(controller.disposeController);
        if (error) controller.setErrorColors();
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(body: _ControllerWrapper(controller: controller)),
        ));
        final fields = find.byType(TextField);

        void expectReadableLabels() {
          for (var index = 0; index < 2; index++) {
            final field = fields.at(index);
            final label = error
                ? 'Invalid Password or Email'
                : index == 0 ? 'Email' : 'Password';
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.descendant(of: field, matching: find.text(label)),
                matching: find.byType(RichText),
              ),
            );
            final material = tester.widget<Material>(find.ancestor(
              of: field,
              matching: find.byType(Material),
            ).first);
            final background = material.color!;
            final foreground = Color.alphaBlend(
              paragraph.text.style!.color!, background,
            );
            final a = foreground.computeLuminance() + .05;
            final b = background.computeLuminance() + .05;
            expect(a > b ? a / b : b / a, greaterThanOrEqualTo(4.5));
            expect(paragraph.didExceedMaxLines, isFalse);
            final decoration = tester.widget<TextField>(field).decoration!;
            expect((decoration.prefixIcon! as Icon).color,
                error ? Colors.red : Colors.blue);
            expect(decoration.enabledBorder!.borderSide.color,
                error ? Colors.red : Colors.grey);
            expect(decoration.focusedBorder!.borderSide.color,
                error ? Colors.red : Colors.blue);
          }
          expect(tester.takeException(), isNull);
        }

        expectReadableLabels();
        for (var index = 0; index < 2; index++) {
          await tester.tap(fields.at(index));
          await tester.pumpAndSettle();
          expectReadableLabels();
          await tester.enterText(fields.at(index),
              index == 0 ? 'reader@example.invalid' : 'synthetic-password');
          await tester.pumpAndSettle();
          expectReadableLabels();
        }
        FocusManager.instance.primaryFocus!.unfocus();
        await tester.pumpAndSettle();
        expectReadableLabels();
        expect(controller.emailController.text, 'reader@example.invalid');
        expect(controller.passwordController.text, 'synthetic-password');
        expect(tester.widget<TextField>(fields.last).obscureText, isTrue);
        await tester.tap(find.byIcon(Icons.visibility_off));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(fields.last).obscureText, isFalse);
        expectReadableLabels();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  group('LoginFormFields', () {
    group('Initial rendering', () {
      testWidgets('displays Email label', (tester) async {
        final controller = buildController();
        await tester.pumpWidget(buildWidget(controller));

        expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
      });

      testWidgets('displays Password label', (tester) async {
        final controller = buildController();
        await tester.pumpWidget(buildWidget(controller));

        expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
      });

      testWidgets('displays email and lock icons in blue', (tester) async {
        final controller = buildController();
        await tester.pumpWidget(buildWidget(controller));

        final emailIcon = tester.widget<Icon>(find.byIcon(Icons.email));
        final lockIcon = tester.widget<Icon>(find.byIcon(Icons.lock));

        expect(emailIcon.color, Colors.blue);
        expect(lockIcon.color, Colors.blue);
      });

      testWidgets('password is obscured by default', (tester) async {
        final controller = buildController();
        await tester.pumpWidget(buildWidget(controller));

        final field = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Password'),
        );
        expect(field.obscureText, isTrue);
      });

      testWidgets('shows visibility_off icon initially', (tester) async {
        final controller = buildController();
        await tester.pumpWidget(buildWidget(controller));

        expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      });
    });

    group('Error state', () {
      testWidgets('shows error label text when setErrorColors called',
              (tester) async {
            final controller = buildController();
            await tester.pumpWidget(buildWidget(controller));

            controller.setErrorColors();
            await tester.pump();

            expect(
              find.widgetWithText(TextField, 'Invalid Password or Email'),
              findsNWidgets(2),
            );
          });

      testWidgets('shows red icons after setErrorColors', (tester) async {
        final controller = buildController();
        await tester.pumpWidget(buildWidget(controller));

        controller.setErrorColors();
        await tester.pump();

        final emailIcon = tester.widget<Icon>(find.byIcon(Icons.email));
        final lockIcon = tester.widget<Icon>(find.byIcon(Icons.lock));

        expect(emailIcon.color, Colors.red);
        expect(lockIcon.color, Colors.red);
      });
    });

    group('Password visibility toggle', () {
      testWidgets('visibility action semantics follow toggles without changing text',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
        final controller = buildController();
        addTearDown(controller.disposeController);
        controller.emailController.text = 'reader@example.invalid';
        controller.passwordController.text = 'synthetic-password';
        await tester.pumpWidget(buildWidget(controller));

        void expectAction(String label, bool obscured) {
          final button = find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == label,
          );
          final data = tester.getSemantics(button).getSemanticsData();
          expect(data.tooltip, label);
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          expect(tester.widget<TextField>(find.byType(TextField).last).obscureText,
              obscured);
          expect(controller.passwordController.text, 'synthetic-password');
          expect(controller.emailController.text, 'reader@example.invalid');
        }

        expectAction('Show password', true);
        await tester.tap(find.byTooltip('Show password'));
        await tester.pumpAndSettle();
        expectAction('Hide password', false);
        controller.setErrorColors();
        await tester.pumpAndSettle();
        expectAction('Hide password', false);
        await tester.tap(find.byTooltip('Hide password'));
        await tester.pumpAndSettle();
        expectAction('Show password', true);
        await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      });

      testWidgets('tapping visibility icon toggles obscureText',
              (tester) async {
            final controller = buildController();
            await tester.pumpWidget(buildWidget(controller));

            // onPressed inside the IconButton calls togglePasswordVisibility
            await tester.tap(find.byIcon(Icons.visibility_off));
            await tester.pump();

            final field = tester.widget<TextField>(
              find.widgetWithText(TextField, 'Password'),
            );
            expect(field.obscureText, isFalse);
          });

      testWidgets('shows visibility icon after toggling', (tester) async {
        final controller = buildController();
        controller.togglePasswordVisibility();
        await tester.pumpWidget(buildWidget(controller));

        expect(find.byIcon(Icons.visibility), findsOneWidget);
        expect(find.byIcon(Icons.visibility_off), findsNothing);
      });
    });
  });
}

class _ControllerWrapper extends StatefulWidget {
  final LoginController controller;
  const _ControllerWrapper({required this.controller});

  @override
  State<_ControllerWrapper> createState() => _ControllerWrapperState();
}

class _ControllerWrapperState extends State<_ControllerWrapper> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FormFields(controller: widget.controller);
}
