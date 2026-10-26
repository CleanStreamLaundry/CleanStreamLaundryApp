import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Some production styles intentionally rely on the platform's default font.
// In widget tests that fallback is Ahem, even after ThemeData loads Roboto.
// Substitute only missing/Ahem families on the actual rendered text tree.
Future<void> applyRealFontFallback(WidgetTester tester) async {
  InlineSpan replace(InlineSpan span) {
    if (span is! TextSpan) return span;
    final style = span.style ?? const TextStyle();
    return TextSpan(
      text: span.text,
      style:
          style.fontFamily == null ||
              style.fontFamily == 'Ahem' ||
              style.fontFamily == 'monospace'
          ? style.copyWith(fontFamily: 'Roboto')
          : style,
      children: span.children?.map(replace).toList(),
      recognizer: span.recognizer,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }

  for (final element in find.byType(RichText, skipOffstage: false).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    paragraph.text = replace(paragraph.text);
  }
  await tester.pump();
}
