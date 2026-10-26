@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/start_machine/start_machine.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../features/start_machine/mocks.dart';
import 'real_font_fallback.dart';
import 'secondary_ui_render_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final size in [const Size(360, 780), const Size(430, 932)]) {
    for (final theme in [lightMode, darkMode]) {
      testWidgets('beta Start ${size.width.toInt()} ${theme.brightness.name}', (
        tester,
      ) async {
        await GetIt.I.reset();
        GetIt.I.registerSingleton<AuthService>(MockAuthService());
        GetIt.I.registerSingleton<ProfileService>(MockProfileService());
        addTearDown(GetIt.I.reset);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        final router = GoRouter(
          initialLocation: '/startPage',
          routes: [
            GoRoute(path: '/startPage', builder: (_, _) => const StartPage()),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
              ),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final element in find.byType(Image).evaluate()) {
          final image = element.widget as Image;
          await tester.runAsync(() => precacheImage(image.image, element));
        }
        await tester.pumpAndSettle();
        await applyRealFontFallback(tester);
        expect(find.text('Unlock Door'), findsNothing);
        expect(find.text('Tap to Pay'), findsOneWidget);
        expect(find.text('Scan QR code'), findsOneWidget);
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('RENDER_DIR');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 3);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(
              '$output/start-${size.width.toInt()}-${theme.brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
