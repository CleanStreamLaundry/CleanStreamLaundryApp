import 'dart:async';
import 'dart:io';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'package:clean_stream_laundry_app/root_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'core/theme/mocks.dart';

const _logoPath = 'assets/splash-logo.png';

class _ControlledLogoBundle extends CachingAssetBundle {
  Completer<ByteData> logo = Completer<ByteData>();
  final logoLoadStarted = Completer<void>();
  final requestedAssets = <String>[];

  @override
  Future<ByteData> load(String key) {
    if (key == 'AssetManifest.bin') {
      return Future.value(
        const StandardMessageCodec().encodeMessage(<String, Object?>{})!,
      );
    }
    requestedAssets.add(key);
    if (key == _logoPath) {
      if (!logoLoadStarted.isCompleted) logoLoadStarted.complete();
      return logo.future;
    }
    return Future.error(FlutterError('Unexpected asset request: $key'));
  }
}

// Observe the real decoder without replacing the ImageProvider or binding.
Future<(int, int)> _decodedLogo(
  _ControlledLogoBundle bundle, {
  VoidCallback? onDecoded,
}) {
  final decoded = Completer<(int, int)>();
  final stream = const AssetImage(_logoPath).resolve(
    ImageConfiguration(bundle: bundle),
  );
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      onDecoded?.call();
      decoded.complete((image.image.width, image.image.height));
      image.dispose();
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      decoded.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return decoded.future.timeout(const Duration(seconds: 5));
}

