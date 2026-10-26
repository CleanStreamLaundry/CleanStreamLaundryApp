import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// Run with the app's existing package config; no separate dependency tree.
void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('Expected app source root and candidate output root');
  }
  final source = img.decodePng(File('${args[0]}/assets/Icon.png').readAsBytesSync())!;
  final output = Directory('${args[1]}/scripts/branding')..createSync(recursive: true);
  for (final spec in [
    (name: 'launcher', size: 1024, diameter: 816, opaque: true),
    (name: 'android12', size: 1152, diameter: 764, opaque: false),
  ]) {
    // Fit the entire source rectangle inside the safe circle, without cropping.
    final scale = spec.diameter / math.sqrt(source.width * source.width + source.height * source.height);
    final resized = img.copyResize(source,
        width: (source.width * scale).floor(),
        height: (source.height * scale).floor(),
        interpolation: img.Interpolation.average);
    final canvas = img.Image(width: spec.size, height: spec.size, numChannels: spec.opaque ? 3 : 4);
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, spec.opaque ? 255 : 0));
    img.compositeImage(canvas, resized,
        dstX: (spec.size - resized.width) ~/ 2,
        dstY: (spec.size - resized.height) ~/ 2);
    File('${output.path}/${spec.name}.png').writeAsBytesSync(img.encodePng(canvas));
    stdout.writeln('${spec.name}: ${spec.size}x${spec.size}; artwork ${resized.width}x${resized.height}');
  }
}
