import 'dart:async';
import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/header.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:clean_stream_laundry_app/features/home/home.dart';
import 'package:clean_stream_laundry_app/features/widgets/navigation_bar.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;
  late MockLocationService mockLocationService;
  late MockMachineService mockMachineService;
  late MockProfileService mockProfileService;

  final defaultLocations = [
    {'id': 1, 'Address': '123 Main St'},
    {'id': 2, 'Address': '456 Oak Ave'},
  ];

  setUp(() {
    mockAuthService = MockAuthService();
    mockLocationService = MockLocationService();
    mockMachineService = MockMachineService();
    mockProfileService = MockProfileService();

    GetIt.instance.reset();
    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
    GetIt.instance.registerSingleton<LocationService>(mockLocationService);
    GetIt.instance.registerSingleton<MachineService>(mockMachineService);
    GetIt.instance.registerSingleton<ProfileService>(mockProfileService);
    final wallet = MockWalletService();
    GetIt.instance.registerSingleton<WalletService>(wallet);
    when(() => wallet.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet-1',
        status: 'active',
        paidBalanceCents: 1000,
        promoBalanceCents: 0,
        totalBalanceCents: 1000,
      ),
    );
    when(
      () => mockAuthService.onAuthChange,
    ).thenAnswer((_) => const Stream.empty());

    SharedPreferences.setMockInitialValues({});

    when(() => mockAuthService.getCurrentUserId).thenReturn(null);
    when(
      () => mockLocationService.getLocations(),
    ).thenAnswer((_) async => defaultLocations);
  });

  tearDown(() => GetIt.instance.reset());

  Widget createWidget() {
    return MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/startPage',
            builder: (context, state) => const Scaffold(body: Text('Start')),
          ),
          GoRoute(
            path: '/loyalty',
            builder: (context, state) => const Scaffold(body: Text('Wallet')),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const Scaffold(body: Text('Settings')),
          ),
        ],
      ),
    );
  }

  void mockMachineCounts(
    String locationId, {
    int washers = 5,
    int idleWashers = 3,
    int dryers = 4,
    int idleDryers = 2,
  }) {
    when(
      () => mockMachineService.getAvailability(int.parse(locationId)),
    ).thenAnswer(
      (_) async => MachineAvailability(
        washers: MachineAvailabilityCount(
          total: washers,
          available: idleWashers,
          busy: washers - idleWashers,
          unknown: 0,
        ),
        dryers: MachineAvailabilityCount(
          total: dryers,
          available: idleDryers,
          busy: dryers - idleDryers,
          unknown: 0,
        ),
        checkedAt: DateTime.now(),
        configured: true,
      ),
    );
    when(
      () => mockMachineService.getWasherCountByLocation(locationId),
    ).thenAnswer((_) async => washers);
    when(
      () => mockMachineService.getIdleWasherCountByLocation(locationId),
    ).thenAnswer((_) async => idleWashers);
    when(
      () => mockMachineService.getDryerCountByLocation(locationId),
    ).thenAnswer((_) async => dryers);
    when(
      () => mockMachineService.getIdleDryerCountByLocation(locationId),
    ).thenAnswer((_) async => idleDryers);
  }

  group('Loading state', () {
    testWidgets(
      'hidden Home keeps its controller but cannot show a late refresh error',
      (tester) async {
        final active = ValueNotifier(true);
        addTearDown(active.dispose);
        when(() => mockAuthService.getCurrentUserId).thenReturn('user-1');
        when(
          () => mockProfileService.getUserBalanceById('user-1'),
        ).thenAnswer((_) async => {'full_name': 'Jane'});
        final page = createWidget();
        await tester.pumpWidget(
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, visible, child) =>
                TickerMode(enabled: visible, child: child!),
            child: page,
          ),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<Header>(find.byType(Header))
            .controller;
        final pending = Completer<Map<String, dynamic>?>();
        when(
          () => mockProfileService.getUserBalanceById('user-1'),
        ).thenAnswer((_) => pending.future);
        final refresh = controller.refresh();
        await tester.pump();
        active.value = false;
        await tester.pump();
        pending.completeError(StateError('Synthetic late read failure'));
        await refresh;
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(
          tester.widget<Header>(find.byType(Header)).controller,
          same(controller),
        );
        clearInteractions(mockProfileService);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        verifyNever(() => mockProfileService.getUserBalanceById(any()));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('shows loading indicator while fetching data', (tester) async {
      when(() => mockLocationService.getLocations()).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return defaultLocations;
      });

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Static UI', () {
    testWidgets('shows welcome message without username', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Welcome!'), findsOneWidget);
    });

    testWidgets('shows welcome message with username when user loaded', (
      tester,
    ) async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user-1');
      when(
        () => mockProfileService.getUserNameById('user-1'),
      ).thenAnswer((_) async => 'Jane');
      when(
        () => mockProfileService.getUserBalanceById('user-1'),
      ).thenAnswer((_) async => {'balance': 999.00, 'full_name': 'Jane'});

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Welcome, Jane'), findsOneWidget);
    });

    testWidgets('shows balance loading text when balance is null', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Loading...'), findsOneWidget);
    });

    testWidgets('has SingleChildScrollView', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('fits compact screens when a location is selected', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      SharedPreferences.setMockInitialValues({
        'lastSelectedLocation': '123 Main St',
        'locationSelectionMode': 'manual',
      });
      mockMachineCounts('1');

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Availability'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fills tall phone screens without bottom dead space', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      SharedPreferences.setMockInitialValues({
        'lastSelectedLocation': '123 Main St',
        'locationSelectionMode': 'manual',
      });
      mockMachineCounts('1');

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsNothing);

      final availabilityCard = find.ancestor(
        of: find.text('Availability'),
        matching: find.byType(Card),
      );
      expect(availabilityCard, findsOneWidget);

      final availabilityBottom = tester.getBottomLeft(availabilityCard).dy;
      final navTop = tester.getTopLeft(find.byType(NavBar)).dy;

      expect(navTop - availabilityBottom, lessThanOrEqualTo(12));
      expect(tester.takeException(), isNull);
    });

    testWidgets('displays location details control', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-location-details-button')),
        findsOneWidget,
      );
    });

    testWidgets('displays Select Location text when no location chosen', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Select Location'), findsOneWidget);
    });

    testWidgets('displays location_on icon', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('displays navigation icon button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-directions-button')),
        findsOneWidget,
      );
    });

    testWidgets('does not show availability card before location selected', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Availability'), findsNothing);
    });
  });

  group('Location selector', () {
    testWidgets('shows locations in bottom sheet when tapped', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select Location'));
      await tester.pumpAndSettle();

      expect(find.text('123 Main St'), findsOneWidget);
      expect(find.text('456 Oak Ave'), findsOneWidget);
    });

    testWidgets('updates selected location after tapping a location', (
      tester,
    ) async {
      mockMachineCounts('1');

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select Location'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('123 Main St'));
      await tester.pumpAndSettle();

      expect(find.text('123 Main St'), findsOneWidget);
    });

    testWidgets('shows availability card after selecting a location', (
      tester,
    ) async {
      mockMachineCounts('1');

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select Location'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('123 Main St'));
      await tester.pumpAndSettle();

      expect(find.text('Availability'), findsOneWidget);
    });

    testWidgets('restores last selected location from storage', (tester) async {
      SharedPreferences.setMockInitialValues({
        'lastSelectedLocation': '123 Main St',
      });
      mockMachineCounts('1');

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('123 Main St'), findsOneWidget);
    });

    testWidgets('shows snackbar when directions tapped with no location', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.navigation));
      await tester.pumpAndSettle();

      expect(
        find.text('Please select a location to get directions!'),
        findsOneWidget,
      );
    });
  });

  group('Availability card', () {
    testWidgets('shows washer and dryer counts after selecting location', (
      tester,
    ) async {
      mockMachineCounts(
        '1',
        washers: 5,
        idleWashers: 3,
        dryers: 4,
        idleDryers: 2,
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select Location'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('123 Main St'));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('washers\navailable'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('dryers\navailable'), findsOneWidget);
    });
  });

  group('Nearest location button', () {
    testWidgets('nearest location action is available in details sheet', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select Location'));
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('home-nearest-location-button'));

      expect(button, findsOneWidget);
    });

    testWidgets('tapping nearest location calls getLocations', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select Location'));
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('home-nearest-location-button'));

      await tester.tap(button);
      await tester.pumpAndSettle();

      verify(() => mockLocationService.getLocations()).called(1);
    });
  });

  group('Home actions', () {
    testWidgets(
      'quiet refresh retains the existing map and balance on failure',
      (tester) async {
        when(() => mockAuthService.getCurrentUserId).thenReturn('user-1');
        when(
          () => mockProfileService.getUserBalanceById('user-1'),
        ).thenAnswer((_) async => {'full_name': 'Jane', 'balance': 999.0});
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();
        final map = tester.element(find.byType(FlutterMap));
        final controller = tester
            .widget<Header>(find.byType(Header))
            .controller;
        final wallet = GetIt.I<WalletService>() as MockWalletService;
        final delayed = Completer<WalletBalance>();
        when(() => wallet.getBalance()).thenAnswer((_) => delayed.future);
        final pending = controller.refresh();
        await tester.pump();
        expect(tester.element(find.byType(FlutterMap)), same(map));
        expect(find.text('\$10.00'), findsOneWidget);
        delayed.completeError(StateError('offline'));
        await pending;
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(FlutterMap)), same(map));
        expect(find.text('\$10.00'), findsOneWidget);
        expect(
          find.textContaining('Showing the last loaded balance'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Start Laundry navigates to start page', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-start-laundry-button')));
      await tester.pumpAndSettle();

      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('Add funds navigates to wallet route', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-add-funds-button')));
      await tester.pumpAndSettle();

      expect(find.text('Wallet'), findsOneWidget);
    });
  });
}
