import 'dart:async';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/settings/settings.dart';
import 'package:clean_stream_laundry_app/features/release_controls/firebase_settings.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clean_stream_laundry_app/features/settings/widgets/notification_lead.dart';
import 'package:clean_stream_laundry_app/features/settings/widgets/settings_card.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'mocks.dart';
import '../../services/firebase/firebase_service_test.dart' show Driver, Tokens;

void main() {
  late MockAuthService mockAuthService;
  late MockTransactionService mockTransactionService;
  late MockProfileService mockProfileService;
  late MockThemeManager mockThemeManager;
  late GoRouter router;

  setUp(() async {
    mockAuthService = MockAuthService();
    mockTransactionService = MockTransactionService();
    mockThemeManager = MockThemeManager();
    mockProfileService = MockProfileService();

    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<ProfileService>(mockProfileService);
    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
    GetIt.instance.registerSingleton<TransactionService>(
      mockTransactionService,
    );

    when(
      () => mockProfileService.getNotificationLeadTime(),
    ).thenAnswer((_) async => 5);
    when(
      () => mockProfileService.getCurrentUserRole(),
    ).thenAnswer((_) async => null);
    when(
      () => mockProfileService.setNotificationLeadTime(any()),
    ).thenAnswer((_) async {});

    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Settings()),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Login Page')),
        ),
        GoRoute(
          path: '/editProfile',
          builder: (_, _) => const Scaffold(body: Text('Edit Profile Page')),
        ),
        GoRoute(
          path: '/monthlyTransactionHistory',
          builder: (_, _) => const Scaffold(body: Text('Monthly Report Page')),
        ),
        GoRoute(
          path: '/refundPage',
          builder: (_, _) => const Scaffold(body: Text('Refund Page')),
        ),
        GoRoute(
          path: '/maintenancePage',
          builder: (_, _) => const Scaffold(body: Text('Maintenance Page')),
        ),
      ],
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Widget createWidget({ThemeData? theme, double textScale = 1}) {
    return ChangeNotifierProvider<ThemeManager>.value(
      value: mockThemeManager,
      child: MaterialApp.router(
        theme: theme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
  }

  double contrast(Color foreground, Color background) {
    final text = Color.alphaBlend(foreground, background).computeLuminance();
    final surface = background.computeLuminance();
    return text > surface
        ? (text + 0.05) / (surface + 0.05)
        : (surface + 0.05) / (text + 0.05);
  }

  Color renderedColor(Finder finder, WidgetTester tester) {
    final richText = find.descendant(
      of: finder,
      matching: find.byType(RichText),
    );
    return tester.renderObject<RenderParagraph>(richText).text.style!.color!;
  }

  for (final theme in [lightMode, darkMode]) {
    final mode = theme.brightness.name;
    testWidgets(
      '$mode sign-out actions have readable text and cancel is inert',
      (tester) async {
        await tester.pumpWidget(createWidget(theme: theme));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(SettingsCard, 'Sign Out'),
        );
        await tester.tap(find.widgetWithText(SettingsCard, 'Sign Out'));
        await tester.pumpAndSettle();

        final dialog = find.byType(AlertDialog);
        final surface = tester
            .widget<Material>(
              find
                  .descendant(of: dialog, matching: find.byType(Material))
                  .first,
            )
            .color!;
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        expect(
          contrast(renderedColor(cancel, tester), surface),
          greaterThanOrEqualTo(4.5),
        );
        final confirm = find.widgetWithText(ElevatedButton, 'Sign Out');
        final buttonSurface = tester
            .widget<Material>(
              find.descendant(of: confirm, matching: find.byType(Material)),
            )
            .color!;
        expect(
          contrast(renderedColor(confirm, tester), buttonSurface),
          greaterThanOrEqualTo(4.5),
        );

        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        verifyNever(() => mockAuthService.logout());
        expect(router.routerDelegate.currentConfiguration.uri.path, '/');
      },
    );

    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$mode $width ${scale}x notification labels and stepper remain usable',
          (tester) async {
            tester.view.physicalSize = Size(width, 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final pending = Completer<int>();
            when(
              () => mockProfileService.getNotificationLeadTime(),
            ).thenAnswer((_) => pending.future);
            await tester.pumpWidget(
              createWidget(theme: theme, textScale: scale),
            );
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(find.byType(NotificationLead), findsNothing);

            void expectCompleteLabels() {
              for (final label in [
                'Notify Before Finish',
                "Minutes you're notified before machine finish",
              ]) {
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.text(label),
                );
                expect(paragraph.didExceedMaxLines, isFalse, reason: label);
              }
              expect(tester.takeException(), isNull);
            }

            expectCompleteLabels();
            final loadingTitle = tester.getRect(
              find.text('Notify Before Finish'),
            );
            pending.complete(5);
            await tester.pumpAndSettle();
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(
              tester.getRect(find.text('Notify Before Finish')),
              loadingTitle,
            );
            expectCompleteLabels();
            await tester.ensureVisible(find.byIcon(Icons.add));
            await tester.tap(find.byIcon(Icons.add));
            await tester.pumpAndSettle();
            expect(find.text('6'), findsOneWidget);
            verify(
              () => mockProfileService.setNotificationLeadTime(6),
            ).called(1);
            await tester.tap(find.byIcon(Icons.remove));
            await tester.pumpAndSettle();
            expect(find.text('5'), findsOneWidget);
            verify(
              () => mockProfileService.setNotificationLeadTime(5),
            ).called(1);
          },
        );
      }
    }
  }

  testWidgets('dark section captions have readable contrast', (tester) async {
    await tester.pumpWidget(createWidget(theme: darkMode));
    await tester.pumpAndSettle();
    for (final label in [
      'Preferences',
      'Account',
      'Support',
      'Legal',
      'Session',
    ]) {
      final color = tester.widget<Text>(find.text(label)).style!.color!;
      expect(
        contrast(color, darkMode.scaffoldBackgroundColor),
        greaterThanOrEqualTo(4.5),
        reason: label,
      );
    }
  });

  group('Settings page tests', () {
    testWidgets('displays page title without duplicate logo', (tester) async {
      await tester.pumpWidget(createWidget());

      expect(find.text('Settings'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == 'assets/Logo.png',
        ),
        findsNothing,
      );
    });

    testWidgets('displays grouped settings sections and rows', (tester) async {
      await tester.pumpWidget(createWidget());

      expect(find.byType(SettingsCard), findsNWidgets(13));
      expect(find.text('Two-factor Authentication'), findsOneWidget);
      expect(find.text('Newsletter'), findsOneWidget);
      expect(find.text('Top-up refunds'), findsOneWidget);
      expect(find.byType(FirebaseSettings), findsNothing);
      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Legal'), findsOneWidget);
      expect(find.text('Session'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.text('Monthly Report'), findsOneWidget);
      expect(find.text('Request Refund'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Notify Before Finish'), findsOneWidget);
      expect(find.text('Facility Maintenance'), findsOneWidget);
    });

    testWidgets(
      'registered Firebase adds three opt-in controls without losing rows',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final service = FirebaseService(
          driver: Driver(),
          tokens: Tokens(),
          preferences: await SharedPreferences.getInstance(),
          environment: 'dev',
          platform: 'android',
          version: '1.0.0',
          build: '1',
          navigate: (_) async {},
          showNotification: (_) async {},
          diagnostic: (_) {},
        );
        GetIt.instance.registerSingleton<FirebaseService>(service);
        addTearDown(service.dispose);
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();
        expect(find.byType(SettingsCard), findsNWidgets(13));
        expect(find.byType(FirebaseSettings), findsOneWidget);
        final controls = find.descendant(
          of: find.byType(FirebaseSettings),
          matching: find.byType(SwitchListTile),
        );
        expect(controls, findsNWidgets(3));
        for (final control in tester.widgetList<SwitchListTile>(controls)) {
          expect(control.value, isFalse);
        }
        expect(find.text('Usage analytics'), findsNothing);
        expect(find.text('In-app messages'), findsOneWidget);
        expect(find.text('Push notifications'), findsOneWidget);
        expect(find.text('Two-factor Authentication'), findsOneWidget);
      },
    );

    testWidgets('displays correct icons for each card', (tester) async {
      await tester.pumpWidget(createWidget());

      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.request_page_outlined), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
    });

    testWidgets('centers content inside SingleChildScrollView', (tester) async {
      await tester.pumpWidget(createWidget());

      expect(find.byType(Center), findsWidgets);
      expect(find.byType(Column), findsWidgets);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('does not overflow on narrow settings screens', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Facility Maintenance'));
      await tester.ensureVisible(find.text('Notify Before Finish'));

      expect(tester.takeException(), isNull);
    });

    testWidgets('calls toggleTheme when theme card is tapped', (tester) async {
      await tester.pumpWidget(createWidget());

      await tester.tap(
        find.ancestor(
          of: find.byIcon(Icons.lightbulb_outline),
          matching: find.byType(SettingsCard),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => mockThemeManager.toggleTheme()).called(1);
    });

    testWidgets('loads notification lead time from ProfileService', (
      tester,
    ) async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => 7);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('shows default notification lead time when loading fails', (
      tester,
    ) async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenThrow(Exception('missing profile'));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('increments notification lead time when + is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      verify(() => mockProfileService.setNotificationLeadTime(6)).called(1);
    });

    testWidgets('decrements notification lead time when - is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.remove));
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      verify(() => mockProfileService.setNotificationLeadTime(4)).called(1);
    });

    testWidgets('does not decrement below 0', (tester) async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => 0);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.remove));
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      verifyNever(() => mockProfileService.setNotificationLeadTime(any()));
    });

    testWidgets('notification lead time does not exceed max limit', (
      tester,
    ) async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => Settings.maxNotificationLeadTime - 2);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final plusButton = find.byIcon(Icons.add);
      await tester.ensureVisible(plusButton);

      await tester.tap(plusButton);
      await tester.pumpAndSettle();

      await tester.tap(plusButton);
      await tester.pumpAndSettle();

      await tester.tap(plusButton);
      await tester.pumpAndSettle();

      expect(find.text('${Settings.maxNotificationLeadTime}'), findsOneWidget);
      verify(
        () => mockProfileService.setNotificationLeadTime(
          Settings.maxNotificationLeadTime,
        ),
      ).called(1);
    });

    testWidgets('shows confirmation dialog when Sign Out is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(SettingsCard, 'Sign Out'));
      await tester.tap(find.widgetWithText(SettingsCard, 'Sign Out'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to sign out?'), findsOneWidget);
    });

    testWidgets('calls logout and navigates to /login on Sign Out confirm', (
      tester,
    ) async {
      when(() => mockAuthService.logout()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(SettingsCard, 'Sign Out'));
      await tester.tap(find.widgetWithText(SettingsCard, 'Sign Out'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Out'));
      await tester.pumpAndSettle();

      verify(() => mockAuthService.logout()).called(1);
    });

    testWidgets('does not log out when Cancel is tapped', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(SettingsCard, 'Sign Out'));
      await tester.tap(find.widgetWithText(SettingsCard, 'Sign Out'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => mockAuthService.logout());
    });

    testWidgets('navigates to /editProfile when Edit Profile is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(SettingsCard, 'Edit Profile'),
      );
      await tester.tap(find.widgetWithText(SettingsCard, 'Edit Profile'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/editProfile',
      );
    });

    testWidgets('fetches transactions and navigates to monthly report', (
      tester,
    ) async {
      when(() => mockTransactionService.getTransactionsForUser()).thenAnswer(
        (_) async => [
          {'id': '1', 'amount': 100},
          {'id': '2', 'amount': 200},
        ],
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(SettingsCard, 'Monthly Report'),
      );
      await tester.tap(find.text('Monthly Report'));
      await tester.pumpAndSettle();

      verify(() => mockTransactionService.getTransactionsForUser()).called(1);
    });

    testWidgets('navigates to /refundPage when Request Refund is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(SettingsCard, 'Request Refund'),
      );
      await tester.tap(find.widgetWithText(SettingsCard, 'Request Refund'));
      await tester.pumpAndSettle();

      expect(find.text('Refund Page'), findsOneWidget);
    });

    testWidgets('navigates to /maintenancePage when maintenance is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(SettingsCard, 'Facility Maintenance'),
      );
      await tester.tap(
        find.widgetWithText(SettingsCard, 'Facility Maintenance'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Maintenance Page'), findsOneWidget);
    });
  });
}
