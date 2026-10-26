import 'dart:async';

import 'package:clean_stream_laundry_app/features/settings/controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;
  late MockProfileService mockProfileService;
  late MockTransactionService mockTransactionService;

  setUp(() {
    mockAuthService = MockAuthService();
    mockProfileService = MockProfileService();
    mockTransactionService = MockTransactionService();

    when(
      () => mockProfileService.getCurrentUserRole(),
    ).thenAnswer((_) async => null);
  });

  SettingsController buildController() => SettingsController(
    authService: mockAuthService,
    profileService: mockProfileService,
    transactionService: mockTransactionService,
  );

  group('loadNotificationLeadTime', () {
    test(
      'shows the saved preference without waiting for the role lookup',
      () async {
        when(
          () => mockProfileService.getNotificationLeadTime(),
        ).thenAnswer((_) async => 7);
        final role = Completer<String?>();
        when(
          () => mockProfileService.getCurrentUserRole(),
        ).thenAnswer((_) => role.future);
        final controller = buildController();
        final loading = controller.loadNotificationLeadTime();
        await Future<void>.delayed(Duration.zero);
        expect(controller.isLoadingDelay, isFalse);
        expect(controller.notificationLeadTime, 7);
        expect(controller.canUseAdminWallets, isFalse);
        role.complete('Owner');
        await loading;
        expect(controller.canUseAdminWallets, isTrue);
        controller.dispose();
      },
    );

    test('ignores late preference completion after disposal', () async {
      final pending = Completer<int>();
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) => pending.future);
      final controller = buildController();
      final loading = controller.loadNotificationLeadTime();
      controller.dispose();
      pending.complete(7);
      await loading;
      verifyNever(() => mockProfileService.getCurrentUserRole());
    });

    test('sets notificationLeadTime from service', () async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => 12);

      final controller = buildController();
      await controller.loadNotificationLeadTime();

      expect(controller.notificationLeadTime, 12);
    });

    test('sets isLoadingDelay to false after loading', () async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => 5);

      final controller = buildController();
      expect(controller.isLoadingDelay, isTrue);

      await controller.loadNotificationLeadTime();

      expect(controller.isLoadingDelay, isFalse);
    });

    test('notifies listeners after loading', () async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => 5);

      final controller = buildController();
      var notified = false;
      controller.addListener(() => notified = true);

      await controller.loadNotificationLeadTime();

      expect(notified, isTrue);
    });

    test('falls back and clears loading when lead time load fails', () async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenThrow(Exception('missing profile'));

      final controller = buildController();
      await controller.loadNotificationLeadTime();

      expect(controller.notificationLeadTime, 5);
      expect(controller.isLoadingDelay, isFalse);
    });
  });

  group('increment', () {
    test('increases notificationLeadTime by 1', () async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => 5);
      when(
        () => mockProfileService.setNotificationLeadTime(any()),
      ).thenAnswer((_) async {});

      final controller = buildController();
      await controller.loadNotificationLeadTime();

      await controller.increment();

      expect(controller.notificationLeadTime, 6);
      verify(() => mockProfileService.setNotificationLeadTime(6)).called(1);
    });

    test('does not exceed maxNotificationLeadTime', () async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => SettingsController.maxNotificationLeadTime);
      when(
        () => mockProfileService.setNotificationLeadTime(any()),
      ).thenAnswer((_) async {});

      final controller = buildController();
      await controller.loadNotificationLeadTime();

      await controller.increment();

      expect(
        controller.notificationLeadTime,
        SettingsController.maxNotificationLeadTime,
      );
      verifyNever(() => mockProfileService.setNotificationLeadTime(any()));
    });
  });

  group('decrement', () {
    test('decreases notificationLeadTime by 1', () async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => 5);
      when(
        () => mockProfileService.setNotificationLeadTime(any()),
      ).thenAnswer((_) async {});

      final controller = buildController();
      await controller.loadNotificationLeadTime();

      await controller.decrement();

      expect(controller.notificationLeadTime, 4);
      verify(() => mockProfileService.setNotificationLeadTime(4)).called(1);
    });

    test('does not go below 0', () async {
      when(
        () => mockProfileService.getNotificationLeadTime(),
      ).thenAnswer((_) async => 0);
      when(
        () => mockProfileService.setNotificationLeadTime(any()),
      ).thenAnswer((_) async {});

      final controller = buildController();
      await controller.loadNotificationLeadTime();

      await controller.decrement();

      expect(controller.notificationLeadTime, 0);
      verifyNever(() => mockProfileService.setNotificationLeadTime(any()));
    });
  });

  group('getTransactions', () {
    test('returns transactions from service', () async {
      final expected = [
        {'id': '1', 'amount': 10},
      ];
      when(
        () => mockTransactionService.getTransactionsForUser(),
      ).thenAnswer((_) async => expected);

      final controller = buildController();
      final result = await controller.getTransactions();

      expect(result, expected);
    });
  });

  group('signOut', () {
    test('calls authService.logout', () async {
      when(() => mockAuthService.logout()).thenAnswer((_) async {});

      final controller = buildController();
      await controller.signOut();

      verify(() => mockAuthService.logout()).called(1);
    });
  });
}
