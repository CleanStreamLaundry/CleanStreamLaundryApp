import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:clean_stream_laundry_app/features/widgets/navigation_bar.dart';

void main() {
  Widget wrapWithRouter(
    String initialLocation, {
    double bottomViewPadding = 0,
    ThemeData? theme,
  }) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/homePage',
          builder: (context, state) => Scaffold(
            body: const Text('Home Page'),
            bottomNavigationBar: const NavBar(),
          ),
        ),
        GoRoute(
          path: '/startPage',
          builder: (context, state) => Scaffold(
            body: const Text('Start Page'),
            bottomNavigationBar: const NavBar(),
          ),
        ),
        GoRoute(
          path: '/scanner',
          builder: (context, state) => Scaffold(
            body: const Text('Scanner Page'),
            bottomNavigationBar: const NavBar(),
          ),
        ),
        GoRoute(
          path: '/paymentPage',
          builder: (context, state) => Scaffold(
            body: const Text('Payment Page'),
            bottomNavigationBar: const NavBar(),
          ),
        ),
        GoRoute(
          path: '/loyalty',
          builder: (context, state) => Scaffold(
            body: const Text('Loyalty Page'),
            bottomNavigationBar: const NavBar(),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => Scaffold(
            body: const Text('Settings Page'),
            bottomNavigationBar: const NavBar(),
          ),
        ),
      ],
    );

    return MaterialApp.router(
      theme: theme,
      routerConfig: router,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);

        return MediaQuery(
          data: mediaQuery.copyWith(
            padding: mediaQuery.padding.copyWith(bottom: 0),
            viewPadding: mediaQuery.viewPadding.copyWith(
              bottom: bottomViewPadding,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  group('NavBar Widget Tests', () {
    const routes = ['/homePage', '/startPage', '/loyalty', '/settings'];
    const labels = ['Home', 'Start', 'Wallet', 'Settings'];
    for (final theme in [lightMode, darkMode]) {
      for (var selected = 0; selected < routes.length; selected++) {
        testWidgets('readable ${theme.brightness.name} labels preserve icons '
            'with ${labels[selected]} selected', (tester) async {
          await tester.pumpWidget(
            wrapWithRouter(routes[selected], theme: theme),
          );
          await tester.pumpAndSettle();
          final bar = tester.widget<BottomNavigationBar>(
            find.byType(BottomNavigationBar),
          );
          final surface = bar.backgroundColor!;
          final icons = find.descendant(
            of: find.byType(BottomNavigationBar),
            matching: find.byType(Icon),
          );
          expect(icons, findsNWidgets(4));
          expect(bar.currentIndex, selected);

          for (var index = 0; index < labels.length; index++) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(labels[index]),
            );
            final color = paragraph.text.style!.color!;
            final first = color.computeLuminance() + 0.05;
            final second = surface.computeLuminance() + 0.05;
            final contrast = first > second ? first / second : second / first;
            expect(contrast, greaterThanOrEqualTo(4.5), reason: labels[index]);
            expect(paragraph.text.style!.fontSize, 12);
            if (theme.brightness == Brightness.light) {
              expect(
                color,
                index == selected
                    ? theme.colorScheme.primary
                    : Colors.grey.shade600,
              );
            }
            final iconText = tester.widget<RichText>(
              find.descendant(
                of: icons.at(index),
                matching: find.byType(RichText),
              ),
            );
            expect(
              iconText.text.style!.color,
              index == selected
                  ? theme.colorScheme.primary
                  : Colors.grey.shade600,
            );
          }
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('retained shell keeps navigation and icon behavior in '
          '${theme.brightness.name}', (tester) async {
        final router = GoRouter(
          initialLocation: routes.first,
          routes: [
            ShellRoute(
              builder: (context, state, child) => Scaffold(
                body: child,
                bottomNavigationBar: NavBar(key: state.pageKey),
              ),
              routes: [
                for (final route in routes)
                  GoRoute(path: route, builder: (_, _) => Text(route)),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: theme, routerConfig: router),
        );
        await tester.pumpAndSettle();
        final originalState = tester.state(find.byType(BottomNavigationBar));
        for (final selected in [1, 2, 3, 0]) {
          await tester.tap(find.text(labels[selected]));
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            routes[selected],
          );
          final bar = tester.widget<BottomNavigationBar>(
            find.byType(BottomNavigationBar),
          );
          expect(bar.currentIndex, selected);
          expect(
            tester.state(find.byType(BottomNavigationBar)),
            same(originalState),
          );
          final icons = find.descendant(
            of: find.byType(BottomNavigationBar),
            matching: find.byType(Icon),
          );
          for (var index = 0; index < labels.length; index++) {
            final iconText = tester.widget<RichText>(
              find.descendant(
                of: icons.at(index),
                matching: find.byType(RichText),
              ),
            );
            expect(
              iconText.text.style!.color,
              index == selected
                  ? theme.colorScheme.primary
                  : Colors.grey.shade600,
            );
          }
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('All nav items are visible', (tester) async {
      await tester.pumpWidget(wrapWithRouter('/homePage'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.local_laundry_service_outlined), findsOneWidget);
      expect(
        find.byIcon(Icons.account_balance_wallet_outlined),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Wallet'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('does not overflow with iPhone bottom safe area', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        wrapWithRouter('/homePage', bottomViewPadding: 34),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(tester.getSize(find.byType(NavBar)).height, 90);
    });

    for (final inset in [0.0, 24.0, 48.0]) {
      testWidgets('Android navigation reserves inset $inset exactly once', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          wrapWithRouter('/homePage', bottomViewPadding: inset),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSize(find.byType(NavBar)).height,
          kBottomNavigationBarHeight + inset,
        );
        for (final label in labels) {
          final target = find.ancestor(
            of: find.text(label),
            matching: find.byType(InkResponse),
          );
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
          expect(
            tester.getBottomLeft(target).dy,
            lessThanOrEqualTo(780 - inset),
          );
        }
        await tester.tap(find.text('Wallet'));
        await tester.pumpAndSettle();
        expect(find.text('Loyalty Page'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Tapping Home navigates to /homePage', (tester) async {
      await tester.pumpWidget(wrapWithRouter('/startPage'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.text('Home Page'), findsOneWidget);
    });

    testWidgets('Tapping Start navigates to /startPage', (tester) async {
      await tester.pumpWidget(wrapWithRouter('/homePage'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('Start Page'), findsOneWidget);
    });

    testWidgets('Tapping Wallet navigates to /loyalty', (tester) async {
      await tester.pumpWidget(wrapWithRouter('/homePage'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wallet'));
      await tester.pumpAndSettle();

      expect(find.text('Loyalty Page'), findsOneWidget);
    });

    testWidgets('Tapping Settings navigates to /settings', (tester) async {
      await tester.pumpWidget(wrapWithRouter('/homePage'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings Page'), findsOneWidget);
    });

    testWidgets('CurrentIndex updates based on initial route', (tester) async {
      await tester.pumpWidget(wrapWithRouter('/loyalty'));
      await tester.pumpAndSettle();

      final bottomNav = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bottomNav.currentIndex, 2);
    });

    testWidgets('Scanner route highlights Start tab', (tester) async {
      await tester.pumpWidget(wrapWithRouter('/scanner'));
      await tester.pumpAndSettle();

      final bottomNav = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bottomNav.currentIndex, 1);
    });

    testWidgets('Payment route highlights Start tab', (tester) async {
      await tester.pumpWidget(wrapWithRouter('/paymentPage?machineId=abc'));
      await tester.pumpAndSettle();

      final bottomNav = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bottomNav.currentIndex, 1);
    });
  });
}