void main() {
  for (final preference in <String?, Brightness>{
    'darkMode': Brightness.dark,
    'lightMode': Brightness.light,
    null: Brightness.light,
    'invalid': Brightness.light,
  }.entries) {
    testWidgets('first app frame restores preference ${preference.key}', (
      tester,
    ) async {
      final storage = MockStorageService();
      final storageReady = Completer<void>();
      final savedTheme = Completer<String?>();
      when(() => storage.init()).thenAnswer((_) => storageReady.future);
      when(
        () => storage.getValue('themeData'),
      ).thenAnswer((_) => savedTheme.future);
      final renderedBrightnesses = <Brightness>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) {
              renderedBrightnesses.add(Theme.of(context).brightness);
              return const Scaffold(body: Text('Theme ready'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      final startup = runThemedApp(
        router: router,
        themeManager: ThemeManager(storage: storage),
      );
      await tester.pump();
      final framesBeforeStorage = renderedBrightnesses.toList();

      storageReady.complete();
      await tester.pump();
      final framesBeforePreference = renderedBrightnesses.toList();

      savedTheme.complete(preference.key);
      await startup;
      await tester.pumpAndSettle();

      expect(framesBeforeStorage, isEmpty);
      expect(framesBeforePreference, isEmpty);
      expect(find.text('Theme ready'), findsOneWidget);
      expect(renderedBrightnesses, isNotEmpty);
      expect(renderedBrightnesses, everyElement(preference.value));
    });
  }

  group('startup logo first frame', () {
    late _ControlledLogoBundle bundle;
    late ThemeManager theme;
    late GoRouter router;
    late ByteData logoBytes;

    setUp(() async {
      logoBytes = ByteData.sublistView(
        await File(_logoPath).readAsBytes(),
      );
      final storage = MockStorageService();
      when(() => storage.init()).thenAnswer((_) async {});
      when(() => storage.getValue('themeData')).thenAnswer((_) async => null);
      theme = ThemeManager(storage: storage);
      await theme.initialized;
      router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Text(Theme.of(context).brightness.name),
            ),
          ),
        ],
      );
    });

    tearDown(() {
      router.dispose();
      theme.dispose();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });

    Future<void> mount(WidgetTester tester) async {
      bundle = _ControlledLogoBundle();
      tester.binding.resetFirstFrameSent();
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: bundle,
          child: ChangeNotifierProvider.value(
            value: theme,
            child: RootApp(router: router),
          ),
        ),
      );
    }

    testWidgets('waits for the bundled logo to decode before first frame', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await mount(tester);
        final heldBeforeDecode = !tester.binding.sendFramesToEngine;
        final requestsBeforeObserver = bundle.requestedAssets.toList();
        var heldAtDecodedImage = false;
        final decoded = _decodedLogo(
          bundle,
          onDecoded: () {
            heldAtDecodedImage = !tester.binding.sendFramesToEngine;
          },
        );
        bundle.logo.complete(logoBytes);
        final dimensions = await decoded;
        await tester.pump();

        expect(heldBeforeDecode, isTrue);
        expect(heldAtDecodedImage, isTrue);
        expect(requestsBeforeObserver, [_logoPath]);
        expect(dimensions, (1024, 850));
        expect(tester.binding.sendFramesToEngine, isTrue);
        expect(bundle.requestedAssets, [_logoPath]);
        expect(find.text('light'), findsOneWidget);
      });
    });

    for (final failure in ['load', 'decode']) {
      testWidgets('releases first frame after $failure failure and reports it', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final errors = <FlutterErrorDetails>[];
          final previousErrorHandler = FlutterError.onError;
          FlutterError.onError = errors.add;
          try {
            await mount(tester);
            final heldBeforeFailure = !tester.binding.sendFramesToEngine;
            final decoded = _decodedLogo(bundle);
            final rejected = expectLater(decoded, throwsA(isA<Exception>()));
            await bundle.logoLoadStarted.future;
            if (failure == 'load') {
              bundle.logo.completeError(Exception('synthetic logo load failure'));
            } else {
              bundle.logo.complete(ByteData.sublistView(Uint8List.fromList([0])));
            }
            await rejected;
            await tester.pump();

            expect(heldBeforeFailure, isTrue);
            expect(tester.binding.sendFramesToEngine, isTrue);
            expect(errors, hasLength(1));
            expect(errors.single.library, 'image resource service');
            expect(errors.single.context.toString(), 'image failed to precache');
            expect(find.text('light'), findsOneWidget);
          } finally {
            FlutterError.onError = previousErrorHandler;
          }
        });
      });
    }

    testWidgets('disposal releases pending hold only once despite late decode', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await mount(tester);
        final heldBeforeDisposal = !tester.binding.sendFramesToEngine;
        final decoded = _decodedLogo(bundle);
        await tester.pumpWidget(const SizedBox.shrink());
        final releasedOnDisposal = tester.binding.sendFramesToEngine;

        // A later owner must not lose its hold when this root's decode finishes.
        tester.binding.resetFirstFrameSent();
        tester.binding.deferFirstFrame();
        try {
          bundle.logo.complete(logoBytes);
          await decoded;
          await tester.pump();
          expect(heldBeforeDisposal, isTrue);
          expect(releasedOnDisposal, isTrue);
          expect(tester.binding.sendFramesToEngine, isFalse);
        } finally {
          tester.binding.allowFirstFrame();
        }
      });
    });

    testWidgets('theme rebuild does not acquire another logo hold', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await mount(tester);
        final heldInitially = !tester.binding.sendFramesToEngine;
        theme.themeData = darkMode;
        await tester.pump();
        final decoded = _decodedLogo(bundle);
        bundle.logo.complete(logoBytes);
        await decoded;
        await tester.pump();
        final releasedAfterDecode = tester.binding.sendFramesToEngine;

        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        bundle.logo = Completer<ByteData>();
        tester.binding.resetFirstFrameSent();
        theme.themeData = lightMode;
        await tester.pump();
        final noNewHold = tester.binding.sendFramesToEngine;
        final requestsAfterTheme = bundle.requestedAssets.toList();
        // Finish a request even if a regression mistakenly starts one.
        final cleanupDecode = _decodedLogo(bundle);
        bundle.logo.complete(logoBytes);
        await cleanupDecode;
        await tester.pump();

        expect(heldInitially, isTrue);
        expect(releasedAfterDecode, isTrue);
        expect(noNewHold, isTrue);
        expect(requestsAfterTheme, [_logoPath]);
        expect(find.text('light'), findsOneWidget);
      });
    });
  });
}
