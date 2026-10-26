import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:image/image.dart' as img;
import 'package:yaml/yaml.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

img.Image readImage(String path) => img.decodePng(File(path).readAsBytesSync())!;

void checkSquare(String path, int size, {required bool opaque, double? radius}) {
  final image = readImage(path);
  require(image.width == size && image.height == size, '$path dimensions');
  require(image.hasAlpha != opaque, '$path alpha channel');
  if (radius == null) return;
  var artworkPixels = 0;
  for (final pixel in image) {
    final artwork = opaque
        ? pixel.r != 255 || pixel.g != 255 || pixel.b != 255
        : pixel.a != 0;
    if (!artwork) continue;
    artworkPixels++;
    final dx = pixel.x + 0.5 - size / 2;
    final dy = pixel.y + 0.5 - size / 2;
    require(dx * dx + dy * dy <= radius * radius, '$path artwork outside safe circle');
  }
  require(artworkPixels > size * size / 20, '$path blank or undersized');
}

void main(List<String> args) {
  require(args.length == 2 || args.length == 3,
      'Expected source app, candidate root, and optional generated app root');
  final source = args[0];
  final candidate = args[1];
  final icon = readImage('$source/assets/Icon.png');
  final logo = readImage('$source/assets/Logo.png');
  require(icon.width == 3454 && icon.height == 2758, 'Approved Icon dimensions changed');
  require(logo.width == 6300 && logo.height == 5232, 'Approved Logo dimensions changed');
  final original = jsonDecode(jsonEncode(loadYaml(File('$source/pubspec.yaml').readAsStringSync()))) as Map;
  final updated = jsonDecode(jsonEncode(loadYaml(File('$candidate/pubspec.yaml').readAsStringSync()))) as Map;
  final expected = jsonDecode(jsonEncode(original)) as Map;
  (expected['flutter_icons'] as Map<String, dynamic>).addAll({
    'image_path': 'scripts/branding/launcher.png',
    'remove_alpha_ios': true,
    'web': {'generate': true},
  });
  final splash = expected['flutter_native_splash'] as Map;
  splash['color_dark_web'] = '#212121';
  splash['ios'] = false;
  (splash['android_12'] as Map)['image'] = 'scripts/branding/android12.png';
  require(const DeepCollectionEquality().equals(expected, updated), 'Unexpected pubspec changes');
  checkSquare('$candidate/scripts/branding/launcher.png', 1024, opaque: true, radius: 409.6);
  checkSquare('$candidate/scripts/branding/android12.png', 1152, opaque: false, radius: 384);
  stdout.writeln('PASS: source dimensions, scoped config, opaque launcher mask, Android12 alpha/mask');

  if (args.length == 3) {
    final root = args[2];
    checkSquare('$root/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png', 1024, opaque: true);
    const densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    for (final entry in densities.entries) {
      checkSquare('$root/android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png', entry.value, opaque: true);
      for (final night in ['', '-night']) {
        checkSquare('$root/android/app/src/main/res/drawable$night-${entry.key}/android12splash.png', entry.value * 6, opaque: false, radius: entry.value * 2);
      }
    }
    final manifest = jsonDecode(File('$root/web/manifest.json').readAsStringSync()) as Map;
    for (final entry in manifest['icons'] as List) {
      final size = int.parse((entry['sizes'] as String).split('x').first);
      require(size == 192 || size == 512, 'Unexpected web icon size');
      checkSquare('$root/web/${entry['src']}', size, opaque: true, radius: size * 0.4);
    }
    final index = File('$root/web/index.html').readAsStringSync();
    require(index.contains('href="icons/Icon-192.png"') && index.contains('href="favicon.png"'), 'Web head still references old icons');
    require(index.contains('#212121'), 'Missing web dark splash background');
    final project = File('$root/ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    require(project.contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;') &&
        project.contains('PRODUCT_BUNDLE_IDENTIFIER = com.cleanstreamlaundrysolutions.clenaStreamLaundryApp;'), 'iOS floor/identity changed');
    for (final file in [
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
      'ios/Runner/Assets.xcassets/LaunchSurface.colorset/Contents.json',
      'ios/Runner.xcodeproj/project.pbxproj',
      'ios/Podfile',
      'android/app/build.gradle.kts',
    ]) {
      require(File('$source/$file').readAsStringSync() == File('$root/$file').readAsStringSync(), '$file changed');
    }
    stdout.writeln('PASS: generated launcher/splash/web dimensions and masks, web references/dark surface, preserved native config');
  }
}
