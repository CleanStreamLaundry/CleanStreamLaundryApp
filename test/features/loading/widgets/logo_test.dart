import 'package:clean_stream_laundry_app/features/loading/widgets/logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildLogo() {
  return const MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: Logo()),
    ),
  );
}

void main() {
  group('Logo', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(_buildLogo());
      expect(tester.takeException(), isNull);
    });

    testWidgets('contains a TweenAnimationBuilder wrapping a Transform.scale',
            (tester) async {
          await tester.pumpWidget(_buildLogo());

          expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
          expect(find.byType(Transform), findsAtLeastNWidgets(1));
        });

    testWidgets('renders an Image widgets for the logo asset', (tester) async {
      await tester.pumpWidget(_buildLogo());

      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, 'assets/splash-logo.png');
      expect(image.height, 250);
    });

    testWidgets('scale swaps begin/end after animation completes', (tester) async {
      await tester.pumpWidget(_buildLogo());

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
    });

    testWidgets('does not throw after multiple pump cycles', (tester) async {
      await tester.pumpWidget(_buildLogo());

      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      expect(tester.takeException(), isNull);
    });
  });
}
