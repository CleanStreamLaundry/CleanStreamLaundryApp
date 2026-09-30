import 'dart:async';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:get_it/get_it.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/widgets/location_selector.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMaintenanceController extends Mock implements MaintenanceController {}
class _Auth extends Mock implements AuthService {}
class _Edge extends Mock implements EdgeFunctionService {}
class _Locations extends Mock implements LocationService {}
class _Profile extends Mock implements ProfileService {}

void main() {
  setUpAll(() => registerFallbackValue(MaintenanceController.noApplicableLocation));
  late MockMaintenanceController mockController;

  setUp(() {
    mockController = MockMaintenanceController();
    when(() => mockController.locations).thenReturn([(id: '1', address: '123 Wash Ave'), (id: '2', address: '456 Spin Ct')]);
    when(() => mockController.selectedLocation).thenReturn(null);
    when(() => mockController.generation).thenReturn(0);
    when(() => mockController.isCurrent(any())).thenReturn(true);
    when(() => mockController.selectLocation(any())).thenReturn(null);
  });

  Widget createWidget() {
    return MaterialApp(
      home: Scaffold(
        body: LocationSelector(controller: mockController),
      ),
    );
  }

  testWidgets('displays placeholder text when no location is selected', (tester) async {
    await tester.pumpWidget(createWidget());

    expect(find.text('Select Location'), findsOneWidget);
  });

  testWidgets('displays the selected location name from the controller', (tester) async {
    when(() => mockController.selectedLocation).thenReturn((id: '1', address: '123 Wash Ave'));

    await tester.pumpWidget(createWidget());

    expect(find.text('123 Wash Ave'), findsOneWidget);
    expect(find.text('Select Location'), findsNothing);
  });

  testWidgets('opens bottom sheet and shows options when tapped', (tester) async {
    await tester.pumpWidget(createWidget());
    await tester.tap(find.byType(GestureDetector));
    await tester.pumpAndSettle();

    expect(find.text('No Applicable Location'), findsOneWidget);
    expect(find.text('123 Wash Ave'), findsOneWidget);
    expect(find.text('456 Spin Ct'), findsOneWidget);
  });

  testWidgets('calls selectLocation on controller and closes sheet when an item is tapped', (tester) async {
    await tester.pumpWidget(createWidget());

    await tester.tap(find.byType(GestureDetector));
    await tester.pumpAndSettle();
    await tester.tap(find.text('456 Spin Ct'));
    await tester.pumpAndSettle();

    verify(() => mockController.selectLocation((id: '2', address: '456 Spin Ct'))).called(1);
    expect(find.text('456 Spin Ct'), findsNothing);
  });

  testWidgets('selecting "No Applicable Location" sends the explicit null-ID choice', (tester) async {
    await tester.pumpWidget(createWidget());

    await tester.tap(find.byType(GestureDetector));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No Applicable Location'));
    await tester.pumpAndSettle();

    verify(() => mockController.selectLocation(MaintenanceController.noApplicableLocation)).called(1);
  });

  testWidgets('duplicate addresses display separate stable IDs and select the exact row', (tester) async {
    when(() => mockController.locations).thenReturn([
      (id: '41', address: 'Shared address'),
      (id: '42', address: 'Shared address'),
    ]);
    await tester.pumpWidget(createWidget());
    await tester.tap(find.byType(GestureDetector));
    await tester.pumpAndSettle();
    expect(find.text('Shared address'), findsNWidgets(2));
    expect(find.text('Location 41'), findsOneWidget);
    expect(find.text('Location 42'), findsOneWidget);
    await tester.tap(find.text('Location 42'));
    await tester.pumpAndSettle();
    verify(() => mockController.selectLocation((id: '42', address: 'Shared address'))).called(1);
    verifyNever(() => mockController.selectLocation((id: '41', address: 'Shared address')));
  });

  for (final transition in ['B', 'A-B-A', 'signout-login']) {
    for (final noLocation in [false, true]) {
      testWidgets('$transition while picker is open rejects ${noLocation ? 'null' : 'ID'} selection', (tester) async {
        final auth = _Auth();
        final edge = _Edge();
        final events = StreamController<bool>.broadcast(sync: true);
        String? user = 'A';
        when(() => auth.getCurrentUserId).thenAnswer((_) => user);
        when(() => auth.onAuthChange).thenAnswer((_) => events.stream);
        GetIt.instance.registerSingleton<LocationService>(_Locations());
        final subject = MaintenanceController(authService: auth,
          edgeFunctionService: edge, profileService: _Profile());
        subject.locations = [(id: '42', address: 'Shared address')];
        subject.selectLocation(subject.locations.single);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          subject.dispose();
          await events.close();
          await GetIt.instance.reset();
        });
        await tester.pumpWidget(MaterialApp(home: Scaffold(
          body: LocationSelector(controller: subject),
        )));
        await tester.tap(find.byType(GestureDetector));
        await tester.pumpAndSettle();
        user = transition == 'signout-login' ? null : 'B';
        events.add(user != null);
        if (transition != 'B') { user = 'A'; events.add(true); }
        expect(subject.selectedLocation, isNull);
        await tester.tap(find.text(noLocation ? 'No Applicable Location' : 'Location 42'));
        await tester.pumpAndSettle();
        expect(subject.selectedLocation, isNull);
        expect(find.text('Location 42'), findsNothing);
        verifyNoMoreInteractions(edge);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
