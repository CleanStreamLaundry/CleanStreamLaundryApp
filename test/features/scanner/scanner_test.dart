import 'package:clean_stream_laundry_app/features/scanner/scanner.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_communication_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockMachineCommunicationService mockMachineCommunicator;

  setUp(() async {
    mockMachineCommunicator = MockMachineCommunicationService();
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MachineCommunicationService>(
      mockMachineCommunicator,
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Widget createWidget() {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/scanner',
        routes: [
          GoRoute(path: '/scanner', builder: (_, __) => const ScannerPage()),
          GoRoute(
            path: '/startPage',
            builder: (_, __) => const Scaffold(body: Text('Start Page')),
          ),
          GoRoute(
            path: '/paymentPage',
            builder: (_, __) => const Scaffold(
              body: Column(
                children: [Text('Payment Page'), Text('Pay with Loyalty')],
              ),
            ),
          ),
        ],
      ),
    );
  }

  group('UI elements', () {
    testWidgets('displays MobileScanner', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byType(MobileScanner), findsOneWidget);
    });

    testWidgets('displays Cancel button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FloatingActionButton, 'Cancel'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('displays scanning frame overlay', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final frameFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final decoration = widget.decoration as BoxDecoration;
          final border = decoration.border as Border?;
          return border?.top.color == Colors.white &&
              border?.top.width == 3 &&
              decoration.borderRadius == BorderRadius.circular(12);
        }
        return false;
      });

      expect(frameFinder, findsOneWidget);

      final container = tester.widget<Container>(frameFinder);
      expect(container.constraints?.maxWidth, 250);
      expect(container.constraints?.maxHeight, 250);
    });

    testWidgets('MobileScanner has controller and onDetect callback', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      expect(scanner.controller, isNotNull);
      expect(scanner.onDetect, isNotNull);
      expect(scanner.tapToFocus, isTrue);
      expect(scanner.scanWindow, isNotNull);
    });
  });

  group('Navigation', () {
    testWidgets('Cancel button navigates to /startPage', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Start Page'), findsOneWidget);
      expect(find.byType(ScannerPage), findsNothing);
    });

    testWidgets('navigates to paymentPage when availability passes', (
      tester,
    ) async {
      when(
        () => mockMachineCommunicator.checkAvailability(any()),
      ).thenAnswer((_) async => 'pass');

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final state = tester.state<State>(find.byType(ScannerPage));
      await (state as dynamic).processNayaxCode('machine123');
      await tester.pumpAndSettle();

      expect(find.byType(ScannerPage), findsNothing);
      expect(find.text('Pay with Loyalty'), findsOneWidget);
    });

    testWidgets('stays on page and shows dialog when availability fails', (
      tester,
    ) async {
      when(
        () => mockMachineCommunicator.checkAvailability(any()),
      ).thenAnswer((_) async => 'fail');

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final state = tester.state<State>(find.byType(ScannerPage));
      await (state as dynamic).processNayaxCode('machine123');
      await tester.pumpAndSettle();

      expect(find.text('Machine Unavailable'), findsOneWidget);
    });
  });

  group('Lifecycle', () {
    testWidgets('disposes without errors on navigation away', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ScannerPage), findsNothing);
    });
  });
}
