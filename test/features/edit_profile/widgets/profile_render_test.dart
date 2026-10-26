@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/name_form.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/widgets/email_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in [lightMode, darkMode]) {
    for (final scale in [1.0, 2.0]) {
      for (final error in [false, true]) {
        testWidgets('profile render name ${theme.brightness.name} ${scale}x '
            '${error ? 'error' : 'hint'} fits with readable contrast', (tester) async {
          await checkProfileFieldRender(
            tester,
            theme: theme,
            scale: scale,
            fixture: 'name-${theme.brightness.name}-$scale-${error ? 'error' : 'hint'}',
            text: error ? 'Name cannot be empty' : 'Enter your full name',
            validate: error,
            field: (controller) => NameFormField(controller: controller, enabled: true),
          );
        });
      }
    }
  }

  for (final theme in [lightMode, darkMode]) {
    for (final scale in [1.0, 2.0]) {
      for (final state in ['hint', 'empty', 'invalid']) {
        testWidgets('profile render email ${theme.brightness.name} ${scale}x '
            '$state fits with readable contrast', (tester) async {
          await checkProfileFieldRender(
            tester,
            theme: theme,
            scale: scale,
            fixture: 'email-${theme.brightness.name}-$scale-$state',
            text: switch (state) {
              'hint' => 'Enter your email address',
              'empty' => 'Email cannot be empty',
              _ => 'Please enter a valid email',
            },
            validate: state != 'hint',
            value: state == 'invalid' ? 'invalidemail' : '',
            field: (controller) => EmailFormField(controller: controller, enabled: true),
          );
        });
      }
    }
  }
}

// Real Roboto replaces the test-only Ahem font for these VM-only render cases.
Future<void> checkProfileFieldRender(
  WidgetTester tester, {
  required ThemeData theme,
  required double scale,
  required String fixture,
  required String text,
  required bool validate,
  required Widget Function(TextEditingController) field,
  String value = '',
}) async {
  await tester.runAsync(() async {
    final override = Platform.environment['PROFILE_TEST_FONT'];
    final font = override == null
        ? File.fromUri(Uri.file(Platform.resolvedExecutable)
            .resolve('../../material_fonts/Roboto-Regular.ttf'))
        : File(override);
    final loader = FontLoader('Roboto')
      ..addFont(font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(File('${font.parent.path}/MaterialIcons-Regular.otf')
          .readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await icons.load();
  });
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = TextEditingController(text: value);
  addTearDown(controller.dispose);
  final formKey = GlobalKey<FormState>();
  final captureKey = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    theme: theme.copyWith(
      platform: TargetPlatform.android,
      textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    ),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: SingleChildScrollView(
          child: RepaintBoundary(
            key: captureKey,
            child: Material(
              color: theme.scaffoldBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Form(key: formKey, child: field(controller)),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byType(TextFormField));
  if (validate) expect(formKey.currentState!.validate(), isFalse);
  await tester.pumpAndSettle();
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  final decoration = tester.widget<TextField>(find.byType(TextField)).decoration!;
  final background = validate
      ? theme.scaffoldBackgroundColor
      : Color.alphaBlend(decoration.fillColor!, theme.scaffoldBackgroundColor);
  final color = paragraph.text.style!.color!;
  final a = Color.alphaBlend(color, background).computeLuminance();
  final b = background.computeLuminance();
  final contrast = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
  debugPrint('$fixture contrast=${contrast.toStringAsFixed(3)} '
      'truncated=${paragraph.didExceedMaxLines} size=${paragraph.size}');

  final output = Platform.environment['PROFILE_RENDER_DIR'];
  if (output != null) {
    final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await Directory(output).create(recursive: true);
      await File('$output/$fixture.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  expect(tester.takeException(), isNull);
  expect(contrast, greaterThanOrEqualTo(4.5), reason: '$fixture contrast');
  if (validate && theme.brightness == Brightness.light) {
    expect(color, theme.colorScheme.error, reason: 'Preserve light error color');
  }
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.didExceedMaxLines, isFalse, reason: '$fixture truncation');
  for (var index = 0; index < text.length; index++) {
    if (text[index].trim().isEmpty) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + 1),
    );
    expect(boxes, isNotEmpty, reason: '$fixture missing character $index');
    for (final box in boxes) {
      expect(box.left, greaterThanOrEqualTo(-0.01));
      // Glyph selection boxes may overhang their logical line by a subpixel.
      expect(box.right, lessThanOrEqualTo(paragraph.size.width + 1));
      expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
    }
  }
  final fieldBounds = tester.getRect(find.byType(TextFormField));
  final textBounds = paragraph.localToGlobal(Offset.zero) & paragraph.size;
  expect(textBounds.left, greaterThanOrEqualTo(fieldBounds.left));
  expect(textBounds.right, lessThanOrEqualTo(fieldBounds.right));
  expect(textBounds.bottom, lessThanOrEqualTo(fieldBounds.bottom));
}
