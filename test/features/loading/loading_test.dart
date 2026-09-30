import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/loading/controller.dart';
import 'package:clean_stream_laundry_app/features/loading/loading.dart';
import 'package:clean_stream_laundry_app/features/loading/widgets/error_view.dart';
import 'package:clean_stream_laundry_app/features/loading/widgets/logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'mocks.dart';

class _FakeController extends LoadingPageController {
  _FakeController({String? error})
      : super(
    authService: MockAuthService(),
    appLinks: MockAppLinks(),
  ) {
    this.error = error;
  }

  @override
  Future<void> init({
    required void Function(String route, {Object? extra}) navigate,
    required ValueGetter<bool> isMounted,
  }) async {
  }
}


Widget _withRouter(Widget child, {ThemeData? theme}) {
  final router = GoRouter(
    initialLocation: '/test',
    routes: [
      GoRoute(path: '/test', builder: (_, __) => child),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/homePage', builder: (_, __) => const Scaffold()),
    ],
  );
  return MaterialApp.router(theme: theme, routerConfig: router);
}

void main() {
  for (final theme in [lightMode, darkMode]) {
    testWidgets(
      '${theme.brightness.name} surface persists from first frame to error',
      (tester) async {
        final controller = _FakeController();
        final boundaryKey = GlobalKey();
        final surface = theme.colorScheme.surface.toARGB32();
        final expectedRgba = [
          (surface >> 16) & 0xff,
          (surface >> 8) & 0xff,
          surface & 0xff,
          255,
        ];

        Future<void> expectSurface() async {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              final offset = (image.width + 1) * 4;
              expect(bytes.sublist(offset, offset + 4), expectedRgba);
            } finally {
              image.dispose();
            }
          });
        }

        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: _withRouter(
              LoadingPage(controller: controller),
              theme: theme,
            ),
          ),
        );
        await expectSurface();
        expect(find.byType(Logo), findsOneWidget);
        for (final delay in [16, 500]) {
          await tester.pump(Duration(milliseconds: delay));
          await expectSurface();
          expect(find.byType(Logo), findsOneWidget);
        }
        controller.error = 'Late error';
        controller.notifyListeners();
        await tester.pump();
        await expectSurface();
        await tester.pump(const Duration(milliseconds: 16));
        await expectSurface();
        expect(find.byType(Logo), findsNothing);
        expect(find.byType(ErrorView), findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('Late error'),
            matching: find.byType(RichText),
          ),
        );
        expect(
          paragraph.text.style!.fontFamily,
          theme.textTheme.bodyMedium!.fontFamily,
        );
        expect(paragraph.text.style!.decoration, TextDecoration.none);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('LoadingPage', () {
    testWidgets('shows Logo when controller has no error', (tester) async {
      final controller = _FakeController();

      await tester.pumpWidget(_withRouter(LoadingPage(controller: controller)));
      await tester.pump();

      expect(find.byType(Logo), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing);
    });

    testWidgets('shows ErrorView when controller has an error', (tester) async {
      final controller = _FakeController(error: 'Something went wrong');

      await tester.pumpWidget(_withRouter(LoadingPage(controller: controller)));
      await tester.pump();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.byType(Logo), findsNothing);
    });

    testWidgets('rebuilds and shows ErrorView when error is set after init',
            (tester) async {
          final controller = _FakeController();

          await tester.pumpWidget(_withRouter(LoadingPage(controller: controller)));
          await tester.pump();

          expect(find.byType(Logo), findsOneWidget);

          controller.error = 'Late error';
          controller.notifyListeners();
          await tester.pump();

          expect(find.byType(ErrorView), findsOneWidget);
          expect(find.byType(Logo), findsNothing);
        });

    testWidgets('dispose does not throw when widgets is removed', (tester) async {
      final controller = _FakeController();

      await tester.pumpWidget(_withRouter(LoadingPage(controller: controller)));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      expect(tester.takeException(), isNull);
    });
  });
}
