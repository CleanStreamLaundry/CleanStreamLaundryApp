import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/widgets/custom_app_bar.dart';
import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  group("Custom App Bar Tests", () {
    for (final isDark in [false, true]) {
      for (final width in [320.0, 800.0]) {
        testWidgets(
          'action contrast in ${isDark ? "dark" : "light"} mode at $width',
          (tester) async {
            tester.view.physicalSize = Size(width, 600);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              MaterialApp(
                theme: isDark ? darkMode : lightMode,
                home: const Scaffold(appBar: CustomAppBar()),
              ),
            );

            for (final entry in {
              'Notifications': Icons.notifications_none_rounded,
              'Settings': Icons.settings_outlined,
            }.entries) {
              final icon = find.byIcon(entry.value);
              expect(
                IconTheme.of(tester.element(icon)).color,
                isDark ? Colors.white : Colors.black,
              );
              expect(find.byTooltip(entry.key), findsOneWidget);
              final button = find.ancestor(
                of: icon,
                matching: find.byType(IconButton),
              );
              final semantics = tester.getSemantics(button).getSemanticsData();
              expect(semantics.tooltip, entry.key);
              expect(semantics.flagsCollection.isButton, isTrue);
              expect(semantics.hasAction(SemanticsAction.tap), isTrue);
              expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
              expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
            }
            expect(tester.getSize(find.byType(AppBar)).height, 60);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    test('CustomAppBar instantiates correctly', () {
      const customAppBar = CustomAppBar();
      expect(customAppBar, isA<CustomAppBar>());
    });

    test('CustomAppBar implements PreferredSizeWidget', () {
      const customAppBar = CustomAppBar();
      expect(customAppBar, isA<PreferredSizeWidget>());
    });

    testWidgets('CustomAppBar builds an AppBar widgets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(appBar: const CustomAppBar())),
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('CustomAppBar uses theme primary background', (tester) async {
      const testColor = Color(0xFF2073A9);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.light(primary: testColor),
          ),
          home: Scaffold(appBar: const CustomAppBar()),
        ),
      );

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, testColor);
    });

    testWidgets('CustomAppBar renders correctly inside Scaffold', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: const CustomAppBar(),
            body: const Text('Testing'),
          ),
        ),
      );

      expect(find.text('Testing'), findsOneWidget);
    });

    testWidgets('settings icon navigates to settings route', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(appBar: CustomAppBar()),
              ),
              GoRoute(
                path: '/settings',
                builder: (_, _) => const Scaffold(body: Text('Settings Page')),
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('settings-button')));
      await tester.pumpAndSettle();

      expect(find.text('Settings Page'), findsOneWidget);
    });

    testWidgets('notification bell opens no notifications sheet', (
      tester,
    ) async {
      final notificationService = MockNotificationService();
      when(
        () => notificationService.getPendingNotifications(),
      ).thenAnswer((_) async => const []);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: CustomAppBar(notificationService: notificationService),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('notifications-button')));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('No notifications'), findsOneWidget);
    });

    testWidgets('deferred notification failure shows the empty state safely', (
      tester,
    ) async {
      final notificationService = MockNotificationService();
      final pendingNotifications = Completer<List<AppNotification>>();
      when(
        () => notificationService.getPendingNotifications(),
      ).thenAnswer((_) => pendingNotifications.future);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: CustomAppBar(notificationService: notificationService),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('notifications-button')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No notifications'), findsNothing);

      pendingNotifications.completeError(
        StateError('Notification lookup failed'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('No notifications'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('notification bell shows pending notifications', (
      tester,
    ) async {
      final notificationService = MockNotificationService();
      when(() => notificationService.getPendingNotifications()).thenAnswer(
        (_) async => const [
          AppNotification(
            id: 1,
            title: 'Machine Almost Ready',
            body: 'Dryer 12 will be finished in 5 minutes!',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: CustomAppBar(notificationService: notificationService),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('notifications-button')));
      await tester.pumpAndSettle();

      expect(find.text('Machine Almost Ready'), findsOneWidget);
      expect(
        find.text('Dryer 12 will be finished in 5 minutes!'),
        findsOneWidget,
      );
    });
  });
}
