import 'dart:async';
import 'package:clean_stream_laundry_app/features/loyalty/loyalty.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:clean_stream_laundry_app/features/loyalty/widgets/wallet_pass_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';
import '../../fixtures/loyalty_action_context.dart';

void main() {
  late MockLoyaltyController mockController;

  setUpAll(() {
    registerFallbackValue((_) {});
  });

  setUp(() async {
    mockController = MockLoyaltyController();
    when(() => mockController.loadPurchaseConsent()).thenAnswer((_) async => actionContext());

    await GetIt.instance.reset();
    when(() => mockController.isLoading).thenReturn(false);
    when(() => mockController.isCurrentAccount).thenReturn(true);
    when(() => mockController.accountEpoch).thenReturn(1);
    when(() => mockController.isRefreshing).thenReturn(false);
    when(() => mockController.isPaying).thenReturn(false);
    when(() => mockController.isLoadingMore).thenReturn(false);
    when(() => mockController.isLoadingRewards).thenReturn(false);
    when(() => mockController.hasMoreTransactions).thenReturn(false);
    when(() => mockController.hasMoreRewards).thenReturn(false);
    when(() => mockController.refresh()).thenAnswer((_) async {});
    when(() => mockController.refresh(ifStale: true)).thenAnswer((_) async {});
    when(() => mockController.errorMessage).thenReturn(null);
    when(() => mockController.userName).thenReturn('Test User');
    when(() => mockController.userBalance).thenReturn(25.50);
    when(() => mockController.paidBalance).thenReturn(20.50);
    when(() => mockController.promoBalance).thenReturn(5.00);
    when(() => mockController.userReward).thenReturn(0.0);
    when(() => mockController.recentTransactions).thenReturn([]);
    when(() => mockController.rewardTransactions).thenReturn([]);
    when(() => mockController.showPastTransactions).thenReturn(false);
    when(() => mockController.initialize()).thenAnswer((_) async {});
    when(() => mockController.fetchTransactions()).thenAnswer((_) async {});
    when(() => mockController.toggleTransactionView()).thenAnswer((_) async {});
    when(() => mockController.addListener(any())).thenReturn(null);
    when(() => mockController.removeListener(any())).thenReturn(null);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Widget createWidget({bool openLoadCardOnStart = false}) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => LoyaltyPage(
              controller: mockController,
              openLoadCardOnStart: openLoadCardOnStart,
            ),
          ),
          GoRoute(
            path: '/scanner',
            builder: (_, _) => const Scaffold(body: Text('Scanner')),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('Login')),
          ),
        ],
      ),
    );
  }

  Future<void> openLoadCardDialog(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Load card'));
    await tester.tap(find.text('Load card'));
    await tester.pumpAndSettle();
  }

  Future<void> tapPay(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Load'));
    await tester.pumpAndSettle();
  }

  group('Initialization', () {
    testWidgets('calls initialize on viewModel during initState', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      verify(() => mockController.initialize()).called(1);
    });

    testWidgets('adds listener to viewModel', (tester) async {
      await tester.pumpWidget(createWidget());
      verify(() => mockController.addListener(any())).called(1);
    });

    testWidgets('removes listener on dispose', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      verify(() => mockController.removeListener(any())).called(1);
    });

    testWidgets('displays BasePage when not loading', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.byType(BasePage), findsOneWidget);
    });
  });

  group('Content display', () {
    testWidgets('displays WalletPassCard with correct username', (
      tester,
    ) async {
      when(() => mockController.userName).thenReturn('Jane Doe');
      await tester.pumpWidget(createWidget());
      await tester.pump();

      final card = tester.widget<WalletPassCard>(find.byType(WalletPassCard));
      expect(card.username, 'Jane Doe');
    });

    testWidgets('displays default username when userName is null', (
      tester,
    ) async {
      when(() => mockController.userName).thenReturn(null);
      await tester.pumpWidget(createWidget());
      await tester.pump();

      final card = tester.widget<WalletPassCard>(find.byType(WalletPassCard));
      expect(card.username, 'John Doe');
    });

    testWidgets('displays correct balance with two decimal places', (
      tester,
    ) async {
      when(() => mockController.userBalance).thenReturn(42.75);
      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.text('\$42.75'), findsOneWidget);
    });

    testWidgets('displays unknown balance rather than zero when unavailable', (
      tester,
    ) async {
      when(() => mockController.userBalance).thenReturn(null);
      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.text('Wallet balance unavailable'), findsOneWidget);
      expect(find.byType(WalletPassCard), findsNothing);
    });

    testWidgets('displays paid and promo balances', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.text('Paid \$20.50'), findsOneWidget);
      expect(find.text('Promo \$5.00'), findsOneWidget);
    });

    testWidgets('displays exact wallet pass slogan', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.text('Where freshness flows.'), findsOneWidget);
    });

    testWidgets('does not display old credit-card cues', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.byKey(const Key('cardChip')), findsNothing);
      expect(find.byKey(const Key('mastercard')), findsNothing);
      expect(find.text('1234   5678   9012   3456'), findsNothing);
    });

    testWidgets('displays Load card button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.text('Load card'), findsOneWidget);
    });

    testWidgets('opens load card dialog from route trigger', (tester) async {
      await tester.pumpWidget(createWidget(openLoadCardOnStart: true));
      await tester.pumpAndSettle();

      expect(find.text('Load Loyalty Card'), findsOneWidget);
    });

    testWidgets('displays info button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('displays zero balance correctly', (tester) async {
      when(() => mockController.userBalance).thenReturn(0.0);
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.text('\$0.00'), findsOneWidget);
    });

    testWidgets('displays large balance correctly', (tester) async {
      when(() => mockController.userBalance).thenReturn(9999.99);
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.text('\$9999.99'), findsOneWidget);
    });
  });

  group('Transactions', () {
    testWidgets('shows No transactions found when list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.text('No transactions found.'), findsOneWidget);
      expect(find.text('Transactions'), findsNothing);
    });

    testWidgets('shows transaction header when transactions exist', (
      tester,
    ) async {
      when(
        () => mockController.recentTransactions,
      ).thenReturn(['Test transaction']);
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.text('Transactions'), findsOneWidget);
    });

    testWidgets('shows Show More when showPastTransactions is false', (
      tester,
    ) async {
      when(
        () => mockController.recentTransactions,
      ).thenReturn(['Test transaction']);
      when(() => mockController.showPastTransactions).thenReturn(false);
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.text('Show More'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('shows Show Less when showPastTransactions is true', (
      tester,
    ) async {
      when(
        () => mockController.recentTransactions,
      ).thenReturn(['Test transaction']);
      when(() => mockController.showPastTransactions).thenReturn(true);
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.text('Show Less'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('calls toggleTransactionView when Show More tapped', (
      tester,
    ) async {
      when(
        () => mockController.recentTransactions,
      ).thenReturn(['Test transaction']);
      await tester.pumpWidget(createWidget());
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('transactions-toggle-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('transactions-toggle-button')),
      );
      await tester.pump();
      verify(() => mockController.toggleTransactionView()).called(1);
    });

    testWidgets('calls toggleTransactionView when Show Less tapped', (
      tester,
    ) async {
      when(
        () => mockController.recentTransactions,
      ).thenReturn(['Test transaction']);
      when(() => mockController.showPastTransactions).thenReturn(true);
      await tester.pumpWidget(createWidget());
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('transactions-toggle-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('transactions-toggle-button')),
      );
      await tester.pump();
      verify(() => mockController.toggleTransactionView()).called(1);
    });

    testWidgets('displays transaction cards with receipt icon', (tester) async {
      when(
        () => mockController.recentTransactions,
      ).thenReturn(['Test transaction']);
      await tester.pumpWidget(createWidget());
      await tester.pump();
      expect(find.byType(Card, skipOffstage: false), findsWidgets);
      expect(
        find.byIcon(Icons.receipt_long, skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  group('Error handling', () {
    testWidgets('shows inline refresh error with retained balance', (
      tester,
    ) async {
      when(() => mockController.errorMessage).thenReturn('Test error message');
      await tester.pumpWidget(createWidget());
      await tester.pump();
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Test error message'), findsOneWidget);
      expect(find.byType(WalletPassCard), findsOneWidget);
    });

    testWidgets('refresh failure does not navigate to scanner', (tester) async {
      when(
        () => mockController.errorMessage,
      ).thenReturn('Failed to fetch balance');
      await tester.pumpWidget(createWidget());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Refresh wallet'));
      await tester.pumpAndSettle();

      expect(find.text('Scanner'), findsNothing);
      expect(find.byType(WalletPassCard), findsOneWidget);
      verify(() => mockController.refresh()).called(1);
    });

    testWidgets('read errors do not force navigation to login', (tester) async {
      when(() => mockController.errorMessage).thenReturn('User not known');
      await tester.pumpWidget(createWidget());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Refresh wallet'));
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsNothing);
      verify(() => mockController.refresh()).called(1);
    });

    testWidgets('rebuilds do not enqueue error dialogs', (tester) async {
      when(
        () => mockController.errorMessage,
      ).thenReturn('Something went wrong');
      await tester.pumpWidget(createWidget());
      await tester.pump();
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Something went wrong'), findsOneWidget);
    });
  });

  group('Reward info dialog', () {
    testWidgets('opens reward info dialog when info button tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.text('Rewards program'), findsOneWidget);
      expect(
        find.text(
          'For every \$20 you spend, you get an extra \$5 automatically added to your loyalty balance.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('closes reward info dialog when Got it tapped', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(find.text('Rewards program'), findsNothing);
    });
  });

  group('Rewards sheet', () {
    testWidgets(
      'independent rewards pagination fits a narrow phone without a cached balance',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        when(() => mockController.userBalance).thenReturn(null);
        when(
          () => mockController.rewardTransactions,
        ).thenReturn(List.generate(25, (i) => 'Reward entry $i'));
        when(() => mockController.hasMoreRewards).thenReturn(true);
        when(
          () => mockController.loadMoreTransactions(rewardsOnly: true),
        ).thenAnswer((_) async {});
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('rewards-sheet-button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('More rewards'));
        await tester.tap(find.text('More rewards'));
        verify(
          () => mockController.loadMoreTransactions(rewardsOnly: true),
        ).called(1);
      },
    );

    testWidgets('opens rewards bottom sheet from Rewards pill', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('rewards-sheet-button')));
      await tester.pumpAndSettle();

      expect(find.text('Reward history'), findsOneWidget);
      expect(find.text('\$20.00 until your next \$5 reward'), findsOneWidget);
      expect(
        find.text('Earn \$5 promo credit for every \$20 loaded.'),
        findsOneWidget,
      );
      expect(find.text('No rewards earned yet.'), findsOneWidget);
    });

    testWidgets('shows reward history entries in rewards bottom sheet', (
      tester,
    ) async {
      when(() => mockController.userReward).thenReturn(5.0);
      when(
        () => mockController.rewardTransactions,
      ).thenReturn(['\$5.00 added as promotional credit on May 24, 2026']);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('rewards-sheet-button')));
      await tester.pumpAndSettle();

      expect(find.text('\$15.00 until your next \$5 reward'), findsOneWidget);
      expect(
        find.text('\$5.00 added as promotional credit on May 24, 2026'),
        findsOneWidget,
      );
      expect(find.text('No rewards earned yet.'), findsNothing);
    });
  });

  group('Payment handling', () {
    testWidgets(
      'hidden Wallet suppresses late payment dialogs and resume reads without replay',
      (tester) async {
        final active = ValueNotifier(true);
        addTearDown(active.dispose);
        final completion = Completer<PaymentResult>();
        when(
          () => mockController.loadCard(1, consent: any(named: 'consent')),
        ).thenAnswer((_) => completion.future);
        final page = createWidget();
        await tester.pumpWidget(
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, visible, child) =>
                TickerMode(enabled: visible, child: child!),
            child: page,
          ),
        );
        await tester.pumpAndSettle();
        await openLoadCardDialog(tester);
        await tapPay(tester);
        active.value = false;
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        completion.complete(PaymentResult.pending);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        verify(() => mockController.setActive(false)).called(greaterThan(0));
        verifyNever(() => mockController.refresh(ifStale: true));
        active.value = true;
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        verify(() => mockController.refresh(ifStale: true)).called(1);
        verify(() => mockController.loadCard(1, consent: any(named: 'consent'))).called(1);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'pending is neutral support guidance with no automatic charge or extra read',
      (tester) async {
        when(
          () => mockController.loadCard(1.0, consent: any(named: 'consent')),
        ).thenAnswer((_) async => PaymentResult.pending);
        await tester.pumpWidget(createWidget());
        await openLoadCardDialog(tester);
        await tapPay(tester);
        final dialog = find.byType(AlertDialog);
        expect(find.text('Payment verification pending'), findsOneWidget);
        expect(
          find.textContaining('contact Clean Stream support'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.byIcon(Icons.check_circle),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: dialog, matching: find.byIcon(Icons.error)),
          findsNothing,
        );
        expect(find.textContaining('update shortly'), findsNothing);
        expect(find.textContaining('refunded'), findsNothing);
        await tester.pump(const Duration(minutes: 2));
        verify(() => mockController.loadCard(1.0, consent: any(named: 'consent'))).called(1);
        verifyNever(() => mockController.fetchTransactions());
      },
    );

    testWidgets('late result after unmount cannot show success or refetch', (
      tester,
    ) async {
      final payment = Completer<PaymentResult>();
      when(
        () => mockController.loadCard(1.0, consent: any(named: 'consent')),
      ).thenAnswer((_) => payment.future);
      await tester.pumpWidget(createWidget());
      await openLoadCardDialog(tester);
      await tapPay(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      payment.complete(PaymentResult.success);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      verifyNever(() => mockController.fetchTransactions());
      verifyNever(() => mockController.dispose());
    });

    testWidgets(
      'late result from a changed account cannot show a payment dialog',
      (tester) async {
        final payment = Completer<PaymentResult>();
        when(
          () => mockController.loadCard(1.0, consent: any(named: 'consent')),
        ).thenAnswer((_) => payment.future);
        await tester.pumpWidget(createWidget());
        await openLoadCardDialog(tester);
        await tapPay(tester);
        when(() => mockController.accountEpoch).thenReturn(2);
        payment.complete(PaymentResult.success);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        verifyNever(() => mockController.fetchTransactions());
      },
    );

    testWidgets(
      'same-scope refresh preserves wallet element and scroll position',
      (tester) async {
        final listeners = <VoidCallback>[];
        when(() => mockController.addListener(any())).thenAnswer((call) {
          listeners.add(call.positionalArguments.single as VoidCallback);
        });
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();
        final card = tester.element(find.byType(WalletPassCard));
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -90),
        );
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final offset = scroll.position.pixels;
        when(() => mockController.isRefreshing).thenReturn(true);
        for (final listener in listeners) {
          listener();
        }
        await tester.pump();
        expect(tester.element(find.byType(WalletPassCard)), same(card));
        expect(scroll.position.pixels, offset);
        when(
          () => mockController.errorMessage,
        ).thenReturn('Failed to fetch balance');
        when(() => mockController.isRefreshing).thenReturn(false);
        for (final listener in listeners) {
          listener();
        }
        await tester.pump();
        expect(tester.element(find.byType(WalletPassCard)), same(card));
        expect(scroll.position.pixels, offset);
        expect(
          find.textContaining('Showing the last loaded balance'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'account mismatch masks wallet and history immediately on rebuild',
      (tester) async {
        final listeners = <VoidCallback>[];
        when(() => mockController.addListener(any())).thenAnswer((call) {
          listeners.add(call.positionalArguments.single as VoidCallback);
        });
        when(
          () => mockController.recentTransactions,
        ).thenReturn(['Old account entry']);
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();
        when(() => mockController.isCurrentAccount).thenReturn(false);
        for (final listener in listeners) {
          listener();
        }
        await tester.pump();
        expect(find.byType(WalletPassCard), findsNothing);
        expect(find.text('Old account entry'), findsNothing);
        expect(find.text('Wallet balance unavailable'), findsOneWidget);
      },
    );

    testWidgets('calls loadCard with correct amount on Pay tap', (
      tester,
    ) async {
      when(
        () => mockController.loadCard(any(), consent: any(named: 'consent')),
      ).thenAnswer((_) async => PaymentResult.success);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await openLoadCardDialog(tester);
      await tapPay(tester);

      verify(() => mockController.loadCard(1.0, consent: any(named: 'consent'))).called(1);
    });

    testWidgets('shows success dialog on successful payment', (tester) async {
      when(
        () => mockController.loadCard(any(), consent: any(named: 'consent')),
      ).thenAnswer((_) async => PaymentResult.success);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await openLoadCardDialog(tester);
      await tapPay(tester);

      expect(find.text('Payment Successful!'), findsOneWidget);
      expect(
        find.text(
          'Thank you! Your payment of \$1.00 was processed successfully.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'does not refetch transactions again after successful payment',
      (tester) async {
        when(
          () => mockController.loadCard(any(), consent: any(named: 'consent')),
        ).thenAnswer((_) async => PaymentResult.success);

        await tester.pumpWidget(createWidget());
        await tester.pump();

        await openLoadCardDialog(tester);
        await tapPay(tester);

        verifyNever(() => mockController.fetchTransactions());
      },
    );

    testWidgets('shows canceled dialog when payment is canceled', (
      tester,
    ) async {
      when(
        () => mockController.loadCard(any(), consent: any(named: 'consent')),
      ).thenAnswer((_) async => PaymentResult.canceled);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await openLoadCardDialog(tester);
      await tapPay(tester);

      expect(find.text('Payment Canceled'), findsOneWidget);
      expect(find.text('Payment of \$1.00 was canceled.'), findsOneWidget);
    });

    testWidgets('shows failed dialog when payment fails', (tester) async {
      when(
        () => mockController.loadCard(any(), consent: any(named: 'consent')),
      ).thenAnswer((_) async => PaymentResult.failed);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await openLoadCardDialog(tester);
      await tapPay(tester);

      expect(find.text('Payment Failed'), findsOneWidget);
      expect(
        find.text(
          'An error occurred while processing your payment. Please try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('does not call fetchTransactions on failed payment', (
      tester,
    ) async {
      when(
        () => mockController.loadCard(any(), consent: any(named: 'consent')),
      ).thenAnswer((_) async => PaymentResult.failed);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await openLoadCardDialog(tester);
      await tapPay(tester);

      verifyNever(() => mockController.fetchTransactions());
    });

    testWidgets('does not call fetchTransactions on canceled payment', (
      tester,
    ) async {
      when(
        () => mockController.loadCard(any(), consent: any(named: 'consent')),
      ).thenAnswer((_) async => PaymentResult.canceled);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await openLoadCardDialog(tester);
      await tapPay(tester);

      verifyNever(() => mockController.fetchTransactions());
    });

    testWidgets('handles custom amount payment', (tester) async {
      when(
        () => mockController.loadCard(any(), consent: any(named: 'consent')),
      ).thenAnswer((_) async => PaymentResult.success);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await openLoadCardDialog(tester);

      await tester.tap(find.text('\$25'));
      await tester.pumpAndSettle();

      await tapPay(tester);

      verify(() => mockController.loadCard(25.0, consent: any(named: 'consent'))).called(1);
    });

    testWidgets('closes success dialog when Done tapped', (tester) async {
      when(
        () => mockController.loadCard(any(), consent: any(named: 'consent')),
      ).thenAnswer((_) async => PaymentResult.success);

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await openLoadCardDialog(tester);
      await tapPay(tester);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Payment Successful!'), findsNothing);
    });
  });
}
