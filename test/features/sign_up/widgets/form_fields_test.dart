import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/features/sign_up/widgets/form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController nameCtrl;
  late TextEditingController emailCtrl;
  late TextEditingController passwordCtrl;
  late TextEditingController confirmCtrl;

  setUp(() {
    nameCtrl = TextEditingController();
    emailCtrl = TextEditingController();
    passwordCtrl = TextEditingController();
    confirmCtrl = TextEditingController();
  });

  tearDown(() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    confirmCtrl.dispose();
  });

  Widget buildWidget({
    Color iconColor = Colors.blue,
    Color labelColor = Colors.blue,
    bool obscurePassword = true,
    bool obscureConfirm = true,
    String passwordLabel = 'Password',
    String confirmLabel = 'Confirm Password',
    VoidCallback? onTogglePassword,
    VoidCallback? onToggleConfirm,
    ValueChanged<String>? onPasswordChanged,
    ValueChanged<String>? onConfirmChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SignUpFormFields(
            nameController: nameCtrl,
            emailController: emailCtrl,
            passwordController: passwordCtrl,
            confirmController: confirmCtrl,
            passwordLabel: passwordLabel,
            confirmLabel: confirmLabel,
            iconColor: iconColor,
            labelColor: labelColor,
            obscurePassword: obscurePassword,
            obscureConfirmPassword: obscureConfirm,
            onTogglePassword: onTogglePassword ?? () {},
            onToggleConfirm: onToggleConfirm ?? () {},
            onPasswordChanged: onPasswordChanged ?? (_) {},
            onConfirmChanged: onConfirmChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  group('SignUpFormFields', () {
    group('Rendering', () {
      testWidgets('displays four TextFields', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byType(TextField), findsNWidgets(4));
      });

      testWidgets('displays Name label', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('Name'), findsOneWidget);
      });

      testWidgets('displays Email label', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('Email'), findsOneWidget);
      });

      testWidgets('displays Password label', (tester) async {
        await tester.pumpWidget(buildWidget(passwordLabel: 'Password'));
        expect(find.text('Password'), findsOneWidget);
      });

      testWidgets('displays Confirm Password label', (tester) async {
        await tester.pumpWidget(
            buildWidget(confirmLabel: 'Confirm Password'));
        expect(find.text('Confirm Password'), findsOneWidget);
      });

      testWidgets('shows person icon for name field', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byIcon(Icons.person), findsOneWidget);
      });

      testWidgets('shows email icon for email field', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byIcon(Icons.email), findsOneWidget);
      });

      testWidgets('shows two lock icons for password fields', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byIcon(Icons.lock), findsNWidgets(2));
      });

      testWidgets('shows two visibility_off icons when both obscured',
              (tester) async {
            await tester.pumpWidget(
                buildWidget(obscurePassword: true, obscureConfirm: true));
            expect(find.byIcon(Icons.visibility_off), findsNWidgets(2));
          });
    });

    group('Obscure state', () {
      testWidgets('password field is obscured when obscurePassword is true',
              (tester) async {
            await tester.pumpWidget(buildWidget(obscurePassword: true));
            final field =
            tester.widget<TextField>(find.byType(TextField).at(2));
            expect(field.obscureText, isTrue);
          });

      testWidgets('password field is visible when obscurePassword is false',
              (tester) async {
            await tester.pumpWidget(buildWidget(obscurePassword: false));
            final field =
            tester.widget<TextField>(find.byType(TextField).at(2));
            expect(field.obscureText, isFalse);
            expect(find.byIcon(Icons.visibility), findsAtLeastNWidgets(1));
          });

      testWidgets('confirm field is obscured when obscureConfirm is true',
              (tester) async {
            await tester.pumpWidget(buildWidget(obscureConfirm: true));
            final field =
            tester.widget<TextField>(find.byType(TextField).at(3));
            expect(field.obscureText, isTrue);
          });
    });

    group('Colors', () {
      testWidgets('lock icons use provided iconColor', (tester) async {
        await tester.pumpWidget(buildWidget(iconColor: Colors.red));
        final lockIcons = tester
            .widgetList<Icon>(find.byIcon(Icons.lock))
            .toList();
        for (final icon in lockIcons) {
          expect(icon.color, Colors.red);
        }
      });
    });

    group('Interaction', () {
      testWidgets('password and confirmation actions have distinct stateful semantics',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
        var obscurePassword = true;
        var obscureConfirm = true;
        var passwordToggles = 0;
        var confirmToggles = 0;
        final passwordChanges = <String>[];
        final confirmChanges = <String>[];
        Widget currentFields() => buildWidget(
          obscurePassword: obscurePassword,
          obscureConfirm: obscureConfirm,
          onTogglePassword: () {
            passwordToggles++;
            obscurePassword = !obscurePassword;
          },
          onToggleConfirm: () {
            confirmToggles++;
            obscureConfirm = !obscureConfirm;
          },
          onPasswordChanged: passwordChanges.add,
          onConfirmChanged: confirmChanges.add,
        );
        await tester.pumpWidget(currentFields());
        await tester.enterText(find.byType(TextField).at(2), 'first-password');
        await tester.enterText(find.byType(TextField).at(3), 'confirmation-value');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();

        void expectActions() {
          for (final entry in <String, bool>{
            'password': obscurePassword,
            'confirmation password': obscureConfirm,
          }.entries) {
            final label = '${entry.value ? 'Show' : 'Hide'} ${entry.key}';
            final button = find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == label,
            );
            final data = tester.getSemantics(button).getSemanticsData();
            expect(data.tooltip, label);
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          }
          expect(tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
              obscurePassword);
          expect(tester.widget<TextField>(find.byType(TextField).at(3)).obscureText,
              obscureConfirm);
          expect(passwordCtrl.text, 'first-password');
          expect(confirmCtrl.text, 'confirmation-value');
          expect(passwordChanges, ['first-password']);
          expect(confirmChanges, ['confirmation-value']);
        }

        expectActions();
        for (final label in [
          'Show password',
          'Show confirmation password',
          'Hide password',
          'Hide confirmation password',
        ]) {
          await tester.ensureVisible(find.byTooltip(label));
          await tester.tap(find.byTooltip(label));
          await tester.pumpWidget(currentFields());
          await tester.pumpAndSettle();
          expectActions();
        }
        expect(passwordToggles, 2);
        expect(confirmToggles, 2);
        } finally {
          semantics.dispose();
        }
      });

      testWidgets('calls onTogglePassword when first suffix icon tapped',
              (tester) async {
            var tapped = false;
            await tester.pumpWidget(
                buildWidget(onTogglePassword: () => tapped = true));

            await tester.tap(find.byIcon(Icons.visibility_off).first);
            expect(tapped, isTrue);
          });

      testWidgets('calls onToggleConfirm when second suffix icon tapped',
              (tester) async {
            var tapped = false;
            await tester.pumpWidget(
                buildWidget(onToggleConfirm: () => tapped = true));

            await tester.tap(find.byIcon(Icons.visibility_off).last);
            expect(tapped, isTrue);
          });

      testWidgets('calls onPasswordChanged when password text changes',
              (tester) async {
            String? changed;
            await tester.pumpWidget(
                buildWidget(onPasswordChanged: (v) => changed = v));

            await tester.enterText(find.byType(TextField).at(2), 'hello');
            expect(changed, 'hello');
          });

      testWidgets('calls onConfirmChanged when confirm text changes',
              (tester) async {
            String? changed;
            await tester.pumpWidget(
                buildWidget(onConfirmChanged: (v) => changed = v));

            await tester.enterText(find.byType(TextField).at(3), 'world');
            expect(changed, 'world');
          });

      testWidgets('name field accepts text via controller', (tester) async {
        await tester.pumpWidget(buildWidget());
        await tester.enterText(find.byType(TextField).at(0), 'John Doe');
        expect(nameCtrl.text, 'John Doe');
      });

      testWidgets('name field has no length cap or counter', (tester) async {
        await tester.pumpWidget(buildWidget());
        final field =
        tester.widget<TextField>(find.byType(TextField).at(0));
        final name = 'A' * 200;
        await tester.enterText(find.byType(TextField).first, name);
        await tester.pump();
        expect(nameCtrl.text, name);
        expect(field.maxLength, isNull);
        expect(find.text('200/36'), findsNothing);
      });
    });

    group('Error label', () {
      testWidgets('shows custom error label on password field when set',
              (tester) async {
            await tester.pumpWidget(
              buildWidget(
                passwordLabel: "Passwords don't match",
                confirmLabel: "Passwords don't match",
              ),
            );

            expect(
              find.text("Passwords don't match"),
              findsNWidgets(2),
            );
          });
    });
  });
}
