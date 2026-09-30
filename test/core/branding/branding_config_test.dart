import 'dart:io';

import 'package:flutter_launcher_icons/config/config.dart';
import 'package:flutter_native_splash/cli_commands.dart' as splash;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android and iOS launcher configurations reference existing artwork', () {
    final config = Config.loadConfigFromPubSpec('.')!;

    expect(config.android, isTrue);
    expect(config.ios, isTrue);
    for (final path in [config.getImagePathAndroid(), config.getImagePathIOS()]) {
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue, reason: 'Missing artwork: $path');
    }
  });

  test('native splash configurations reference existing artwork', () {
    final config = splash.getConfig(configFile: 'pubspec.yaml', flavor: null);

    expect(config['android'], isTrue);
    expect(config['ios'], isTrue);
    for (final path in [
      config['image'] as String,
      (config['android_12'] as Map<String, dynamic>)['image'] as String,
    ]) {
      expect(File(path).existsSync(), isTrue, reason: 'Missing artwork: $path');
    }
  });
}
