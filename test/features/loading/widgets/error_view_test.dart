import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/loading/widgets/error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _buildErrorView(
  String error, {
  List<RouteBase>? extraRoutes,
  ThemeData? theme,
}) {
  final router = GoRouter(
    initialLocation: '/test',
    routes: [
      GoRoute(
        path: '/test',
        builder: (_, __) => Scaffold(body: ErrorView(error: error)),
      ),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold(key: Key('login'))),
      ...?extraRoutes,
    ],
  );
  return MaterialApp.router(theme: theme, routerConfig: router);
}

void main() {
  for (final theme in [lightMode, darkMode]) {
    testWidgets(
      '${theme.brightness.name} error text and return action are readable',
      (tester) async {
        const message = 'Your sign-in changed. Please return to Login.';
        await tester.pumpWidget(_buildErrorView(message, theme: theme));
        await tester.pumpAndSettle();
        final button = find.ancestor(
          of: find.text('Return to Login'),
          matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
        );
        final buttonFill = tester
            .widget<Material>(
              find.descendant(of: button, matching: find.byType(Material)),
            )
            .color!;
        final scheme = theme.colorScheme;
        for (final label in [
          'Authentication Failed',
          message,
          'Return to Login',
        ]) {
          final style = tester
              .renderObject<RenderParagraph>(
                find.descendant(
                  of: find.text(label),
                  matching: find.byType(RichText),
                ),
              )
              .text
              .style!;
          final isAction = label == 'Return to Login';
          final background = isAction ? buttonFill : scheme.surface;
          final a = Color.alphaBlend(
            style.color!,
            background,
          ).computeLuminance();
          final b = background.computeLuminance();
          expect(
            a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            style.color,
            isAction && theme.brightness == Brightness.light
                ? scheme.primary
                : scheme.onSurface,
          );
          expect(style.fontFamily, isNot('monospace'));
          expect(style.decoration, TextDecoration.none);
        }
        expect(buttonFill, scheme.surface);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
          Colors.redAccent,
        );
        expect(
          tester.widget<ElevatedButton>(button).style!.padding!.resolve({}),
          const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('login')), findsOneWidget);
      },
    );
  }

  group('ErrorView', () {
    testWidgets('renders the error icon', (tester) async {
      await tester.pumpWidget(_buildErrorView('Some error'));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('renders the "Authentication Failed" heading', (tester) async {
      await tester.pumpWidget(_buildErrorView('Some error'));

      expect(find.text('Authentication Failed'), findsOneWidget);
    });

    testWidgets('renders the supplied error message', (tester) async {
      const message = 'Network timeout occurred';
      await tester.pumpWidget(_buildErrorView(message));

      expect(find.text(message), findsOneWidget);
    });

    testWidgets('renders the "Return to Login" button', (tester) async {
      await tester.pumpWidget(_buildErrorView('err'));

      expect(find.text('Return to Login'), findsOneWidget);
      expect(find.byIcon(Icons.login), findsOneWidget);
    });

    testWidgets('tapping the button navigates to /login', (tester) async {
      await tester.pumpWidget(_buildErrorView('err'));

      await tester.tap(find.text('Return to Login'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login')), findsOneWidget);
    });

    testWidgets('renders different error messages correctly', (tester) async {
      const message = 'Exception: Invalid credentials';
      await tester.pumpWidget(_buildErrorView(message));

      expect(find.text(message), findsOneWidget);
    });

    testWidgets('long error messages do not overflow', (tester) async {
      final longError = 'E' * 300;
      await tester.pumpWidget(_buildErrorView(longError));

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
