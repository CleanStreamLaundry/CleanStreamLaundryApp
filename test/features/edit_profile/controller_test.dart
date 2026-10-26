import 'dart:async';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
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
  late EditProfileController controller;

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

    controller = EditProfileController();
  });

  tearDown(() async {
    await sessionEvents.close();
    await authController.close();
    controller.disposeController();
    GetIt.instance.reset();
  });

  group('loadUserData', () {
    test('populates currentName and currentEmail from services', () async {
      await controller.init();

      expect(controller.currentName, 'John Doe');
      expect(controller.currentEmail, 'test@example.com');
    });

    test('sets controller text fields after loading', () async {
      await controller.init();

      expect(controller.nameController.text, 'John Doe');
      expect(controller.emailController.text, 'test@example.com');
    });

    test('sets isLoading to false after data loads', () async {
      expect(controller.isLoading, isTrue);

      await controller.init();

      expect(controller.isLoading, isFalse);
    });

    test('sets isLoading to false even when service throws', () async {
      when(() => profileService.getUserNameById(any()))
          .thenThrow(Exception('Network error'));

      await expectLater(controller.init(), throwsException);

      expect(controller.isLoading, isFalse);
    });

    test('reloads data when auth state changes', () async {
      await controller.init();

      when(() => profileService.getUserNameById(callerId))
          .thenAnswer((_) async => 'Jane Doe');

      authController.add(true);
      await Future.delayed(Duration.zero);

      expect(controller.currentName, 'Jane Doe');
    });
  });

  group('hasChanges', () {
    setUp(() async {
      await controller.init();
    });

    test('returns false when nothing has changed', () {
      expect(controller.hasChanges, isFalse);
    });

    test('returns true when name differs from currentName', () {
      controller.nameController.text = 'New Name';

      expect(controller.hasChanges, isTrue);
    });

    test('returns true when email differs from currentEmail', () {
      controller.emailController.text = 'new@example.com';

      expect(controller.hasChanges, isTrue);
    });

    test('returns false when text matches after trimming', () {
      controller.nameController.text = controller.currentName;
      controller.emailController.text = controller.currentEmail;

      expect(controller.hasChanges, isFalse);
    });

    test('returns true when only whitespace differs', () {
      controller.nameController.text = '  ${controller.currentName}  ';

      expect(controller.hasChanges, isFalse);
    });
  });


  group('saveChanges', () {
    setUp(() async {
      await controller.init();
      when(() => authService.updateUserAttributes(
        email: any(named: 'email'),
        data: any(named: 'data'),
      )).thenAnswer((_) async {});
    });

    test('throws when no fields have changed', () async {
      await expectLater(controller.saveChanges(), throwsException);

      verifyNever(() => authService.updateUserAttributes(
        email: any(named: 'email'),
        data: any(named: 'data'),
      ));
    });

    test('sends only name when only name changed', () async {
      controller.nameController.text = 'Jane Smith';

      await controller.saveChanges();

      verify(() => authService.updateUserAttributes(
        email: null,
        data: {'full_name': 'Jane Smith'},
      )).called(1);
    });

    test('sends only email when only email changed', () async {
      controller.emailController.text = 'new@example.com';

      await controller.saveChanges();

      verify(() => authService.updateUserAttributes(
        email: 'new@example.com',
        data: null,
      )).called(1);
    });

    test('sends both name and email when both changed', () async {
      controller.nameController.text = 'Jane Smith';
      controller.emailController.text = 'jane@example.com';

      await controller.saveChanges();

      verify(() => authService.updateUserAttributes(
        email: 'jane@example.com',
        data: {'full_name': 'Jane Smith'},
      )).called(1);
    });

    test('trims whitespace from name and email before saving', () async {
      controller.nameController.text = '  Jane  ';
      controller.emailController.text = '  jane@email.com  ';

      await controller.saveChanges();

      verify(() => authService.updateUserAttributes(
        email: 'jane@email.com',
        data: {'full_name': 'Jane'},
      )).called(1);
    });

    test('returns true when email changed', () async {
      controller.emailController.text = 'new@example.com';

      final result = await controller.saveChanges();

      expect(result, isTrue);
    });

    test('returns false when only name changed', () async {
      controller.nameController.text = 'Jane Smith';

      final result = await controller.saveChanges();

      expect(result, isFalse);
    });

    test('updates currentName after successful save', () async {
      controller.nameController.text = 'Jane Smith';

      await controller.saveChanges();

      expect(controller.currentName, 'Jane Smith');
    });

    test('sets and clears isSaving around the service call', () async {
      final completer = Completer<void>();
      when(() => authService.updateUserAttributes(
        email: any(named: 'email'),
        data: any(named: 'data'),
      )).thenAnswer((_) => completer.future);

      controller.nameController.text = 'Jane Smith';

      final future = controller.saveChanges();

      expect(controller.isSaving, isTrue);

      completer.complete();
      await future;

      expect(controller.isSaving, isFalse);
    });

    test('clears isSaving even when service throws', () async {
      when(() => authService.updateUserAttributes(
        email: any(named: 'email'),
        data: any(named: 'data'),
      )).thenThrow(Exception('Save failed'));

      controller.nameController.text = 'Jane Smith';

      await expectLater(controller.saveChanges(), throwsException);

      expect(controller.isSaving, isFalse);
    });

    test('does nothing when called while already saving', () async {
      final completer = Completer<void>();
      when(() => authService.updateUserAttributes(
        email: any(named: 'email'),
        data: any(named: 'data'),
      )).thenAnswer((_) => completer.future);

      controller.nameController.text = 'Jane Smith';

      final firstCall = controller.saveChanges();
      final secondResult = await controller.saveChanges();

      expect(secondResult, isFalse);

      completer.complete();
      await firstCall;

      verify(() => authService.updateUserAttributes(
        email: any(named: 'email'),
        data: any(named: 'data'),
      )).called(1);
    });
  });

  group('deleteAccount', () {
    Future<dynamic> request({Future<bool> Function()? confirm, bool Function()? current}) =>
        controller.deleteAccount(confirm: confirm ?? () async => true, isPageCurrent: current ?? () => true);

    test('confirmed pending preserves session and exact deadline', () async {
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) async => lifecycleStatus());
      final result = await request();
      expect(result.restoreUntil, DateTime.utc(2026, 12, 29, 12, 34, 56));
      verify(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).called(1);
      verifyNever(() => authService.logout());
      verifyNever(() => edgeFunctionService.runEdgeFunction(name: any(named: 'name'), body: any(named: 'body')));
    });

    test('cancel performs no read or mutation', () async {
      expect(await request(confirm: () async => false), isNull);
      verifyNever(() => profileService.getAdmissionStatus());
      verifyNever(() => profileService.requestAccountDeletion(consent: any(named: 'consent')));
    });

    test('existing pending status does not repeat deletion', () async {
      when(() => profileService.getAdmissionStatus()).thenAnswer((_) async => lifecycleStatus());
      expect(await request(), isNotNull);
      verifyNever(() => profileService.requestAccountDeletion(consent: any(named: 'consent')));
    });

    test('duplicate intent is ignored while confirmation is open', () async {
      final confirmation = Completer<bool>();
      final first = request(confirm: () => confirmation.future);
      expect(await request(), isNull);
      confirmation.complete(false);
      await first;
      verifyNever(() => profileService.requestAccountDeletion(consent: any(named: 'consent')));
    });

    test('duplicate mutation stays guarded until completion', () async {
      final response = Completer<AdmissionStatus>();
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) => response.future);
      final first = request();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.isDeleting, isTrue);
      expect(await request(), isNull);
      response.complete(lifecycleStatus());
      expect(await first, isNotNull);
      verify(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).called(1);
    });

    test('unknown outcome reads status without repeating request or confirmation', () async {
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenThrow(Exception('lost response'));
      expect(await request(), isNull);
      expect(controller.needsDeletionStatusCheck, isTrue);
      when(() => profileService.getAdmissionStatus()).thenAnswer((_) async => lifecycleStatus());
      expect(await request(confirm: () => throw StateError('must not confirm')), isNotNull);
      verify(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).called(1);
    });

    test('active after unknown needs a separate explicit confirmation to retry', () async {
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenThrow(Exception('lost response'));
      await request();
      expect(await request(confirm: () => throw StateError('must not confirm')), isNull);
      expect(controller.needsDeletionStatusCheck, isFalse);
      verify(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).called(1);
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) async => lifecycleStatus());
      expect(await request(), isNotNull);
      verify(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).called(1);
    });

    test('failed status check cannot dispatch mutation', () async {
      when(() => profileService.getAdmissionStatus()).thenThrow(Exception('offline'));
      await request();
      await request();
      verifyNever(() => profileService.requestAccountDeletion(consent: any(named: 'consent')));
      expect(controller.needsDeletionStatusCheck, isTrue);
    });

    for (final invalid in [
      lifecycleStatus(pending: false),
      lifecycleStatus(id: '22222222-2222-4222-8222-222222222222'),
    ]) {
      test('rejects unacknowledged result ${invalid.subjectId}/${invalid.accountState}', () async {
        when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) async => invalid);
        expect(await request(), isNull);
        expect(controller.needsDeletionStatusCheck, isTrue);
      });
    }

    test('wrong status subject never dispatches', () async {
      when(() => profileService.getAdmissionStatus()).thenAnswer((_) async =>
          lifecycleStatus(pending: false, id: '22222222-2222-4222-8222-222222222222'));
      expect(await request(), isNull);
      verifyNever(() => profileService.requestAccountDeletion(consent: any(named: 'consent')));
    });

    for (final during in ['confirmation', 'status', 'mutation']) {
      for (final fail in [false, true]) {
        test('A-B-A during $during drops late ${fail ? "error" : "success"}', () async {
          final confirmation = Completer<bool>();
          final response = Completer<AdmissionStatus>();
          when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) =>
              during == 'mutation' ? response.future : Future.value(lifecycleStatus()));
          if (during == 'status') {
            when(() => profileService.getAdmissionStatus()).thenAnswer((_) => response.future);
          }
          final first = request(confirm: () => during == 'confirmation' ? confirmation.future : Future.value(true));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          sessionEvents.add(AuthState(AuthChangeEvent.signedIn, callerSession(id: '22222222-2222-4222-8222-222222222222')));
          sessionEvents.add(AuthState(AuthChangeEvent.signedIn, session));
          if (during == 'confirmation') {
            confirmation.complete(true);
          } else if (fail) {
            response.completeError(Exception('late failure'));
          } else {
            response.complete(lifecycleStatus());
          }
          expect(await first, isNull);
          expect(controller.deletionMessage, isNull);
          if (during != 'mutation') verifyNever(() => profileService.requestAccountDeletion(consent: any(named: 'consent')));
        });
      }
    }

    test('token replacement during confirmation cannot dispatch', () async {
      expect(await request(confirm: () async {
        session = callerSession(token: 'replacement');
        return true;
      }), isNull);
      verifyNever(() => profileService.getAdmissionStatus());
    });

    test('expired session never opens confirmation', () async {
      session = callerSession(expiry: 1);
      expect(await request(confirm: () => throw StateError('must not confirm')), isNull);
      verifyNever(() => profileService.getAdmissionStatus());
    });

    test('leaving page while mutation runs drops completion', () async {
      var current = true;
      final response = Completer<AdmissionStatus>();
      when(() => profileService.requestAccountDeletion(consent: any(named: 'consent'))).thenAnswer((_) => response.future);
      final first = request(current: () => current);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      current = false;
      response.complete(lifecycleStatus());
      expect(await first, isNull);
    });

    test('closed auth stream fails closed', () async {
      await sessionEvents.close();
      expect(await request(), isNull);
      verifyNever(() => profileService.getAdmissionStatus());
    });
  });
}
