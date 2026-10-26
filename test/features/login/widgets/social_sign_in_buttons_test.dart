import 'dart:convert';
import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/features/login/controller.dart';
import 'package:clean_stream_laundry_app/features/login/widgets/social_sign_in_buttons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockAuthService mockAuthService;
  late LoginController mockController;

  setUpAll(() async {
    final loader = FontLoader('Google Sans')
      ..addFont(
        rootBundle.load('assets/fonts/google_sans/GoogleSans-Medium.ttf'),
      );
    await loader.load();
  });

  test('bundles the official Google mark, Medium font, and license', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    expect(
      manifest.where((entry) => entry['family'] == 'Google Sans'),
      [
        {
          'family': 'Google Sans',
          'fonts': [
            {
              'asset': 'assets/fonts/google_sans/GoogleSans-Medium.ttf',
              'weight': 500,
            },
          ],
        },
      ],
    );
    final font =
        await rootBundle.load('assets/fonts/google_sans/GoogleSans-Medium.ttf');
    expect(font.lengthInBytes, 2002260);
    final license =
        await rootBundle.loadString('assets/fonts/google_sans/OFL.txt');
    expect(
      license,
      contains(
        'Copyright 2025 The Google Sans Project Authors '
        '(github.com/googlefonts/googlesans)',
      ),
    );
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));

    final mark = await rootBundle.load('assets/Google.png');
    final codec = await ui.instantiateImageCodec(mark.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 200);
    expect(frame.image.height, 204);
    frame.image.dispose();
    codec.dispose();
  });

  setUp(() {
    mockAuthService = MockAuthService();
    mockController = LoginController(authService: mockAuthService);
    addTearDown(() {
      mockController.disposeController();
      mockController.dispose();
    });

    // Stub async methods
    when(() => mockAuthService.googleSignIn())
        .thenAnswer((_) async => false);
    when(() => mockAuthService.appleSignIn())
        .thenAnswer((_) async => false);
  });

  Widget createWidgetUnderTest({
    Brightness brightness = Brightness.light,
    double textScale = 1,
    double? width,
  }) {
    return MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SizedBox(
            width: width,
            child: SocialSignInButtons(controller: mockController),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'renders both social sign-in buttons on iOS and macOS',
    (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Sign in with Apple'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'renders Google but not Apple sign-in on Android',
    (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Sign in with Apple'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('tapping Google button calls googleSignIn',
          (WidgetTester tester) async {
        await tester.pumpWidget(createWidgetUnderTest());

        await tester.tap(find.text('Sign in with Google'));
        await tester.pump();

        verify(() => mockAuthService.googleSignIn()).called(1);
      });

  testWidgets(
    'tapping Apple button calls appleSignIn on iOS and macOS',
    (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Sign in with Apple'));
      await tester.pump();

      verify(() => mockAuthService.appleSignIn()).called(1);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('google logo is displayed',
          (WidgetTester tester) async {
        await tester.pumpWidget(createWidgetUnderTest());

        expect(find.byKey(const Key('google_logo')), findsOneWidget);
      });

  for (final brightness in Brightness.values) {
    testWidgets('Google colors and typography in ${brightness.name} mode',
        (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(brightness: brightness, width: 280),
      );

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Sign in with Google'),
      );
      final style = button.style!;
      final isDark = brightness == Brightness.dark;
      expect(style.backgroundColor!.resolve({}),
          isDark ? const Color(0xFF131314) : Colors.white);
      expect(style.foregroundColor!.resolve({}),
          isDark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F));
      expect(
        style.side!.resolve({}),
        BorderSide(
          color: isDark ? const Color(0xFF8E918F) : const Color(0xFF747775),
        ),
      );
      expect(style.elevation!.resolve({}), 0);
      expect(style.surfaceTintColor!.resolve({}), Colors.transparent);

      final label = tester.widget<RichText>(
        find.descendant(
          of: find.text('Sign in with Google'),
          matching: find.byType(RichText),
        ),
      );
      expect(label.text.style!.fontSize, 14);
      expect(label.text.style!.fontFamily, 'Google Sans');
      expect(label.text.style!.height, 20 / 14);
      expect(label.text.style!.fontWeight, FontWeight.w500);
      expect(label.text.style!.letterSpacing, 0);

      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(tester.getSemantics(find.text('Sign in with Google')).label,
            'Sign in with Google');
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        semantics.dispose();
      }
    }, variant: TargetPlatformVariant.all());
  }

  testWidgets(
    'Google mark stays unchanged with platform-specific spacing',
    (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      final logoFinder = find.byKey(const Key('google_logo'));
      final logo = tester.widget<Image>(logoFinder);
      expect((logo.image as AssetImage).assetName, 'assets/Google.png');
      expect(logo.color, isNull);
      expect(logo.fit, BoxFit.contain);
      expect(logo.excludeFromSemantics, isTrue);
      expect(tester.getSize(logoFinder), const Size(20, 20));

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Sign in with Google'),
      );
      final isIOS = !kIsWeb &&
          Theme.of(tester.element(logoFinder)).platform == TargetPlatform.iOS;
      final padding = button.style!.padding!.resolve({})! as EdgeInsets;
      expect(padding.left, isIOS ? 16 : 12);
      expect(padding.right, isIOS ? 16 : 12);
      expect(
        tester.getTopLeft(find.text('Sign in with Google')).dx -
            tester.getTopRight(logoFinder).dx,
        isIOS ? 12 : 10,
      );
    },
    variant: TargetPlatformVariant.all(),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
        'Google remains readable and tappable with large text in ${brightness.name} mode',
        (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(
          width: 280,
          textScale: 2,
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final button = find.widgetWithText(ElevatedButton, 'Sign in with Google');
      final buttonRect = tester.getRect(button);
      final labelRect = tester.getRect(find.text('Sign in with Google'));
      expect(buttonRect.height, greaterThanOrEqualTo(48));
      expect(buttonRect.contains(labelRect.topLeft), isTrue);
      expect(buttonRect.contains(labelRect.bottomRight), isTrue);
      expect(tester.getSize(find.byKey(const Key('google_logo'))),
          const Size(20, 20));

      await tester.tap(button);
      verify(() => mockAuthService.googleSignIn()).called(1);
    });
  }

  testWidgets('Google exposes a labeled button and supports keyboard activation',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(createWidgetUnderTest());

      expect(
        tester.getSemantics(find.text('Sign in with Google')),
        matchesSemantics(
          label: 'Sign in with Google',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      verify(() => mockAuthService.googleSignIn()).called(1);
    } finally {
      semantics.dispose();
    }
  });
}
