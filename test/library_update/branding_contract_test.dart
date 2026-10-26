import 'dart:typed_data';

import 'package:flutter_launcher_icons/config/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../scripts/branding/check.dart' as branding;

void main() {
  test('image ICC compression round-trips through archive zlib in memory', () {
    final bytes = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));
    final profile = img.IccProfile(
      'synthetic',
      img.IccProfileCompression.none,
      Uint8List.fromList(bytes),
    );
    expect(profile.compressed(), isNotEmpty);
    expect(profile.compression, img.IccProfileCompression.deflate);
    expect(profile.decompressed(), orderedEquals(bytes));
    expect(profile.compression, img.IccProfileCompression.none);
  });

  test('existing launcher config and reviewed masks remain valid', () {
    final config = Config.loadConfigFromPubSpec('.')!;
    expect(config.android, isTrue);
    expect(config.ios, isTrue);
    expect(config.getImagePathAndroid(), 'scripts/branding/launcher.png');
    expect(config.getImagePathIOS(), 'scripts/branding/launcher.png');
    expect(config.removeAlphaIOS, isTrue);
    branding.checkSquare(
      'scripts/branding/launcher.png',
      1024,
      opaque: true,
      radius: 409.6,
    );
    branding.checkSquare(
      'scripts/branding/android12.png',
      1152,
      opaque: false,
      radius: 384,
    );
  });

  test('prepare script image operations retain channels in memory', () {
    final source = img.Image(width: 4, height: 4, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(20, 80, 140, 255));
    final resized = img.copyResize(
      source,
      width: 2,
      height: 2,
      interpolation: img.Interpolation.average,
    );
    for (final channels in [3, 4]) {
      final canvas = img.Image(width: 4, height: 4, numChannels: channels);
      img.fill(
        canvas,
        color: img.ColorRgba8(255, 255, 255, channels == 3 ? 255 : 0),
      );
      img.compositeImage(canvas, resized, dstX: 1, dstY: 1);
      final decoded = img.decodePng(img.encodePng(canvas))!;
      expect(decoded.width, 4);
      expect(decoded.height, 4);
      expect(decoded.hasAlpha, channels == 4);
      expect(decoded.getPixel(0, 0).a, channels == 3 ? 255 : 0);
      final center = decoded.getPixel(1, 1);
      expect([center.r, center.g, center.b, center.a], [20, 80, 140, 255]);
    }
  });
}
