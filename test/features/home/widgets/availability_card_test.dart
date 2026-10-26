import 'dart:async';
import 'package:clean_stream_laundry_app/features/home/controller.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/availability_card.dart';
import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import '../mocks.dart';

void main() {
  late MockMachineService machines;
  late HomePageController controller;
  MachineAvailability sample({int available = 1, int unknown = 0}) =>
      MachineAvailability(
        washers: MachineAvailabilityCount(
          total: 1,
          available: available,
          busy: 1 - available - unknown,
          unknown: unknown,
        ),
        dryers: const MachineAvailabilityCount(
          total: 2,
          available: 1,
          busy: 1,
          unknown: 0,
        ),
        checkedAt: DateTime.now(),
        configured: true,
      );
  setUp(() {
    machines = MockMachineService();
    GetIt.I.registerSingleton<AuthService>(MockAuthService());
    GetIt.I.registerSingleton<LocationService>(MockLocationService());
    GetIt.I.registerSingleton<MachineService>(machines);
    GetIt.I.registerSingleton<ProfileService>(MockProfileService());
    controller = HomePageController(locationParser: MockLocationParser());
    controller.locationIDSelected = 1;
    when(
      () => machines.getAvailability(any()),
    ).thenAnswer((_) async => sample());
  });
  tearDown(() async {
    controller.dispose();
    await GetIt.I.reset();
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AvailabilityCard(controller: controller)),
      ),
    );
  }

  testWidgets('Refresh reads a fresh snapshot and updates a busy washer', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('1 of 1 washers ready'), findsOneWidget);
    when(
      () => machines.getAvailability(1),
    ).thenAnswer((_) async => sample(available: 0));
    await tester.tap(find.byTooltip('Refresh availability'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('0 of 1 washers ready'), findsOneWidget);
    verify(() => machines.getAvailability(1)).called(2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('refresh retains geometry and uses a full-size icon target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await show(tester);
    await tester.pumpAndSettle();
    final button = find.byTooltip('Refresh availability');
    final bounds = tester.getRect(find.byType(Card));
    expect(tester.getSize(button), const Size(48, 48));
    final pending = Completer<MachineAvailability>();
    when(() => machines.getAvailability(1)).thenAnswer((_) => pending.future);
    await tester.tap(button);
    await tester.pump();
    expect(tester.getRect(find.byType(Card)), bounds);
    expect(find.bySemanticsLabel('1 of 1 washers ready'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    pending.complete(sample());
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Card)), bounds);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not poll or show repeated loading while Home stays open', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 2));
    verify(() => machines.getAvailability(1)).called(1);
    expect(find.text('Checking availability…'), findsNothing);
    expect(find.textContaining('Last checked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('retains a fresh snapshot when returning to Home', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    final navigator = Navigator.of(
      tester.element(find.byType(AvailabilityCard)),
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another page')),
      ),
    );
    await tester.pumpAndSettle();
    verify(() => machines.getAvailability(1)).called(1);
    navigator.pop();
    await tester.pumpAndSettle();
    verifyNever(() => machines.getAvailability(1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'stale background refresh keeps content and refresh icon stable',
    (tester) async {
      var now = DateTime(2026, 10, 3);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AvailabilityCard(controller: controller, now: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(Card));
      final message = tester
          .widget<Text>(find.textContaining('Last checked'))
          .data;
      final pending = Completer<MachineAvailability>();
      when(() => machines.getAvailability(1)).thenAnswer((_) => pending.future);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text(message!), findsOneWidget);
      expect(find.text('Checking availability…'), findsNothing);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNotNull,
      );
      expect(find.bySemanticsLabel('1 of 1 washers ready'), findsOneWidget);
      expect(tester.getRect(find.byType(Card)), bounds);
      pending.complete(sample(available: 0));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('0 of 1 washers ready'), findsOneWidget);
      verify(() => machines.getAvailability(1)).called(2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('pauses in background and reuses a fresh snapshot on resume', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    verify(() => machines.getAvailability(1)).called(1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    verifyNever(() => machines.getAvailability(1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'hidden branch defers initial and changed-location reads until activation',
    (tester) async {
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, visible, child) =>
                TickerMode(enabled: visible, child: child!),
            child: Scaffold(body: AvailabilityCard(controller: controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      verifyNever(() => machines.getAvailability(any()));
      active.value = true;
      await tester.pumpAndSettle();
      verify(() => machines.getAvailability(1)).called(1);
      active.value = false;
      await tester.pump();
      controller.locationIDSelected = 2;
      controller.notifyListeners();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      verifyNever(() => machines.getAvailability(any()));
      expect(find.bySemanticsLabel('1 of 1 washers ready'), findsNothing);
      active.value = true;
      await tester.pumpAndSettle();
      verify(() => machines.getAvailability(2)).called(1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('unknown status is a dash, never an available washer', (
    tester,
  ) async {
    when(
      () => machines.getAvailability(1),
    ).thenAnswer((_) async => sample(available: 0, unknown: 1));
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('washers status unavailable'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('1 machine with unconfirmed status'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed refresh does not keep showing an available count', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    when(() => machines.getAvailability(1)).thenThrow(Exception('network'));
    await tester.tap(find.byTooltip('Refresh availability'));
    await tester.pumpAndSettle();
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('Status unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('late response from old location cannot replace the new one', (
    tester,
  ) async {
    final old = Completer<MachineAvailability>();
    when(() => machines.getAvailability(1)).thenAnswer((_) => old.future);
    when(
      () => machines.getAvailability(2),
    ).thenAnswer((_) async => sample(available: 0));
    await show(tester);
    await tester.pump();
    controller.locationIDSelected = 2;
    controller.notifyListeners();
    await tester.pumpAndSettle();
    old.complete(sample());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('0 of 1 washers ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('narrow Samsung-style layout fits without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('same-location account change rejects the old snapshot', (
    tester,
  ) async {
    final auth = GetIt.I<AuthService>() as MockAuthService;
    when(() => auth.getCurrentUserId).thenReturn('user-a');
    final old = Completer<MachineAvailability>();
    when(() => machines.getAvailability(1)).thenAnswer((_) => old.future);
    await show(tester);
    await tester.pump();
    when(() => auth.getCurrentUserId).thenReturn('user-b');
    when(
      () => machines.getAvailability(1),
    ).thenAnswer((_) async => sample(available: 0));
    controller.notifyListeners();
    await tester.pumpAndSettle();
    old.complete(sample());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('0 of 1 washers ready'), findsOneWidget);
    verify(() => machines.getAvailability(1)).called(2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('replacing controller at same location isolates old response', (
    tester,
  ) async {
    final old = Completer<MachineAvailability>();
    when(() => machines.getAvailability(1)).thenAnswer((_) => old.future);
    await show(tester);
    await tester.pump();
    final replacement = HomePageController(locationParser: MockLocationParser())
      ..locationIDSelected = 1;
    when(
      () => machines.getAvailability(1),
    ).thenAnswer((_) async => sample(available: 0));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AvailabilityCard(controller: replacement)),
      ),
    );
    await tester.pumpAndSettle();
    old.complete(sample());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('0 of 1 washers ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    replacement.dispose();
  });

  testWidgets('covered route defers a changed-location request until return', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    final navigator = Navigator.of(
      tester.element(find.byType(AvailabilityCard)),
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covered')),
      ),
    );
    await tester.pumpAndSettle();
    controller.locationIDSelected = 2;
    controller.notifyListeners();
    await tester.pump();
    verifyNever(() => machines.getAvailability(2));
    navigator.pop();
    await tester.pumpAndSettle();
    verify(() => machines.getAvailability(2)).called(1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late failure after unmount makes no additional request', (
    tester,
  ) async {
    final delayed = Completer<MachineAvailability>();
    when(() => machines.getAvailability(1)).thenAnswer((_) => delayed.future);
    await show(tester);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    delayed.completeError(StateError('late'));
    await tester.pump(const Duration(minutes: 2));
    verify(() => machines.getAvailability(1)).called(1);
    expect(tester.takeException(), isNull);
  });
}
