@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/loyalty/widgets/load_card_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fixtures/loyalty_action_context.dart';

void main() {
  setUpAll(() async {
    final config = File('.dart_tool/package_config.json');
    final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
    final flutter = Directory.fromUri(
      config.absolute.uri.resolve(
        packages.singleWhere((entry) => entry['name'] == 'flutter')['rootUri']
            as String,
      ),
    ).uri;
    for (final family in {
      'Roboto': ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'],
      'MaterialIcons': ['MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final name in family.value) {
        final file = File.fromUri(
          flutter.resolve('../../bin/cache/artifacts/material_fonts/$name'),
        );
        loader.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });

  for (final theme in [lightMode, darkMode]) {
    for (final state in [
      'default',
      'selected',
      'typing',
      'error',
      'large',
      'large-keyboard',
    ]) {
      testWidgets('${theme.brightness.name} $state amount dialog render', (
        tester,
      ) async {
        final large = state.startsWith('large');
        final keyboard =
            state == 'typing' || state == 'error' || state.endsWith('keyboard');
        final size = Size(large && !keyboard ? 320 : 360, 780);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(large ? 2 : 1),
                boldText: true,
              ),
              child: RepaintBoundary(key: boundary, child: child!),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => LoadCardDialog(
                      loadConsent: () async => actionContext(),
                      onPay: (_, _) async {},
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/Icon.png'),
            tester.element(find.byType(LoadCardDialog)),
          ),
        );
        await tester.pumpAndSettle();
        if (state == 'selected') await tester.tap(find.text('\$50'));
        if (keyboard || large) {
          await tester.enterText(
            find.byType(TextField),
            state == 'error'
                ? '0'
                : large
                ? '500.00'
                : '37.25',
          );
        }
        if (keyboard) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final chips = [
          for (final value in [10, 15, 25, 50])
            find.widgetWithText(ChoiceChip, '\$$value'),
        ];
        final first = tester.getRect(chips.first);
        for (final chip in chips) {
          final rect = tester.getRect(chip);
          expect(rect.top, closeTo(first.top, .01));
          expect(rect.width, closeTo(first.width, .01));
          expect(rect.height, greaterThanOrEqualTo(48));
          final text = find
              .descendant(of: chip, matching: find.byType(RichText))
              .first;
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(
            paragraph.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(paragraph.size.width + .01),
          );
        }
        final pay = find.widgetWithText(ElevatedButton, 'Load');
        expect(pay.hitTestable(), findsOneWidget);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        expect(
          tester.getBottomLeft(pay).dy,
          lessThanOrEqualTo(size.height - (keyboard ? 300 : 24)),
        );
        if (!large && !keyboard) {
          expect(
            tester
                .getSize(
                  find
                      .descendant(
                        of: find.byType(Dialog),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .height,
            lessThanOrEqualTo(size.height - 28 - 24 - 48),
          );
          expect(
            find.byTooltip('Increase by 25 cents').hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byTooltip('Decrease by 25 cents').hitTestable(),
            findsOneWidget,
          );
        }
        const output = String.fromEnvironment('RENDER_DIR');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File(
              '$output/${theme.brightness.name}-$state.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
