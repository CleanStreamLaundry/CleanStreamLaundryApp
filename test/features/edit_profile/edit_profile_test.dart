import 'dart:async';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/edit_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'mocks.dart';
import 'lifecycle_fixtures.dart';
import '../../fixtures/loyalty_action_context.dart';

void main() {
  late MockAuthService authService;
  late MockProfileService profileService;
  late MockEdgeFunctionService edgeFunctionService;
  late StreamController<bool> authController;
  late StreamController<AuthState> sessionEvents;
  late Session session;

  setUp(() {
    authService = MockAuthService();
    profileService = MockProfileService();
    when(() => profileService.getLoyaltyActionContext('account_deletion'))
        .thenAnswer((_) async => actionContext(action: 'account_deletion'));
    edgeFunctionService = MockEdgeFunctionService();
    authController = StreamController<bool>.broadcast();
    sessionEvents = StreamController<AuthState>.broadcast(sync: true);
    session = callerSession();
    when(() => authService.currentSession).thenAnswer((_) => session);
    when(() => authService.authStateChanges).thenAnswer((_) => sessionEvents.stream);
    when(() => profileService.getAdmissionStatus()).thenAnswer((_) async => lifecycleStatus(pending: false));

    GetIt.instance.reset();
    GetIt.instance.registerSingleton<AuthService>(authService);
    GetIt.instance.registerSingleton<ProfileService>(profileService);
    GetIt.instance.registerSingleton<EdgeFunctionService>(edgeFunctionService);

    when(() => authService.onAuthChange)
        .thenAnswer((_) => authController.stream);
    when(() => authService.getCurrentUserId).thenAnswer((_) => callerId);
    when(() => authService.getCurrentUserEmail())
        .thenAnswer((_) => 'test@example.com');
    when(() => profileService.getUserNameById(callerId))
        .thenAnswer((_) async => 'John Doe');
    when(() => authService.updateUserAttributes(
      email: any(named: 'email'),
      data: any(named: 'data'),
    )).thenAnswer((_) async {});
  });

  tearDown(() async {
    await sessionEvents.close();
    await authController.close();
    GetIt.instance.reset();
  });

  Widget createWidget({ThemeData? theme, double dialogTextScale = 1}) {
    return MaterialApp.router(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(dialogTextScale),
        ),
        child: child!,
      ),
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            // Isolate dialog scaling from unrelated background Ahem overflows.
            builder: (_, __) => MediaQuery.withNoTextScaling(
              child: const EditProfilePage(),
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Scaffold(body: Text('Settings')),
          ),
          GoRoute(
            path: '/change-email-verification',
            builder: (_, __) => const Scaffold(body: Text('Verify Email')),
          ),
          GoRoute(
            path: '/admission',
            builder: (_, __) => const Scaffold(body: Text('Admission')),
          ),
        ],
      ),
    );
  }

  group('Static UI', () {
    testWidgets('displays page title', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('loads and displays user data in info cards', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Current:'), findsNWidgets(2));
      expect(find.text('John Doe'), findsNWidgets(2));
      expect(find.text('test@example.com'), findsNWidgets(2));
      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('input fields have proper hint text', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Enter your full name'), findsOneWidget);
      expect(find.text('Enter your email address'), findsOneWidget);
    });

    testWidgets('displays danger zone section with delete account button',
            (tester) async {
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          expect(find.text('Danger Zone'), findsOneWidget);
          expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
          expect(find.text('Delete Account'), findsOneWidget);
          expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        });

    testWidgets('page is scrollable', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('Loading state', () {
    testWidgets('displays loading indicator while fetching data',
            (tester) async {
          final completer = Completer<String>();
          when(() => profileService.getUserNameById(callerId))
              .thenAnswer((_) => completer.future);

          await tester.pumpWidget(createWidget());
          await tester.pump();

          expect(find.byType(CircularProgressIndicator), findsOneWidget);

          completer.complete('John Doe');
          await tester.pumpAndSettle();

          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('John Doe'), findsNWidgets(2));
        });

    testWidgets('shows error dialog when init fails', (tester) async {
      when(() => profileService.getUserNameById(any()))
          .thenThrow(Exception('Network error'));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Error'), findsOneWidget);
      expect(find.textContaining('Failed to load profile data'), findsOneWidget);
    });

    testWidgets('error dialog dismisses on OK tap', (tester) async {
      when(() => profileService.getUserNameById(any()))
          .thenThrow(Exception('Network error'));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Error'), findsNothing);
    });
  });

  group('Navigation', () {
    testWidgets('back button navigates to settings', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('navigates to verification page when email changes',
            (tester) async {
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextFormField, 'New Email'),
            'new@email.com',
          );
          await tester.tap(find.text('Save Changes'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          verify(() => authService.updateUserAttributes(
            email: 'new@email.com',
            data: null,
          )).called(1);

          expect(find.text('Verify Email'), findsOneWidget);
        });
  });

  group('Confirmation dialog', () {
    testWidgets('shows confirmation dialog before saving changes',
            (tester) async {
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextFormField, 'New Full Name'),
            'New Name',
          );
          await tester.tap(find.text('Save Changes'));
          await tester.pumpAndSettle();

          expect(find.text('Confirm Changes'), findsOneWidget);
          expect(
            find.text(
                'Are you sure you want to save these changes to your profile?'),
            findsOneWidget,
          );
          expect(find.text('Cancel'), findsOneWidget);
          expect(find.text('Save'), findsOneWidget);
        });

    testWidgets('shows No Changes dialog when nothing was edited',
            (tester) async {
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await tester.tap(find.text('Save Changes'));
          await tester.pumpAndSettle();

          expect(find.text('No Changes'), findsOneWidget);
          expect(find.text("You haven't changed anything."), findsOneWidget);

          verifyNever(() => authService.updateUserAttributes(
            email: any(named: 'email'),
            data: any(named: 'data'),
          ));
        });

    testWidgets('cancels save when user taps Cancel in confirmation',
            (tester) async {
          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextFormField, 'New Full Name'),
            'New Name',
          );
          await tester.tap(find.text('Save Changes'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          verifyNever(() => authService.updateUserAttributes(
            email: any(named: 'email'),
            data: any(named: 'data'),
          ));
        });
  });


  group('Form validation', () {
    testWidgets('validates empty name', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Full Name'),
        '',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Name cannot be empty'), findsOneWidget);
    });

    testWidgets('validates invalid email', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Email'),
        'invalid-email',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('validates empty email', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Email'),
        '   ',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Email cannot be empty'), findsOneWidget);
    });

    testWidgets('keeps long names without truncation', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final name = 'A' * 200;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Full Name'),
        name,
      );
      await tester.pump();

      final textField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'New Full Name'),
      );
      expect(textField.controller!.text, name);
    });

    testWidgets('name field only allows alphanumeric and spaces', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Full Name'),
        'Test@#\$%',
      );
      await tester.pump();

      final textField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'New Full Name'),
      );
      expect(textField.controller!.text, 'Test');
    });
  });

  group('Save behavior', () {
    testWidgets('updates name and shows success message', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Full Name'),
        'Jane Smith',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(() => authService.updateUserAttributes(
        email: null,
        data: {'full_name': 'Jane Smith'},
      )).called(1);

      expect(find.text('Profile Updated'), findsOneWidget);
    });

    testWidgets('trims whitespace before saving', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Full Name'),
        '  Jane  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Email'),
        '  jane@email.com  ',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(() => authService.updateUserAttributes(
        email: 'jane@email.com',
        data: {'full_name': 'Jane'},
      )).called(1);
    });

    testWidgets('disables save button while saving', (tester) async {
      final completer = Completer<void>();
      when(() => authService.updateUserAttributes(
        email: any(named: 'email'),
        data: any(named: 'data'),
      )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New Full Name'),
        'New Name',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find
            .ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(ElevatedButton),
        )
            .first,
      );
      expect(saveButton.onPressed, isNull);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('shows Update Failed dialog when saveChanges throws',
            (tester) async {
          when(() => authService.updateUserAttributes(
            email: any(named: 'email'),
            data: any(named: 'data'),
          )).thenThrow(Exception('Server error'));

          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextFormField, 'New Full Name'),
            'Jane Smith',
          );
          await tester.tap(find.text('Save Changes'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          expect(find.text('Update Failed'), findsOneWidget);
        });
  });


  group('Delete account', () {
    for (final theme in [lightMode, darkMode]) {
      for (final width in [320.0, 390.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('acknowledgement is reachable and cancel has no effects '
              'at $width/${scale}x ${theme.brightness.name}', (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(createWidget(theme: theme, dialogTextScale: scale));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            await tester.ensureVisible(find.byType(OutlinedButton));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(OutlinedButton));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            final deleteButton = find.widgetWithText(ElevatedButton, 'Request Deletion');
            final acknowledgement = find.byType(CheckboxListTile);
            final checkbox = find.byType(Checkbox);
            expect(tester.widget<ElevatedButton>(deleteButton).onPressed, isNull);
            expect(tester.widget<CheckboxListTile>(acknowledgement).value, isFalse);
            await tester.tap(deleteButton);
            await tester.pumpAndSettle();

            await tester.ensureVisible(checkbox);
            await tester.pumpAndSettle();
            expect(checkbox.hitTestable(), findsOneWidget);
            await tester.tap(checkbox);
            await tester.pumpAndSettle();
            expect(tester.widget<CheckboxListTile>(acknowledgement).value, isTrue);
            expect(tester.widget<ElevatedButton>(deleteButton).onPressed, isNotNull);

            await tester.tap(checkbox);
            await tester.pumpAndSettle();
            expect(tester.widget<CheckboxListTile>(acknowledgement).value, isFalse);
            expect(tester.widget<ElevatedButton>(deleteButton).onPressed, isNull);
            await tester.tap(checkbox);
            await tester.pumpAndSettle();

            final cancel = find.widgetWithText(TextButton, 'Cancel');
            expect(cancel.hitTestable(), findsOneWidget);
            await tester.tap(cancel);
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(find.byType(EditProfilePage), findsOneWidget);
            expect(tester.takeException(), isNull);
            verifyNever(() => edgeFunctionService.runEdgeFunction(
              name: any(named: 'name'),
              body: any(named: 'body'),
            ));
            verifyNever(() => authService.logout());
          });
        }
      }
    }

    Future<void> openDeleteDialog(WidgetTester tester) async {
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
    }

    testWidgets('shows delete account confirmation dialog', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);

      expect(find.text('Delete Account?'), findsOneWidget);
      expect(
        find.text(
          'Your account will be restricted immediately. You can explicitly restore it within 90 days; signing in alone is not enough. The exact deadline appears after confirmation. Deletion does not create or extend refund rights.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Request Deletion'), findsOneWidget);
      expect(find.text(deletionAcknowledgement), findsOneWidget);
      expect(find.text('Purchased credit: \$20.50'), findsOneWidget);
      expect(find.text('Promotional credit: \$5.00'), findsOneWidget);
    });

    testWidgets('delete is disabled until acknowledgement and after unchecking',
        (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);

      final deleteButton = find.widgetWithText(ElevatedButton, 'Request Deletion');
      final acknowledgement = find.byType(CheckboxListTile);
      expect(tester.widget<CheckboxListTile>(acknowledgement).value, isFalse);
      expect(tester.widget<ElevatedButton>(deleteButton).onPressed, isNull);

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('Delete Account?'), findsOneWidget);
      verifyNever(() => edgeFunctionService.runEdgeFunction(
        name: any(named: 'name'),
        body: any(named: 'body'),
      ));

      await tester.tap(acknowledgement);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(acknowledgement).value, isTrue);
      expect(tester.widget<ElevatedButton>(deleteButton).onPressed, isNotNull);

      await tester.tap(acknowledgement);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(acknowledgement).value, isFalse);
      expect(tester.widget<ElevatedButton>(deleteButton).onPressed, isNull);
    });

    testWidgets('cancels delete when user taps Cancel', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => edgeFunctionService.runEdgeFunction(
        name: any(named: 'name'),
        body: any(named: 'body'),
      ));
    });

    testWidgets('navigates to admission after confirmed pending without logout', (tester) async {
      when(() => authService.logout()).thenAnswer((_) async {});
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) async => lifecycleStatus());

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Deletion'));
      await tester.pumpAndSettle();

      expect(find.text('Admission'), findsOneWidget);
      verifyNever(() => authService.logout());
    });

    testWidgets('shows unknown outcome when pending is not acknowledged',
            (tester) async {
          when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) async => lifecycleStatus(pending: false));

          await tester.pumpWidget(createWidget());
          await tester.pumpAndSettle();
          await openDeleteDialog(tester);

          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Request Deletion'));
          await tester.pumpAndSettle();

          expect(find.text('Check Account Status'), findsOneWidget);
          expect(
            find.text('The outcome could not be confirmed. Check account status before making another request.'),
            findsOneWidget,
          );
        });

    testWidgets('shows unknown outcome when deleteAccount throws', (tester) async {
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenThrow(Exception('Network failure'));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Deletion'));
      await tester.pumpAndSettle();

      expect(find.text('Check Account Status'), findsOneWidget);
    });

    testWidgets('unknown outcome checks status and navigates without repeating', (tester) async {
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenThrow(Exception('lost response'));
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Deletion'));
      await tester.pumpAndSettle();
      when(() => profileService.getAdmissionStatus()).thenAnswer((_) async => lifecycleStatus());
      await tester.ensureVisible(find.text('Check Account Status'));
      await tester.tap(find.text('Check Account Status'));
      await tester.pumpAndSettle();
      expect(find.text('Admission'), findsOneWidget);
      verify(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).called(1);
      verifyNever(() => authService.logout());
    });

    testWidgets('A-B-A while confirming cannot dispatch', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);
      sessionEvents.add(AuthState(AuthChangeEvent.signedOut, null));
      sessionEvents.add(AuthState(AuthChangeEvent.signedIn, session));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Deletion'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfilePage), findsOneWidget);
      verifyNever(() => profileService.requestAccountDeletion(consent: any(named: 'consent')));
    });

    for (final fail in [false, true]) {
      testWidgets('late ${fail ? "failure" : "success"} after A-B-A has no UI effects', (tester) async {
        final response = Completer<AdmissionStatus>();
        when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) => response.future);
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();
        await openDeleteDialog(tester);
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Request Deletion'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        sessionEvents.add(AuthState(AuthChangeEvent.signedOut, null));
        sessionEvents.add(AuthState(AuthChangeEvent.signedIn, session));
        if (fail) {
          response.completeError(Exception('late failure'));
        } else {
          response.complete(lifecycleStatus());
        }
        await tester.pumpAndSettle();
        expect(find.byType(EditProfilePage), findsOneWidget);
        expect(find.text('Admission'), findsNothing);
        expect(find.textContaining('The outcome could not be confirmed.'), findsNothing);
        expect(tester.takeException(), isNull);
        verifyNever(() => authService.logout());
      });
    }

    testWidgets('leaving the page while pending cannot navigate on completion', (tester) async {
      final response = Completer<AdmissionStatus>();
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) => response.future);
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Deletion'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      response.complete(lifecycleStatus());
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
