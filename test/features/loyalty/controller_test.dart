import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:get_it/get_it.dart';
import 'package:clean_stream_laundry_app/features/loyalty/controller.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_ledger_entry.dart';
import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';
import 'mocks.dart';
import '../../fixtures/loyalty_action_context.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_action_context.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';

void main() {
  late LoyaltyController controller;
  late MockAuthService mockAuthService;
  late MockProfileService mockProfileService;
  late MockWalletService mockWalletService;
  late MockPaymentProcessor mockPaymentProcessor;

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(
      WalletLedgerEntry(
        id: 0,
        entryType: 'load_paid',
        amountCents: 0,
        paidAmountCents: 0,
        promoAmountCents: 0,
        createdAt: DateTime(2026),
      ),
    );
  });
  Future<List<WalletLedgerEntry>> ledger() => mockWalletService.getLedger(
    userId: any(named: 'userId'),
    walletAccountId: any(named: 'walletAccountId'),
    since: any(named: 'since'),
    before: any(named: 'before'),
    rewardsOnly: any(named: 'rewardsOnly'),
  );

  setUp(() {
    GetIt.instance.reset();

    mockAuthService = MockAuthService();
    mockProfileService = MockProfileService();
    mockWalletService = MockWalletService();
    mockPaymentProcessor = MockPaymentProcessor();

    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
    GetIt.instance.registerSingleton<ProfileService>(mockProfileService);
    GetIt.instance.registerSingleton<WalletService>(mockWalletService);
    GetIt.instance.registerSingleton<PaymentProcessor>(mockPaymentProcessor);
    when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
    when(
      () => mockAuthService.onAuthChange,
    ).thenAnswer((_) => const Stream.empty());

    when(() => mockWalletService.getBalance()).thenAnswer(
      (_) async => const WalletBalance(
        walletAccountId: 'wallet123',
        status: 'active',
        paidBalanceCents: 10000,
        promoBalanceCents: 0,
        totalBalanceCents: 10000,
      ),
    );
    when(ledger).thenAnswer((_) async => []);
    when(
      () => mockProfileService.getUserBalanceById(any()),
    ).thenAnswer((_) async => {'balance': 100.0, 'full_name': 'Jane Doe'});

    controller = LoyaltyController();
  });

  tearDown(() {
    controller.dispose();
    GetIt.instance.reset();
  });

  test('loads consent for the current account and discards a late account switch', () async {
    await controller.initialize();
    when(() => mockProfileService.getLoyaltyActionContext('wallet_load'))
        .thenAnswer((_) async => actionContext(subject: 'user123'));
    expect((await controller.loadPurchaseConsent()).subjectId, 'user123');
    final pending = Completer<LoyaltyActionContext>();
    when(() => mockProfileService.getLoyaltyActionContext('wallet_load'))
        .thenAnswer((_) => pending.future);
    final result = controller.loadPurchaseConsent();
    when(() => mockAuthService.getCurrentUserId).thenReturn('other');
    pending.complete(actionContext(subject: 'user123'));
    await expectLater(result, throwsStateError);
  });

  group('initialize', () {
    test('should fetch balance and transactions successfully', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(
        () => mockProfileService.getUserBalanceById('user123'),
      ).thenAnswer((_) async => {'balance': 100.0, 'full_name': 'Jane Doe'});

      await controller.initialize();

      expect(controller.userBalance, 100.0);
      expect(controller.userName, 'Jane Doe');
      expect(controller.isLoading, false);
      expect(controller.errorMessage, null);

      verify(() => mockAuthService.getCurrentUserId).called(greaterThan(1));
      verify(() => mockProfileService.getUserBalanceById('user123')).called(1);
      verify(() => mockWalletService.getBalance()).called(1);
      verify(ledger).called(2);
    });

    test('should handle profile service error gracefully', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(
        () => mockProfileService.getUserBalanceById('user123'),
      ).thenThrow(Exception('Network error'));

      await controller.initialize();

      expect(controller.errorMessage, 'Failed to fetch balance');
      expect(controller.isLoading, false);
    });

    test('initialize should handle null userId', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn(null);

      await controller.initialize();

      expect(controller.errorMessage, 'User not known');
      expect(controller.isLoading, false);

      verifyNever(() => mockProfileService.getUserBalanceById(any()));
    });

    test('should default to 0.0 balance when null', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(
        () => mockProfileService.getUserBalanceById('user123'),
      ).thenAnswer((_) async => {'balance': null, 'full_name': 'Jane Doe'});
      when(
        () => mockWalletService.getBalance(),
      ).thenAnswer((_) async => WalletBalance.empty());

      await controller.initialize();

      expect(controller.userBalance, 0.0);
      expect(controller.userName, 'Jane Doe');
    });

    test('should default to "John Doe" when name is null', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(
        () => mockProfileService.getUserBalanceById('user123'),
      ).thenAnswer((_) async => {'balance': 100.0, 'full_name': null});

      await controller.initialize();

      expect(controller.userName, 'John Doe');
    });
  });

  group('toggleTransactionView', () {
    test('should toggle showPastTransactions from false to true', () async {
      expect(controller.showPastTransactions, false);

      await controller.toggleTransactionView();

      expect(controller.showPastTransactions, true);
      verifyNever(ledger);
    });

    test('should toggle showPastTransactions from true to false', () async {
      controller.showPastTransactions = true;

      await controller.toggleTransactionView();

      expect(controller.showPastTransactions, false);
    });
  });

  group('fetchTransactions', () {
    test('should call wallet ledger service', () async {
      await controller.fetchTransactions();

      verify(ledger).called(2);
    });

    test('fetchTransactions filters out old wallet ledger entries', () async {
      final now = DateTime.now();
      when(ledger).thenAnswer(
        (_) async => [
          WalletLedgerEntry(
            id: 1,
            entryType: 'load_paid',
            amountCents: 1000,
            paidAmountCents: 1000,
            promoAmountCents: 0,
            createdAt: now,
          ),
          WalletLedgerEntry(
            id: 2,
            entryType: 'load_bonus',
            amountCents: 500,
            paidAmountCents: 0,
            promoAmountCents: 500,
            createdAt: now.subtract(const Duration(days: 40)),
          ),
        ],
      );

      await controller.initialize();
      await controller.toggleTransactionView();

      expect(controller.recentTransactions.length, 1);
      expect(controller.rewardTransactions, isEmpty);
    });

    test(
      'fetchTransactions populates reward history from bonus entries',
      () async {
        final now = DateTime.now();
        when(ledger).thenAnswer(
          (_) async => [
            WalletLedgerEntry(
              id: 1,
              entryType: 'load_paid',
              amountCents: 2000,
              paidAmountCents: 2000,
              promoAmountCents: 0,
              createdAt: now,
            ),
            WalletLedgerEntry(
              id: 2,
              entryType: 'load_bonus',
              amountCents: 500,
              paidAmountCents: 0,
              promoAmountCents: 500,
              createdAt: now,
            ),
            WalletLedgerEntry(
              id: 3,
              entryType: 'redeem_promo',
              amountCents: -250,
              paidAmountCents: 0,
              promoAmountCents: -250,
              createdAt: now,
            ),
          ],
        );

        await controller.fetchTransactions();

        expect(controller.rewardTransactions, hasLength(1));
        expect(
          controller.rewardTransactions.single,
          contains('added as promotional credit'),
        );
      },
    );

    test('fetchTransactions retains reward history on ledger errors', () async {
      await controller.initialize();
      controller.recentTransactions = ['old transaction'];
      controller.rewardTransactions = ['old reward'];
      when(ledger).thenThrow(Exception('Ledger unavailable'));

      await controller.fetchTransactions();

      expect(controller.recentTransactions, ['old transaction']);
      expect(controller.rewardTransactions, ['old reward']);
      expect(controller.transactionsError, isNotNull);
      expect(controller.rewardsError, isNotNull);
    });
  });

  group('loadCard', () {
    test(
      'loadCard should update balance and fetch transactions on success',
      () async {
        when(() => mockAuthService.getCurrentUserId).thenReturn('user123');

        controller.userBalance = 20.0;

        when(
          () => mockPaymentProcessor.processPayment(10.0, 'Loyalty Card'),
        ).thenAnswer((_) async => PaymentResult.success);

        when(() => mockWalletService.getBalance()).thenAnswer(
          (_) async => const WalletBalance(
            walletAccountId: 'wallet123',
            status: 'active',
            paidBalanceCents: 3000,
            promoBalanceCents: 0,
            totalBalanceCents: 3000,
          ),
        );

        final result = await controller.loadCard(10.0);

        expect(result, PaymentResult.success);
        expect(controller.userBalance, 30);

        verify(() => mockWalletService.getBalance()).called(1);
        verify(ledger).called(2);
      },
    );

    test('loadCard should not update balance on failed payment', () async {
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');

      await controller.initialize();
      controller.userBalance = 20.0;

      when(
        () => mockPaymentProcessor.processPayment(10.0, 'Loyalty Card'),
      ).thenAnswer((_) async => PaymentResult.failed);

      final result = await controller.loadCard(10.0);

      expect(result, PaymentResult.failed);
      expect(controller.userBalance, 20.0);

      verifyNever(() => mockProfileService.updateBalanceById(any(), any()));
    });
  });

  group('quiet refresh and pagination', () {
    late DateTime ledgerTime;
    setUp(() => ledgerTime = DateTime.now());
    WalletBalance balance(int cents, {String walletId = 'wallet123'}) =>
        WalletBalance(
          walletAccountId: walletId,
          status: 'active',
          paidBalanceCents: cents,
          promoBalanceCents: 0,
          totalBalanceCents: cents,
        );
    WalletLedgerEntry entry(int id, {bool reward = false}) => WalletLedgerEntry(
      id: id,
      entryType: reward ? 'load_bonus' : 'load_paid',
      amountCents: id,
      paidAmountCents: reward ? 0 : id,
      promoAmountCents: reward ? id : 0,
      createdAt: ledgerTime,
    );

    test(
      'coalesces a refresh with four reads, retaining current content',
      () async {
        await controller.initialize();
        clearInteractions(mockWalletService);
        clearInteractions(mockProfileService);
        final delayed = Completer<WalletBalance>();
        when(
          () => mockWalletService.getBalance(),
        ).thenAnswer((_) => delayed.future);
        final first = controller.refresh();
        expect(identical(first, controller.refresh()), isTrue);
        expect(controller.userBalance, 100.0);
        expect(controller.isLoading, isFalse);
        expect(controller.isRefreshing, isTrue);
        delayed.complete(balance(2500));
        await first;
        expect(controller.userBalance, 25.0);
        expect(controller.isRefreshing, isFalse);
        verify(
          () => mockProfileService.getUserBalanceById('user123'),
        ).called(1);
        verify(() => mockWalletService.getBalance()).called(1);
        verify(ledger).called(2);
      },
    );

    test(
      'one pending payment refresh stays pending, duplicate load shares work',
      () async {
        await controller.initialize();
        clearInteractions(mockWalletService);
        final result = Completer<PaymentResult>();
        when(
          () => mockPaymentProcessor.processPayment(10, 'Loyalty Card'),
        ).thenAnswer((_) => result.future);
        final first = controller.loadCard(10);
        final second = controller.loadCard(10);
        expect(identical(first, second), isTrue);
        expect(controller.isPaying, isTrue);
        await controller.refresh(ifStale: true);
        verifyNever(() => mockWalletService.getBalance());
        result.complete(PaymentResult.pending);
        expect(await first, PaymentResult.pending);
        expect(controller.userBalance, 100.0);
        expect(controller.isPaying, isFalse);
        verify(
          () => mockPaymentProcessor.processPayment(10, 'Loyalty Card'),
        ).called(1);
        verify(() => mockWalletService.getBalance()).called(1);
        verify(ledger).called(2);
        verifyNever(() => mockProfileService.updateBalanceById(any(), any()));
        verifyNever(() => mockProfileService.updateRewardsById(any(), any()));
      },
    );

    test(
      'post-payment read cannot reuse an in-flight pre-payment response',
      () async {
        await controller.initialize();
        final old = Completer<WalletBalance>();
        when(
          () => mockWalletService.getBalance(),
        ).thenAnswer((_) => old.future);
        final oldRead = controller.refresh();
        when(
          () => mockPaymentProcessor.processPayment(10, 'Loyalty Card'),
        ).thenAnswer((_) async => PaymentResult.success);
        final payment = controller.loadCard(10);
        await Future<void>.delayed(Duration.zero);
        when(
          () => mockWalletService.getBalance(),
        ).thenAnswer((_) async => balance(11000));
        old.complete(balance(5000));
        await oldRead;
        expect(await payment, PaymentResult.success);
        expect(controller.userBalance, 110.0);
        verify(() => mockWalletService.getBalance()).called(3);
      },
    );

    test(
      'changed user before balance completion prevents old-wallet ledger fetch',
      () async {
        final delayed = Completer<WalletBalance>();
        when(
          () => mockWalletService.getBalance(),
        ).thenAnswer((_) => delayed.future);
        final pending = controller.initialize();
        await Future<void>.delayed(Duration.zero);
        when(() => mockAuthService.getCurrentUserId).thenReturn('user-b');
        expect(controller.isCurrentAccount, isFalse);
        delayed.complete(balance(9000, walletId: 'wallet-a'));
        await pending;
        verifyNever(ledger);
        expect(controller.userBalance, isNull);
      },
    );

    test('A to B to A clears state and rejects the first A response', () async {
      final events = StreamController<bool>.broadcast(sync: true);
      addTearDown(events.close);
      when(() => mockAuthService.onAuthChange).thenAnswer((_) => events.stream);
      await controller.initialize();
      final firstA = Completer<WalletBalance>();
      when(
        () => mockWalletService.getBalance(),
      ).thenAnswer((_) => firstA.future);
      final old = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      when(() => mockAuthService.getCurrentUserId).thenReturn('user-b');
      when(
        () => mockWalletService.getBalance(),
      ).thenAnswer((_) async => balance(2000, walletId: 'wallet-b'));
      events.add(true);
      expect(controller.userBalance, isNull);
      expect(controller.recentTransactions, isEmpty);
      await controller.refresh();
      when(() => mockAuthService.getCurrentUserId).thenReturn('user123');
      when(
        () => mockWalletService.getBalance(),
      ).thenAnswer((_) async => balance(3000));
      events.add(true);
      await controller.refresh();
      firstA.complete(balance(9900));
      await old;
      expect(controller.userBalance, 30.0);
      when(() => mockAuthService.getCurrentUserId).thenReturn(null);
      events.add(false);
      expect(controller.userBalance, isNull);
      expect(controller.rewardTransactions, isEmpty);
      expect(controller.isCurrentAccount, isFalse);
    });

    test(
      'pending payment after account change does not refresh another wallet',
      () async {
        await controller.initialize();
        clearInteractions(mockWalletService);
        final result = Completer<PaymentResult>();
        when(
          () => mockPaymentProcessor.processPayment(10, 'Loyalty Card'),
        ).thenAnswer((_) => result.future);
        final payment = controller.loadCard(10);
        when(() => mockAuthService.getCurrentUserId).thenReturn('user-b');
        result.complete(PaymentResult.success);
        expect(await payment, PaymentResult.pending);
        verifyNever(() => mockWalletService.getBalance());
        verifyNever(ledger);
      },
    );

    test(
      'bounded pages have independent reward cursors and cached toggles',
      () async {
        final calls = <Invocation>[];
        final time = DateTime.now();
        WalletLedgerEntry row(int id, bool reward) => WalletLedgerEntry(
          id: id,
          entryType: reward ? 'load_bonus' : 'load_paid',
          amountCents: id,
          paidAmountCents: reward ? 0 : id,
          promoAmountCents: reward ? id : 0,
          createdAt: time,
        );
        when(ledger).thenAnswer((call) async {
          calls.add(call);
          final reward = call.namedArguments[#rewardsOnly] as bool;
          final before = call.namedArguments[#before] as WalletLedgerEntry?;
          if (before == null) {
            return List.generate(
              26,
              (i) => row((reward ? 200 : 100) - i, reward),
            );
          }
          return [row(before.id - 1, reward), row(before.id - 2, reward)];
        });
        await controller.initialize();
        expect(controller.recentTransactions, hasLength(3));
        expect(controller.rewardTransactions, hasLength(25));
        expect(controller.hasMoreTransactions, isTrue);
        expect(controller.hasMoreRewards, isTrue);
        await controller.toggleTransactionView();
        expect(controller.recentTransactions, hasLength(25));
        expect(calls, hasLength(2));
        await controller.loadMoreTransactions();
        expect(
          (calls.last.namedArguments[#before] as WalletLedgerEntry).id,
          76,
        );
        expect(controller.recentTransactions, hasLength(27));
        expect(controller.hasMoreTransactions, isFalse);
        await controller.loadMoreTransactions(rewardsOnly: true);
        expect(
          (calls.last.namedArguments[#before] as WalletLedgerEntry).id,
          176,
        );
        expect(controller.rewardTransactions, hasLength(27));
        expect(controller.hasMoreRewards, isFalse);
        await controller.loadMoreTransactions();
        await controller.toggleTransactionView();
        await controller.toggleTransactionView();
        expect(calls, hasLength(4));
        expect(controller.recentTransactions, hasLength(27));
        verify(() => mockWalletService.getBalance()).called(1);
      },
    );

    test(
      'page error retains rows/cursor, retry deduplicates and stops at end',
      () async {
        when(
          ledger,
        ).thenAnswer((_) async => List.generate(26, (i) => entry(100 - i)));
        await controller.initialize();
        await controller.toggleTransactionView();
        when(ledger).thenThrow(StateError('offline'));
        await controller.loadMoreTransactions();
        expect(controller.recentTransactions, hasLength(25));
        expect(controller.transactionsError, isNotNull);
        expect(controller.hasMoreTransactions, isTrue);
        when(ledger).thenAnswer((call) async {
          expect((call.namedArguments[#before] as WalletLedgerEntry).id, 76);
          return [entry(76), entry(75)];
        });
        await controller.loadMoreTransactions();
        expect(controller.recentTransactions, hasLength(26));
        expect(controller.transactionsError, isNull);
        expect(controller.hasMoreTransactions, isFalse);
      },
    );

    test(
      'refresh invalidates an older page and prevents overlapping more requests',
      () async {
        when(
          ledger,
        ).thenAnswer((_) async => List.generate(26, (i) => entry(100 - i)));
        await controller.initialize();
        await controller.toggleTransactionView();
        final oldPage = Completer<List<WalletLedgerEntry>>();
        when(ledger).thenAnswer((_) => oldPage.future);
        final pending = controller.loadMoreTransactions();
        await controller.loadMoreTransactions();
        verify(ledger).called(3);
        when(ledger).thenAnswer((_) async => [entry(200)]);
        await controller.refresh();
        oldPage.complete([entry(75)]);
        await pending;
        expect(controller.recentTransactions, hasLength(1));
        expect(controller.recentTransactions.single, contains('2.00'));
        expect(controller.isLoadingMore, isFalse);
      },
    );

    test(
      'head refresh preserves loaded pages and uses the new cursor without gaps',
      () async {
        var head = 100;
        WalletLedgerEntry? lastCursor;
        when(ledger).thenAnswer((call) async {
          if (call.namedArguments[#rewardsOnly] == true) return [];
          lastCursor = call.namedArguments[#before] as WalletLedgerEntry?;
          final start = lastCursor == null ? head : lastCursor!.id - 1;
          return List.generate(26, (i) => entry(start - i));
        });
        await controller.initialize();
        await controller.toggleTransactionView();
        await controller.loadMoreTransactions();
        expect(controller.recentTransactions, hasLength(50));
        final oldest = controller.recentTransactions.last;
        head = 110;
        await controller.refresh();
        expect(controller.recentTransactions, hasLength(60));
        expect(controller.recentTransactions.last, oldest);
        await controller.loadMoreTransactions();
        expect(lastCursor!.id, 86);
        expect(controller.recentTransactions, hasLength(60));
        expect(controller.recentTransactions.last, oldest);
      },
    );

    for (final rewardsOnly in [false, true]) {
      for (final appendSize in [26, 25]) {
        test('75 cached rows survive head refresh and append $appendSize '
            '(rewards: $rewardsOnly)', () async {
          var head = 100;
          var refreshed = false;
          WalletLedgerEntry? lastCursor;
          when(ledger).thenAnswer((call) async {
            if (call.namedArguments[#rewardsOnly] != rewardsOnly) return [];
            lastCursor = call.namedArguments[#before] as WalletLedgerEntry?;
            final start = lastCursor == null ? head : lastCursor!.id - 1;
            final count = refreshed && lastCursor != null ? appendSize : 26;
            return List.generate(
              count,
              (i) => entry(start - i, reward: rewardsOnly),
            );
          });
          List<String> visibleRows() => rewardsOnly
              ? controller.rewardTransactions
              : controller.recentTransactions;

          await controller.initialize();
          await controller.toggleTransactionView();
          await controller.loadMoreTransactions(rewardsOnly: rewardsOnly);
          await controller.loadMoreTransactions(rewardsOnly: rewardsOnly);
          final loaded = List<String>.of(visibleRows());
          expect(loaded, hasLength(75));

          head = 105;
          refreshed = true;
          await controller.refresh();
          final afterRefresh = List<String>.of(visibleRows());
          expect(afterRefresh, hasLength(80));
          expect(afterRefresh.skip(5), orderedEquals(loaded));

          await controller.loadMoreTransactions(rewardsOnly: rewardsOnly);
          expect(lastCursor!.id, 81);
          expect(visibleRows(), orderedEquals(afterRefresh));
          expect(
            rewardsOnly
                ? controller.hasMoreRewards
                : controller.hasMoreTransactions,
            appendSize == 26,
          );
        });
      }
    }

    test(
      'signed-out event invalidates same-user re-login before old result',
      () async {
        final events = StreamController<bool>.broadcast(sync: true);
        when(
          () => mockAuthService.onAuthChange,
        ).thenAnswer((_) => events.stream);
        addTearDown(events.close);
        await controller.initialize();
        final old = Completer<WalletBalance>();
        when(
          () => mockWalletService.getBalance(),
        ).thenAnswer((_) => old.future);
        final pending = controller.refresh();
        await Future<void>.delayed(Duration.zero);
        events.add(false);
        expect(controller.userBalance, isNull);
        expect(controller.isCurrentAccount, isFalse);
        when(
          () => mockWalletService.getBalance(),
        ).thenAnswer((_) async => balance(2000));
        events.add(true);
        await controller.refresh();
        old.complete(balance(9900));
        await pending;
        expect(controller.userBalance, 20.0);
      },
    );

    test('reentrant refresh listener still issues one set of reads', () async {
      var requested = false;
      controller.addListener(() {
        if (controller.isRefreshing && !requested) {
          requested = true;
          controller.refresh();
        }
      });
      await controller.initialize();
      verify(() => mockWalletService.getBalance()).called(1);
      verify(ledger).called(2);
    });

    testWidgets(
      'timeout and late ledger response preserve history without more requests',
      (tester) async {
        when(ledger).thenAnswer((_) async => [entry(100)]);
        await controller.initialize();
        final old = controller.recentTransactions.single;
        clearInteractions(mockWalletService);
        final delayed = Completer<List<WalletLedgerEntry>>();
        when(ledger).thenAnswer((_) => delayed.future);
        final pending = controller.refresh();
        await tester.pump();
        await tester.pump(LoyaltyController.requestTimeout);
        await pending;
        expect(controller.recentTransactions.single, old);
        expect(controller.transactionsError, isNotNull);
        expect(controller.isRefreshing, isFalse);
        delayed.complete([entry(999)]);
        await tester.pump(const Duration(minutes: 2));
        expect(controller.recentTransactions.single, old);
        verify(() => mockWalletService.getBalance()).called(1);
        verify(ledger).called(2);
        verifyNever(() => mockPaymentProcessor.processPayment(any(), any()));
      },
    );

    testWidgets('dispose ends pending waits and detaches auth listener', (
      tester,
    ) async {
      final events = StreamController<bool>.broadcast();
      addTearDown(events.close);
      when(() => mockAuthService.onAuthChange).thenAnswer((_) => events.stream);
      final delayed = Completer<WalletBalance>();
      when(
        () => mockWalletService.getBalance(),
      ).thenAnswer((_) => delayed.future);
      final local = LoyaltyController();
      final pending = local.initialize();
      expect(events.hasListener, isTrue);
      await tester.pump();
      local.dispose();
      await tester.pump();
      await pending;
      expect(events.hasListener, isFalse);
      delayed.completeError(StateError('late failure'));
      await tester.pump();
      verifyNever(ledger);
      expect(tester.takeException(), isNull);
    });
  });
}
