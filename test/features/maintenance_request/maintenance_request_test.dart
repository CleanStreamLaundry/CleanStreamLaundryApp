import 'dart:async';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/maintenance_request.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/controller.dart';

class MockMaintenanceController extends Mock implements MaintenanceController {}

void main() {
  late MockMaintenanceController mockController;
  late TextEditingController descriptionController;

  setUp(() {
    mockController = MockMaintenanceController();
    descriptionController = TextEditingController();

    when(() => mockController.attemptedSubmit).thenReturn(false);
    when(
      () => mockController.categories,
    ).thenReturn(['Washer/Dryer Maintenance', 'App Maintenance', 'Other']);
    when(() => mockController.selectedCategory).thenReturn(null);
    when(() => mockController.isLoading).thenReturn(false);
    when(() => mockController.generation).thenReturn(0);
    when(() => mockController.draftKey).thenReturn('fixture-draft');
    when(() => mockController.isCurrent(any())).thenReturn(true);
    when(() => mockController.isFormValid).thenReturn(false);
    when(() => mockController.selectedImage).thenReturn(null);
    when(
      () => mockController.descriptionController,
    ).thenReturn(descriptionController);
    when(() => mockController.locations).thenReturn([
      (id: '1', address: 'Address 1'),
      (id: '2', address: 'Address 2'),
    ]);
    when(() => mockController.selectedLocation).thenReturn(null);
    when(() => mockController.init()).thenAnswer((_) async => {});
    when(() => mockController.addListener(any())).thenReturn(null);
    when(() => mockController.removeListener(any())).thenReturn(null);
    when(() => mockController.disposeController()).thenReturn(null);
    when(() => mockController.dispose()).thenReturn(null);
  });

  Widget createWidget() {
    return MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => MaintenancePage(controller: mockController),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: Text('Settings Page')),
          ),
        ],
      ),
    );
  }

  group('Maintenance Page Tests', () {
    testWidgets('renders all required UI elements', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Request Maintenance'), findsOneWidget);
      expect(find.text('Submit Maintenance Request'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('calls init on page load to fetch locations', (tester) async {
      await tester.pumpWidget(createWidget());

      verify(() => mockController.init()).called(1);
    });

    testWidgets('invalid form retains branded submit for validation feedback', (
      tester,
    ) async {
      when(() => mockController.isFormValid).thenReturn(false);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final color = button.style?.backgroundColor?.resolve({});
      expect(
        color,
        Theme.of(
          tester.element(find.byType(ElevatedButton)),
        ).colorScheme.primary,
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('calls markAttemptedSubmit on button press with auto-scroll', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final submitButton = find.text('Submit Maintenance Request');

      await tester.dragUntilVisible(
        submitButton,
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      await tester.tap(submitButton);
      await tester.pump();

      verify(() => mockController.markAttemptedSubmit()).called(1);
    });

    testWidgets('shows loading indicator when controller is loading', (
      tester,
    ) async {
      when(() => mockController.isLoading).thenReturn(true);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows success dialog on successful submission', (
      tester,
    ) async {
      when(() => mockController.isFormValid).thenReturn(true);
      when(
        () => mockController.submitMaintenance(),
      ).thenAnswer((_) async => true);
      when(() => mockController.markAttemptedSubmit()).thenReturn(null);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final submitButton = find.text('Submit Maintenance Request');

      await tester.dragUntilVisible(
        submitButton,
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      await tester.tap(submitButton);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Success'), findsOneWidget);
      expect(
        find.text('Your maintenance request has been submitted'),
        findsOneWidget,
      );
    });
  });

  group('Maintenance page lifetime', () {
    Future<void> pressSubmit(WidgetTester tester) async {
      await tester.dragUntilVisible(
        find.text('Submit Maintenance Request'),
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.tap(find.text('Submit Maintenance Request'));
      await tester.pump();
    }

    for (final throwsError in [false, true]) {
      testWidgets(
        '${throwsError ? 'thrown' : 'false'} result preserves text and shows safe uncertainty',
        (tester) async {
          final pending = Completer<bool>();
          descriptionController.text = 'Keep this draft';
          when(() => mockController.isFormValid).thenReturn(true);
          when(
            () => mockController.submitMaintenance(),
          ).thenAnswer((_) => pending.future);
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();
          await pressSubmit(tester);
          if (throwsError) {
            pending.completeError(StateError('private synthetic detail'));
          } else {
            pending.complete(false);
          }
          await tester.pumpAndSettle();
          expect(
            find.text(MaintenanceController.unknownMessage),
            findsOneWidget,
          );
          expect(find.text('Success'), findsNothing);
          expect(find.text('Settings Page'), findsNothing);
          expect(descriptionController.text, 'Keep this draft');
          await tester.pump(const Duration(minutes: 1));
          verify(() => mockController.submitMaintenance()).called(1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final completion in ['success', 'failure', 'error']) {
      for (final invalidation in ['unmount', 'account']) {
        testWidgets(
          '$completion after $invalidation does not show a result or navigate',
          (tester) async {
            final pending = Completer<bool>();
            var current = true;
            when(
              () => mockController.isCurrent(any()),
            ).thenAnswer((_) => current);
            when(() => mockController.isFormValid).thenReturn(true);
            when(
              () => mockController.submitMaintenance(),
            ).thenAnswer((_) => pending.future);
            await tester.pumpWidget(createWidget());
            await tester.pumpAndSettle();
            await pressSubmit(tester);
            if (invalidation == 'unmount') {
              await tester.pumpWidget(const SizedBox.shrink());
            } else {
              current = false;
            }
            if (completion == 'error') {
              pending.completeError(StateError('late synthetic error'));
            } else {
              pending.complete(completion == 'success');
            }
            await tester.pumpAndSettle();
            expect(find.text('Success'), findsNothing);
            expect(
              find.text(MaintenanceController.unknownMessage),
              findsNothing,
            );
            expect(find.text('Settings Page'), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('duplicate presses are guarded even before the next rebuild', (
      tester,
    ) async {
      final pending = Completer<bool>();
      when(() => mockController.isFormValid).thenReturn(true);
      when(
        () => mockController.submitMaintenance(),
      ).thenAnswer((_) => pending.future);
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      final callback = tester
          .widget<ElevatedButton>(find.byType(ElevatedButton))
          .onPressed!;
      callback();
      callback();
      verify(() => mockController.submitMaintenance()).called(1);
      pending.complete(false);
      await tester.pumpAndSettle();
    });

    for (final changeAccount in [false, true]) {
      testWidgets(
        'dialog dismissal ${changeAccount ? 'rejects a stale account' : 'keeps successful settings navigation'}',
        (tester) async {
          var current = true;
          when(
            () => mockController.isCurrent(any()),
          ).thenAnswer((_) => current);
          when(() => mockController.isFormValid).thenReturn(true);
          when(
            () => mockController.submitMaintenance(),
          ).thenAnswer((_) async => true);
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();
          await pressSubmit(tester);
          await tester.pumpAndSettle();
          expect(find.text('Success'), findsOneWidget);
          current = !changeAccount;
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(
            find.text('Settings Page'),
            changeAccount ? findsNothing : findsOneWidget,
          );
        },
      );
    }
  });

  realControllerPageTests();
}

class _PageAuth extends Mock implements AuthService {}

class _PageEdge extends Mock implements EdgeFunctionService {}

class _PageProfile extends Mock implements ProfileService {}

class _PageLocations extends Mock implements LocationService {}

void realControllerPageTests() {
  group('Maintenance page actual controller', () {
    for (final accountChange in ['A-B-A', 'signout-login']) {
      testWidgets(
        'initial replay retains fields; batched $accountChange clears draft and rejects late success',
        (tester) async {
          final auth = _PageAuth();
          final edge = _PageEdge();
          final locations = _PageLocations();
          final events = StreamController<bool>.broadcast(sync: true);
          String? user = '11111111-1111-4111-8111-111111111111';
          when(() => auth.getCurrentUserId).thenAnswer((_) => user);
          when(() => auth.onAuthChange).thenAnswer((_) => events.stream);
          when(() => locations.getLocations()).thenAnswer(
            (_) async => [
              {'id': 1, 'Address': 'Fixture location'},
            ],
          );
          final post = Completer<FunctionResponse?>();
          when(
            () => edge.runEdgeFunction(
              name: any(named: 'name'),
              body: any(named: 'body'),
            ),
          ).thenAnswer((_) => post.future);
          GetIt.instance.registerSingleton<LocationService>(locations);
          final subject = MaintenanceController(
            authService: auth,
            edgeFunctionService: edge,
            profileService: _PageProfile(),
          );
          subject.selectedCategory = 'Other';
          subject.selectedLocation = (id: '1', address: 'Fixture location');
          subject.descriptionController.text = 'Draft belongs to A';
          final router = GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => MaintenancePage(controller: subject),
              ),
              GoRoute(
                path: '/settings',
                builder: (_, _) => const Text('Settings fixture'),
              ),
            ],
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            subject.dispose();
            router.dispose();
            await events.close();
            await GetIt.instance.reset();
          });
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          events.add(true);
          await tester.pumpAndSettle();
          expect(find.text('Draft belongs to A'), findsOneWidget);
          expect(subject.selectedCategory, 'Other');
          await tester.dragUntilVisible(
            find.text('Submit Maintenance Request'),
            find.byType(SingleChildScrollView),
            const Offset(0, -200),
          );
          await tester.tap(find.text('Submit Maintenance Request'));
          await tester.pump();
          user = accountChange == 'A-B-A'
              ? '22222222-2222-4222-8222-222222222222'
              : null;
          events.add(user != null);
          user = '11111111-1111-4111-8111-111111111111';
          events.add(true);
          await tester.pump();
          expect(find.text('Draft belongs to A'), findsNothing);
          expect(subject.selectedCategory, isNull);
          expect(
            tester
                .state<FormFieldState<String>>(
                  find.byType(DropdownButtonFormField<String>),
                )
                .value,
            isNull,
          );
          post.complete(
            FunctionResponse(
              status: 200,
              data: {
                'success': true,
                'record': [
                  {
                    'maint_id': 12,
                    'user_id': user,
                    'category': 'Other',
                    'location': 'Fixture location',
                    'description': 'Draft belongs to A',
                    'image_data': null,
                    'location_id': 1,
                    'attachment_ref': null,
                  },
                ],
              },
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Success'), findsNothing);
          expect(find.text('Settings fixture'), findsNothing);
          expect(subject.descriptionController.text, isEmpty);
          expect(subject.submissionMessage, isNull);
          verify(
            () => edge.runEdgeFunction(
              name: any(named: 'name'),
              body: any(named: 'body'),
            ),
          ).called(1);
        },
      );
    }
  });
}
