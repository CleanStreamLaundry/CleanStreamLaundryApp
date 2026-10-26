import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/widgets/custom_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  test('Home dark surfaces keep text and status labels readable', () {
    final colors = darkMode.colorScheme;
    for (final text in [
      colors.homeAccent,
      colors.fontInverted,
      colors.fontSecondary,
      Colors.green.shade300,
      Colors.red.shade300,
    ]) {
      expect(contrast(text, colors.homeCard), greaterThanOrEqualTo(4.5));
    }
    expect(
      contrast(colors.homeAccent, colors.surface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('Home light colors and other tabs keep their existing values', () {
    final light = lightMode.colorScheme;
    final dark = darkMode.colorScheme;
    expect(light.homeCard, light.cardPrimary);
    expect(light.homeAccent, light.primary);
    expect(light.homeGradient, light.primaryGradient);
    expect(dark.cardPrimary, const Color(0xFFCFCFCD));
    expect(dark.primaryGradient.colors.last, Colors.deepPurple);
    expect(dark.homeGradient.colors.last, const Color(0xFF145678));
  });

  testWidgets('Header gradient override stays opt-in', (tester) async {
    final colors = darkMode.colorScheme;
    for (final gradient in [null, colors.homeGradient]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: darkMode,
          home: Scaffold(appBar: CustomAppBar(gradient: gradient)),
        ),
      );
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      final background = appBar.flexibleSpace! as Container;
      expect(
        (background.decoration! as BoxDecoration).gradient,
        gradient ?? colors.primaryGradient,
      );
    }
  });
}
