import 'package:clean_stream_laundry_app/features/home/controller.dart';
import 'dart:async';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;
  late MockLocationService mockLocationService;
  late MockMachineService mockMachineService;
  late MockProfileService mockProfileService;
  late MockLocationParser mockLocationParser;
  late MockWalletService wallet;

  final testLocations = [
    {'id': 1, 'Address': '123 Main St', 'Latitude': 40.0, 'Longitude': -86.0},
    {'id': 2, 'Address': '456 Oak Ave', 'Latitude': 40.5, 'Longitude': -86.5},
  ];

  setUp(() async {
    mockAuthService = MockAuthService();
    mockLocationService = MockLocationService();
    mockMachineService = MockMachineService();
    mockProfileService = MockProfileService();
    mockLocationParser = MockLocationParser();
    wallet = MockWalletService();

    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
    GetIt.instance.registerSingleton<LocationService>(mockLocationService);
    GetIt.instance.registerSingleton<MachineService>(mockMachineService);
    GetIt.instance.registerSingleton<ProfileService>(mockProfileService);
    GetIt.instance.registerSingleton<WalletService>(wallet);
    when(() => wallet.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet-1',
        status: 'active',
        paidBalanceCents: 1250,
        promoBalanceCents: 0,
        totalBalanceCents: 1250,
      ),
    );
    when(
      () => mockAuthService.onAuthChange,
    ).thenAnswer((_) => const Stream.empty());

    SharedPreferences.setMockInitialValues({});

    when(() => mockAuthService.getCurrentUserId).thenReturn(null);
    when(
      () => mockLocationService.getLocations(),
    ).thenAnswer((_) async => testLocations);
    when(
      () => mockLocationParser.getNearestLocation(any()),
    ).thenAnswer((_) async => null);
  });

  tearDown(() => GetIt.instance.reset());

  HomePageController buildController({DateTime Function()? now}) {
    final controller = HomePageController(
      locationParser: mockLocationParser,
      now: now,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('init', () {
    test('sets isLoading to false after init', () async {
      final controller = buildController();

      expect(controller.isLoading, isTrue);

      await controller.init();

      expect(controller.isLoading, isFalse);
    });

    test('populates locations from service', () async {
      final controller = buildController();

      await controller.init();

      expect(controller.locations, testLocations);
    });

    test('populates locationID map', () async {
      final controller = buildController();

      await controller.init();

      expect(controller.locationID['123 Main St'], equals(1));
      expect(controller.locationID['456 Oak Ave'], equals(2));
    });

    test('populates locationCoordinates map', () async {
      final controller = buildController();

      await controller.init();

      expect(controller.locationCoordinates.containsKey('123 Main St'), isTrue);
      expect(controller.locationCoordinates.containsKey('456 Oak Ave'), isTrue);
    });

    test('does not call profile service when userId is null', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn(null);
      final controller = buildController();

      await controller.init();

      verifyNever(() => mockProfileService.getUserNameById(any()));
      verifyNever(() => mockProfileService.getUserBalanceById(any()));
    });

    test('loads username and balance when userId is set', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user-1');
      when(
        () => mockProfileService.getUserNameById('user-1'),
      ).thenAnswer((_) async => 'John Doe');
      when(
        () => mockProfileService.getUserBalanceById('user-1'),
      ).thenAnswer((_) async => {'balance': 999.0, 'full_name': 'John Doe'});

      final controller = buildController();
      await controller.init();

      expect(controller.username, 'John Doe');
      expect(controller.balance?['balance'], 12.50);
    });

    test('restores last selected location from storage', () async {
      SharedPreferences.setMockInitialValues({
        'lastSelectedLocation': '123 Main St',
        'locationSelectionMode': 'manual',
      });

      final controller = buildController();
      await controller.init();

      expect(controller.selectedName, '123 Main St');
      expect(controller.locationSelected, isTrue);
      expect(controller.locationIDSelected, 1);
    });

    test(
      'does not restore location if stored address not in locations',
      () async {
        SharedPreferences.setMockInitialValues({
          'lastSelectedLocation': 'Unknown Address',
          'locationSelectionMode': 'manual',
        });

        final controller = buildController();
        await controller.init();

        expect(controller.locationSelected, isFalse);
        expect(controller.locationIDSelected, isNull);
      },
    );

    test(
      'selects nearest location by default without manual preference',
      () async {
        when(
          () => mockLocationParser.getNearestLocation(any()),
        ).thenAnswer((_) async => testLocations.last);

        final controller = buildController();
        await controller.init();

        expect(controller.selectedName, '456 Oak Ave');
        expect(controller.locationSelected, isTrue);
        expect(controller.locationIDSelected, 2);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('locationSelectionMode'), 'nearest');
        expect(prefs.getString('lastSelectedLocation'), '456 Oak Ave');
      },
    );

    test('manual location preference overrides nearest default', () async {
      SharedPreferences.setMockInitialValues({
        'lastSelectedLocation': '123 Main St',
        'locationSelectionMode': 'manual',
      });
      when(
        () => mockLocationParser.getNearestLocation(any()),
      ).thenAnswer((_) async => testLocations.last);

      final controller = buildController();
      await controller.init();

      expect(controller.selectedName, '123 Main St');
      expect(controller.locationSelected, isTrue);
      expect(controller.locationIDSelected, 1);
      verifyNever(() => mockLocationParser.getNearestLocation(any()));
    });
  });

  group('selectLocation', () {
    test(
      'duplicate addresses retain the chosen row for coordinates and availability',
      () async {
        final rows = [
          {...testLocations.first, 'Name': 'First'},
          {...testLocations.last, 'Address': '123 Main St', 'Name': 'Second'},
        ];
        when(
          () => mockLocationService.getLocations(),
        ).thenAnswer((_) async => rows);
        when(
          () => mockLocationParser.getNearestLocation(any()),
        ).thenAnswer((_) async => rows.first);
        final controller = buildController();
        await controller.init();
        expect(controller.locationIDSelected, 1);
        expect(controller.selectedLocation, same(rows.first));
        expect(controller.selectedCoordinates, const LatLng(40, -86));
        controller.selectLocation('123 Main St', locationId: 2);
        expect(controller.locationIDSelected, 2);
        expect(controller.selectedLocation, same(rows.last));
        expect(controller.selectedCoordinates, const LatLng(40.5, -86.5));
        expect(controller.isNearestSelection, isFalse);
        await Future<void>.delayed(Duration.zero);
        final restored = buildController();
        await restored.init();
        expect(restored.locationIDSelected, 2);
        expect(restored.selectedLocation, same(rows.last));
      },
    );

    test(
      'locations are published before GPS finishes and manual choice wins',
      () async {
        final gps = Completer<Map<String, dynamic>?>();
        when(
          () => mockLocationParser.getNearestLocation(any()),
        ).thenAnswer((_) => gps.future);
        final controller = buildController();
        final published = Completer<void>();
        controller.addListener(() {
          if (controller.locations.isNotEmpty && !published.isCompleted)
            published.complete();
        });
        final initializing = controller.init();
        await published.future;
        expect(controller.locationSelected, isFalse);
        expect(controller.selectedCoordinates, isNull);
        controller.selectLocation('123 Main St');
        gps.complete(testLocations.last);
        await initializing;
        expect(controller.locationIDSelected, 1);
        expect(controller.selectedCoordinates, const LatLng(40, -86));
      },
    );

    test('sets selectedName, locationSelected, locationIDSelected', () async {
      final controller = buildController();
      await controller.init();

      controller.selectLocation('123 Main St');

      expect(controller.selectedName, '123 Main St');
      expect(controller.locationSelected, isTrue);
      expect(controller.locationIDSelected, 1);
    });

    test('does nothing for unknown address', () async {
      final controller = buildController();
      await controller.init();

      controller.selectLocation('Unknown Address');

      expect(controller.locationSelected, isFalse);
      expect(controller.locationIDSelected, isNull);
    });

    test('saves selection to storage', () async {
      final controller = buildController();
      await controller.init();

      controller.selectLocation('123 Main St');
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lastSelectedLocation'), '123 Main St');
      expect(prefs.getString('locationSelectionMode'), 'manual');
    });

    test('calls onZoom when coordinates exist', () async {
      final controller = buildController();
      await controller.init();

      LatLng? zoomedTo;
      double? zoomedZoom;
      controller.onZoom = (coords, zoom) {
        zoomedTo = coords;
        zoomedZoom = zoom;
      };

      controller.selectLocation('123 Main St');

      expect(zoomedTo, isNotNull);
      expect(zoomedZoom, equals(15.0));
    });
  });

  group('selectNearestLocation', () {
    test('selects the nearest location when one is found', () async {
      when(
        () => mockLocationParser.getNearestLocation(any()),
      ).thenAnswer((_) async => testLocations.first);

      final controller = buildController();
      await controller.init();

      await controller.selectNearestLocation();

      expect(controller.selectedName, '123 Main St');
      expect(controller.locationSelected, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locationSelectionMode'), 'nearest');
      expect(prefs.getString('lastSelectedLocation'), '123 Main St');
    });

    test('does nothing when no nearest location found', () async {
      when(
        () => mockLocationParser.getNearestLocation(any()),
      ).thenAnswer((_) async => null);

      final controller = buildController();
      await controller.init();

      await controller.selectNearestLocation();

      expect(controller.locationSelected, isFalse);
    });
  });

  group('quiet refresh', () {
    setUp(() {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user-1');
      when(() => mockProfileService.getUserBalanceById(any())).thenAnswer(
        (call) async => {
          'full_name': call.positionalArguments.single,
          'balance': 999.0,
        },
      );
    });

    test(
      'coalesces reads and retains the ledger balance while refreshing',
      () async {
        final controller = buildController();
        await controller.init();
        clearInteractions(wallet);
        clearInteractions(mockProfileService);
        final delayed = Completer<WalletBalance>();
        when(() => wallet.getBalance()).thenAnswer((_) => delayed.future);
        final first = controller.refresh();
        final second = controller.refresh();
        expect(identical(first, second), isTrue);
        expect(controller.balance?['balance'], 12.50);
        expect(controller.isLoading, isFalse);
        expect(controller.isRefreshing, isTrue);
        delayed.complete(
          const WalletBalance(
            walletAccountId: 'wallet-1',
            status: 'active',
            paidBalanceCents: 2000,
            promoBalanceCents: 500,
            totalBalanceCents: 2500,
          ),
        );
        await first;
        expect(controller.balance?['balance'], 25.0);
        verify(() => wallet.getBalance()).called(1);
        verify(() => mockProfileService.getUserBalanceById('user-1')).called(1);
        verifyNever(() => mockProfileService.getUserNameById(any()));
      },
    );

    test(
      'refresh error retains content, then successful retry clears error',
      () async {
        final controller = buildController();
        await controller.init();
        when(() => wallet.getBalance()).thenThrow(StateError('offline'));
        await controller.refresh();
        expect(controller.balance?['balance'], 12.50);
        expect(controller.username, 'user-1');
        expect(controller.errorMessage, isNotNull);
        when(
          () => wallet.getBalance(),
        ).thenAnswer((_) async => WalletBalance.empty());
        await controller.refresh();
        expect(controller.balance?['balance'], 0.0);
        expect(controller.errorMessage, isNull);
      },
    );

    test(
      'only stale resume events fetch; ordinary time passage does not',
      () async {
        var now = DateTime(2026, 9, 29);
        final controller = buildController(now: () => now);
        await controller.init();
        await controller.refresh(ifStale: true);
        verify(() => wallet.getBalance()).called(1);
        now = now.add(const Duration(minutes: 1));
        verifyNever(() => wallet.getBalance());
        await controller.refresh(ifStale: true);
        verify(() => wallet.getBalance()).called(1);
      },
    );

    test(
      'account switch masks immediately and rejects delayed old-account data',
      () async {
        final authEvents = StreamController<bool>.broadcast(sync: true);
        when(
          () => mockAuthService.onAuthChange,
        ).thenAnswer((_) => authEvents.stream);
        addTearDown(authEvents.close);
        final controller = buildController();
        await controller.init();
        final old = Completer<WalletBalance>();
        when(() => wallet.getBalance()).thenAnswer((_) => old.future);
        final oldRead = controller.refresh();
        await Future<void>.delayed(Duration.zero);
        when(() => mockAuthService.getCurrentUserId).thenReturn('user-2');
        expect(controller.balance, isNull);
        expect(controller.username, isNull);
        when(
          () => wallet.getBalance(),
        ).thenAnswer((_) async => WalletBalance.empty());
        authEvents.add(true);
        await controller.refresh();
        old.complete(
          const WalletBalance(
            walletAccountId: 'wallet-1',
            status: 'active',
            paidBalanceCents: 9000,
            promoBalanceCents: 0,
            totalBalanceCents: 9000,
          ),
        );
        await oldRead;
        expect(controller.username, 'user-2');
        expect(controller.balance?['balance'], 0.0);
        when(() => mockAuthService.getCurrentUserId).thenReturn(null);
        authEvents.add(false);
        expect(controller.balance, isNull);
        expect(controller.username, isNull);
      },
    );

    test(
      'manual selection wins against delayed nearest-location lookup',
      () async {
        final controller = buildController();
        await controller.init();
        final nearest = Completer<Map<String, dynamic>?>();
        when(
          () => mockLocationParser.getNearestLocation(any()),
        ).thenAnswer((_) => nearest.future);
        final searching = controller.selectNearestLocation();
        controller.selectLocation('123 Main St');
        nearest.complete(testLocations.last);
        await searching;
        expect(controller.locationIDSelected, 1);
        expect(controller.selectedName, '123 Main St');
      },
    );

    testWidgets('timeout preserves data and ignores late completion', (
      tester,
    ) async {
      final controller = buildController();
      await controller.init();
      final late = Completer<WalletBalance>();
      when(() => wallet.getBalance()).thenAnswer((_) => late.future);
      final pending = controller.refresh();
      await tester.pump();
      await tester.pump(HomePageController.requestTimeout);
      await pending;
      expect(controller.isRefreshing, isFalse);
      expect(controller.balance?['balance'], 12.5);
      late.complete(WalletBalance.empty());
      await tester.pump();
      expect(controller.balance?['balance'], 12.5);
      expect(controller.errorMessage, isNotNull);
    });

    testWidgets('dispose cancels local wait and ignores a late error', (
      tester,
    ) async {
      final controller = HomePageController(locationParser: mockLocationParser);
      await controller.init();
      final late = Completer<WalletBalance>();
      when(() => wallet.getBalance()).thenAnswer((_) => late.future);
      final pending = controller.refresh();
      await tester.pump();
      controller.dispose();
      await tester.pump();
      await pending;
      late.completeError(StateError('late failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('getAvailability', () {
    const availability = MachineAvailability(
      washers: MachineAvailabilityCount(
        total: 5,
        available: 3,
        busy: 2,
        unknown: 0,
      ),
      dryers: MachineAvailabilityCount(
        total: 4,
        available: 2,
        busy: 2,
        unknown: 0,
      ),
      configured: true,
      checkedAt: null,
    );
    setUp(() {
      when(
        () => mockMachineService.getAvailability(any()),
      ).thenAnswer((_) async => availability);
    });

    test(
      'requires a location instead of inventing zero availability',
      () async {
        final controller = buildController();
        await controller.init();

        expect(controller.getAvailability, throwsStateError);
        verifyNever(() => mockMachineService.getAvailability(any()));
      },
    );

    test('returns machine counts for selected location', () async {
      final controller = buildController();
      await controller.init();
      controller.selectLocation('123 Main St');

      final counts = await controller.getAvailability();
      expect(counts.washers.total, 5);
      expect(counts.washers.available, 3);
      expect(counts.dryers.total, 4);
      expect(counts.dryers.available, 2);
    });

    test(
      'reads one selected-location snapshot, not four legacy counts',
      () async {
        final controller = buildController();
        await controller.init();
        controller.selectLocation('123 Main St'); // id = 1

        await controller.getAvailability();
        verify(() => mockMachineService.getAvailability(1)).called(1);
        verifyNever(() => mockMachineService.getWasherCountByLocation(any()));
        verifyNever(
          () => mockMachineService.getIdleWasherCountByLocation(any()),
        );
        verifyNever(() => mockMachineService.getDryerCountByLocation(any()));
        verifyNever(
          () => mockMachineService.getIdleDryerCountByLocation(any()),
        );
      },
    );
  });
}
