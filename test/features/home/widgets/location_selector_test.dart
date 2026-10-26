import 'package:clean_stream_laundry_app/features/home/controller.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/location_selector.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mocks.dart';

void main() {
  late MockAuthService mockAuthService;
  late MockLocationService mockLocationService;
  late MockMachineService mockMachineService;
  late MockProfileService mockProfileService;

  final testLocations = [
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

    SharedPreferences.setMockInitialValues({});

    when(() => mockAuthService.getCurrentUserId).thenReturn(null);
    when(
      () => mockLocationService.getLocations(),
    ).thenAnswer((_) async => testLocations);
  });

  tearDown(() => GetIt.instance.reset());

  Future<HomePageController> buildController() async {
    final controller = HomePageController(locationParser: MockLocationParser());
    await controller.init();
    return controller;
  }

  Widget buildWidget({
    required HomePageController controller,
    VoidCallback? onGetDirections,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => LocationSelector(
            controller: controller,
            onGetDirections: onGetDirections ?? () {},
          ),
        ),
      ),
    );
  }

  group('LocationSelector', () {
    testWidgets(
      'selected details follow id rather than first duplicate address',
      (tester) async {
        final rows = [
          {
            'id': 1,
            'Address': '123 Main St',
            'Name': 'First laundry',
            'Details': 'First entrance',
          },
          {
            'id': 2,
            'Address': '123 Main St',
            'Name': 'Second laundry',
            'Details': 'Second entrance',
          },
        ];
        when(
          () => mockLocationService.getLocations(),
        ).thenAnswer((_) async => rows);
        final controller = await buildController();
        controller.selectLocation('123 Main St', locationId: 2);
        await tester.pumpWidget(buildWidget(controller: controller));
        expect(find.text('Second laundry'), findsOneWidget);
        expect(find.text('First laundry'), findsNothing);
        expect(find.text('Nearest location'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('home-location-details-button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Second entrance'), findsOneWidget);
        expect(find.text('First entrance'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
    group('Initial state', () {
      testWidgets('shows Select Location placeholder', (tester) async {
        final controller = await buildController();
        await tester.pumpWidget(buildWidget(controller: controller));

        expect(find.text('Select Location'), findsOneWidget);
      });

      testWidgets('shows selected name when already set', (tester) async {
        SharedPreferences.setMockInitialValues({
          'lastSelectedLocation': '123 Main St',
        });
        final controller = HomePageController(
          locationParser: MockLocationParser(),
        );
        await controller.init();

        await tester.pumpWidget(buildWidget(controller: controller));

        expect(find.text('123 Main St'), findsOneWidget);
      });

      testWidgets('displays location_on icon', (tester) async {
        final controller = await buildController();
        await tester.pumpWidget(buildWidget(controller: controller));

        expect(find.byIcon(Icons.location_on), findsOneWidget);
      });

      testWidgets('displays navigation icon button', (tester) async {
        final controller = await buildController();
        await tester.pumpWidget(buildWidget(controller: controller));

        expect(find.byIcon(Icons.navigation), findsOneWidget);
      });

      testWidgets('uses location display fields when selected', (tester) async {
        SharedPreferences.setMockInitialValues({
          'lastSelectedLocation': '123 Main St',
        });
        when(() => mockLocationService.getLocations()).thenAnswer(
          (_) async => [
            {
              'id': 1,
              'Address': '123 Main St',
              'Name': 'Kokomo Laundry Center',
              'Hours': '5:00 AM - 11:00 PM',
              'OpenHour': 5,
              'CloseHour': 23,
              'AfterHoursAvailable': true,
              'Details': 'Side entrance available after hours',
            },
          ],
        );
        final controller = await buildController();

        await tester.pumpWidget(buildWidget(controller: controller));

        expect(find.text('Kokomo Laundry Center'), findsOneWidget);
        expect(find.text('123 Main St'), findsOneWidget);
        expect(find.text('5:00 AM - 11:00 PM'), findsOneWidget);
      });
    });

    group('Bottom sheet', () {
      testWidgets('shows location list on tap', (tester) async {
        final controller = await buildController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.tap(find.text('Select Location'));
        await tester.pumpAndSettle();

        expect(find.text('123 Main St'), findsOneWidget);
        expect(find.text('456 Oak Ave'), findsOneWidget);
      });

      testWidgets('chevron opens location details and picker', (tester) async {
        SharedPreferences.setMockInitialValues({
          'lastSelectedLocation': '123 Main St',
        });
        when(() => mockLocationService.getLocations()).thenAnswer(
          (_) async => [
            {
              'id': 1,
              'Address': '123 Main St',
              'Name': 'Kokomo Laundry Center',
              'Hours': '5:00 AM - 11:00 PM',
              'AfterHoursAvailable': true,
              'Details': 'Side entrance available after hours',
            },
            {'id': 2, 'Address': '456 Oak Ave'},
          ],
        );
        final controller = await buildController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.tap(
          find.byKey(const ValueKey('home-location-details-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Location details'), findsOneWidget);
        expect(
          find.text('Side entrance available after hours'),
          findsOneWidget,
        );
        expect(find.text('After-hours access available'), findsOneWidget);
        expect(find.text('Change location'), findsOneWidget);
        expect(find.text('456 Oak Ave'), findsOneWidget);
      });

      testWidgets('closes bottom sheet after selecting a location', (
        tester,
      ) async {
        final controller = await buildController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.tap(find.text('Select Location'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('123 Main St'));
        await tester.pumpAndSettle();

        expect(find.text('456 Oak Ave'), findsNothing);
      });

      testWidgets('calls controller.selectLocation when location tapped', (
        tester,
      ) async {
        final controller = await buildController();
        await tester.pumpWidget(buildWidget(controller: controller));

        await tester.tap(find.text('Select Location'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('123 Main St'));
        await tester.pumpAndSettle();

        expect(controller.selectedName, '123 Main St');
        expect(controller.locationSelected, isTrue);
      });
    });

    group('Directions button', () {
      testWidgets('calls onGetDirections when navigation icon tapped', (
        tester,
      ) async {
        var tapped = false;
        final controller = await buildController();

        await tester.pumpWidget(
          buildWidget(
            controller: controller,
            onGetDirections: () => tapped = true,
          ),
        );

        await tester.tap(find.byIcon(Icons.navigation));

        expect(tapped, isTrue);
      });
    });
  });
}
