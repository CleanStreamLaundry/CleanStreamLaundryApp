import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_launcher_icons/config/config.dart';
import 'package:flutter_native_splash/cli_commands.dart' as splash;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android and iOS launcher configurations reference existing artwork',
    () {
      final config = Config.loadConfigFromPubSpec('.')!;

      expect(config.android, isTrue);
      expect(config.ios, isTrue);
      for (final path in [
        config.getImagePathAndroid(),
        config.getImagePathIOS(),
      ]) {
        expect(path, isNotNull);
        expect(
          File(path!).existsSync(),
          isTrue,
          reason: 'Missing artwork: $path',
        );
      }
    },
  );

  test('native splash configurations reference existing artwork', () {
    final config = splash.getConfig(configFile: 'pubspec.yaml', flavor: null);

    expect(config['android'], isTrue);
    expect(
      config['ios'],
      isFalse,
      reason: 'Preserve the reviewed named-color iOS launch storyboard',
    );
    for (final path in [
      config['image'] as String,
      (config['android_12'] as Map<String, dynamic>)['image'] as String,
    ]) {
      expect(File(path).existsSync(), isTrue, reason: 'Missing artwork: $path');
    }

    final storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    expect(storyboard, contains('image="LaunchImage"'));
    expect(
      storyboard,
      contains('<color key="backgroundColor" name="LaunchSurface"/>'),
    );
    const imageSet = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
    final images =
        jsonDecode(File('$imageSet/Contents.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(images['images'], hasLength(3));
    for (final image in images['images'] as List<dynamic>) {
      final path = '$imageSet/${image['filename']}';
      expect(File(path).existsSync(), isTrue, reason: 'Missing artwork: $path');
    }
    expect(
      File(
        'ios/Runner/Assets.xcassets/LaunchSurface.colorset/Contents.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('Android night splash background pixels are opaque dark gray', () async {
    for (final qualifier in ['drawable-night', 'drawable-night-v21']) {
      final file = File('android/app/src/main/res/$qualifier/background.png');
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(data, isNotNull);
          final pixels = data!.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          expect(pixels, isNotEmpty);
          for (var i = 0; i < pixels.length; i += 4) {
            expect(pixels.sublist(i, i + 4), [0x21, 0x21, 0x21, 0xff]);
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
  });

  test(
    'Android native theme reuses the Flutter preference without a global change',
    () {
      final activity = File(
        'android/app/src/main/kotlin/com/cleanstreamlaundrysolutions/'
        'clean_stream_laundry_app/MainActivity.kt',
      ).readAsStringSync();
      expect(activity, contains('FlutterFragmentActivity()'));
      expect(
        activity,
        contains(
          'getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)',
        ),
      );
      expect(
        activity,
        contains('getString("flutter.themeData", null) == "darkMode"'),
      );
      expect(
        activity,
        contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.S'),
      );
      expect(activity, contains('manager.setApplicationNightMode(mode)'));
      expect(activity, isNot(contains('.setNightMode(')));
      expect(activity, isNot(contains('recreate()')));
    },
  );

  test('Android keeps the native theme listener scoped to the activity', () {
    final activity = File(
      'android/app/src/main/kotlin/com/cleanstreamlaundrysolutions/'
      'clean_stream_laundry_app/MainActivity.kt',
    ).readAsStringSync();
    final create = RegExp(
      r'override fun onCreate\b[\s\S]*?\n    }',
    ).firstMatch(activity);
    final destroy = RegExp(
      r'override fun onDestroy\b[\s\S]*?\n    }',
    ).firstMatch(activity);
    expect(create, isNotNull);
    expect(destroy, isNotNull);
    final body = create!.group(0)!;
    expect(activity, contains('private val themeListener'));
    expect(activity, contains('key == "flutter.themeData" || key == null'));
    expect(
      body,
      contains(
        'themePreferences.registerOnSharedPreferenceChangeListener(themeListener)',
      ),
    );
    expect(
      destroy!.group(0),
      contains(
        'themePreferences.unregisterOnSharedPreferenceChangeListener(themeListener)',
      ),
    );
    expect(body.indexOf('syncNativeTheme()'), greaterThanOrEqualTo(0));
    expect(
      body.indexOf('super.onCreate(savedInstanceState)'),
      greaterThanOrEqualTo(0),
    );
    expect(
      body.indexOf('syncNativeTheme()'),
      lessThan(body.indexOf('super.onCreate(savedInstanceState)')),
    );
  });

  test('web app metadata uses the customer-facing name', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final index = File('web/index.html').readAsStringSync();

    expect(manifest['name'], 'Clean Stream Laundry');
    expect(manifest['short_name'], 'Clean Stream');
    expect(index, contains('<title>Clean Stream Laundry</title>'));
    expect(
      index,
      contains(
        'name="apple-mobile-web-app-title" content="Clean Stream Laundry"',
      ),
    );
    expect(index, isNot(contains('clean_stream_laundry_app')));
  });

  test('web manifest icon dimensions match the existing artwork', () async {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;

    for (final icon in manifest['icons'] as List<dynamic>) {
      final file = File('web/${icon['src']}');
      expect(file.existsSync(), isTrue, reason: 'Missing icon: ${file.path}');
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      try {
        final frame = await codec.getNextFrame();
        try {
          expect(icon['sizes'], '${frame.image.width}x${frame.image.height}');
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
  });

  test('web touch icon and favicon references resolve', () {
    final index = File('web/index.html').readAsStringSync();
    for (final relation in ['apple-touch-icon', 'icon']) {
      final link = RegExp(
        '<link rel="$relation"[^>]*href="([^"]+)"',
      ).firstMatch(index);
      expect(link, isNotNull, reason: 'Missing $relation link');
      expect(File('web/${link!.group(1)}').existsSync(), isTrue);
    }
  });
}
