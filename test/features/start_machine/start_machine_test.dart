import 'dart:ui' show SemanticsAction;

import 'package:clean_stream_laundry_app/features/start_machine/start_machine.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockDoorUnlocker mockUnlocker;
  late MockProfileService mockProfileService;
  late MockAuthService mockAuthService;

  setUp(() async {
    mockUnlocker = MockDoorUnlocker();
    mockProfileService = MockProfileService();
    mockAuthService = MockAuthService();

    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<ProfileService>(mockProfileService);
    GetIt.instance.registerSingleton<AuthService>(mockAuthService);

    when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
    when(
      () => mockProfileService.getUserBalanceById('user123'),
    ).thenAnswer((_) async => {'balance': 50.0});
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Widget createWidget({bool doorAccessEnabled = true}) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => StartPage(
              doorUnlocker: mockUnlocker,
              doorAccessEnabled: doorAccessEnabled,
            ),
          ),
          GoRoute(
            path: '/scanner',
            builder: (context, state) =>
                const Scaffold(body: Text('Scanner Page')),
          ),
          GoRoute(
            path: '/startPage',
            builder: (context, state) => StartPage(
              doorUnlocker: mockUnlocker,
              doorAccessEnabled: doorAccessEnabled,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> scrollToUnlockButton(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Unlock Door'));
    await tester.pumpAndSettle();
  }

  group('Static UI', () {
    testWidgets(
      'beta keeps laundry actions without exposing mock door access',
      (tester) async {
        await tester.pumpWidget(createWidget(doorAccessEnabled: false));
        await tester.pumpAndSettle();

        expect(find.text('Tap to Pay'), findsOneWidget);
        expect(find.text('Scan QR code'), findsOneWidget);
        expect(find.text('How it works'), findsOneWidget);
        expect(find.text('After Hours'), findsNothing);
        expect(find.text('Unlock Door'), findsNothing);
        verifyNever(() => mockUnlocker.unlockNearestDoor());
        verifyNever(() => mockProfileService.getUserBalanceById(any()));

        await tester.tap(find.text('Scan QR code'));
        await tester.pumpAndSettle();
        expect(find.text('Scanner Page'), findsOneWidget);
      },
    );

    testWidgets('action tiles expose labeled button semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        final nodeIds = <int>{};
        for (final title in ['Tap to Pay', 'Scan QR code', 'Unlock Door']) {
          final finder = find.bySemanticsLabel(RegExp('^$title\\n'));
          expect(finder, findsOneWidget);
          final node = tester.getSemantics(finder);
          final data = node.getSemanticsData();
          expect(data.label, startsWith('$title\n'));
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          nodeIds.add(node.id);
        }
        expect(nodeIds, hasLength(3));
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('displays Start Laundry header', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Start Laundry'), findsOneWidget);
      expect(find.text('NFC or QR'), findsOneWidget);
      expect(
        find.text('Choose a method and start your machine.'),
        findsOneWidget,
      );
    });

    testWidgets('displays Tap To Pay card', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Tap to Pay'), findsOneWidget);
      expect(find.byIcon(Icons.tap_and_play), findsOneWidget);
      expect(
        find.text('Use your mobile wallet at the reader.'),
        findsOneWidget,
      );
    });

    testWidgets('displays Scan QR code button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.text('Fast  •  Secure  •  No extra fees'), findsOneWidget);
    });

    testWidgets('displays How it works section', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('How it works'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Start'), findsAtLeastNWidgets(1));
    });

    testWidgets('displays After Hours section and Unlock Door button', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await scrollToUnlockButton(tester);

      expect(find.text('After Hours'), findsOneWidget);
      expect(find.text('Unlock Door'), findsOneWidget);
      expect(find.text('Unlock the facility door.'), findsOneWidget);
      expect(find.text(r'Load $20 on loyalty card'), findsOneWidget);
      expect(find.text('Tap Unlock button'), findsOneWidget);
      expect(find.text('Place phone on door lock'), findsOneWidget);
    });
  });

  group('Navigation', () {
    testWidgets('tapping Scan QR code navigates to /scanner', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();

      expect(find.text('Scanner Page'), findsOneWidget);
    });

    testWidgets('tapping Tap To Pay opens instructions sheet', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tap to Pay'));
      await tester.pumpAndSettle();

      expect(find.text('Tap to pay at the machine'), findsOneWidget);
      expect(find.text('Open your wallet'), findsOneWidget);
      expect(find.text('Hold near the reader'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('fits full layout above bottom navigation on narrow screens', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final bottomNavTop = tester
          .getTopLeft(find.byType(BottomNavigationBar))
          .dy;

      expect(find.text('Tap to Pay'), findsOneWidget);
      expect(find.text('Unlock Door'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('unlock-door-card'))).dy,
        lessThan(bottomNavTop),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('places Tap to Pay before Scan QR code', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final tapTop = tester.getTopLeft(find.text('Tap to Pay')).dy;
      final scanTop = tester.getTopLeft(find.text('Scan QR code')).dy;

      expect(tapTop, lessThan(scanTop));
    });

    testWidgets('sizes Unlock Door like Tap to Pay', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final tapHeight = tester
          .getSize(find.byKey(const ValueKey('tap-to-pay-card')))
          .height;
      final unlockHeight = tester
          .getSize(find.byKey(const ValueKey('unlock-door-card')))
          .height;

      expect(unlockHeight, tapHeight);
    });

    testWidgets('does not use a scroll container for the main layout', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  });

  group('Door unlocking', () {
    testWidgets('shows searching dialog when Unlock Door is tapped', (
      tester,
    ) async {
      when(() => mockUnlocker.unlockNearestDoor()).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return true;
      });

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await scrollToUnlockButton(tester);

      await tester.tap(find.text('Unlock Door'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.textContaining('Finding Nearby Doors'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('shows success dialog after successful unlock', (tester) async {
      when(
        () => mockUnlocker.unlockNearestDoor(),
      ).thenAnswer((_) async => true);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await scrollToUnlockButton(tester);

      await tester.tap(find.text('Unlock Door'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Door Unlocked!'), findsOneWidget);
    });

    testWidgets('shows failure dialog when unlock fails', (tester) async {
      when(
        () => mockUnlocker.unlockNearestDoor(),
      ).thenAnswer((_) async => false);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await scrollToUnlockButton(tester);

      await tester.tap(find.text('Unlock Door'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('No Nearby Doors Found'), findsOneWidget);
    });

    testWidgets('allows unlocking when balance is exactly 20', (tester) async {
      when(
        () => mockProfileService.getUserBalanceById(any()),
      ).thenAnswer((_) async => {'balance': 20.0});
      when(
        () => mockUnlocker.unlockNearestDoor(),
      ).thenAnswer((_) async => true);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await scrollToUnlockButton(tester);

      await tester.tap(find.text('Unlock Door'));
      await tester.pumpAndSettle();

      verify(() => mockUnlocker.unlockNearestDoor()).called(1);
    });

    testWidgets('allows unlocking when balance is above 20', (tester) async {
      when(
        () => mockUnlocker.unlockNearestDoor(),
      ).thenAnswer((_) async => true);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await scrollToUnlockButton(tester);

      await tester.tap(find.text('Unlock Door'));
      await tester.pumpAndSettle();

      verify(() => mockUnlocker.unlockNearestDoor()).called(1);
    });
  });

  group('Low balance', () {
    testWidgets('shows low balance dialog when balance is below 20', (
      tester,
    ) async {
      when(
        () => mockProfileService.getUserBalanceById(any()),
      ).thenAnswer((_) async => {'balance': 15.0});

      await tester.pumpWidget(createWidget());
      await tester.pump();
      await tester.pumpAndSettle();
      await scrollToUnlockButton(tester);

      await tester.tap(find.text('Unlock Door'));
      await tester.pumpAndSettle();

      expect(find.text('Low Balance'), findsOneWidget);
      expect(find.textContaining('at least 20.00'), findsOneWidget);
      verifyNever(() => mockUnlocker.unlockNearestDoor());
    });

    testWidgets('shows low balance dialog when balance is null', (
      tester,
    ) async {
      when(
        () => mockProfileService.getUserBalanceById(any()),
      ).thenAnswer((_) async => null);

      await tester.pumpWidget(createWidget());
      await tester.pump();
      await tester.pumpAndSettle();
      await scrollToUnlockButton(tester);

      await tester.tap(find.text('Unlock Door'));
      await tester.pumpAndSettle();

      expect(find.text('Low Balance'), findsOneWidget);
      verifyNever(() => mockUnlocker.unlockNearestDoor());
    });
  });
}
