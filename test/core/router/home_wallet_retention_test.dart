import 'dart:async';

import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'package:clean_stream_laundry_app/features/home/controller.dart';
import 'package:clean_stream_laundry_app/features/home/home.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/header.dart';
import 'package:clean_stream_laundry_app/features/loyalty/controller.dart';
import 'package:clean_stream_laundry_app/features/loyalty/loyalty.dart';
import 'package:clean_stream_laundry_app/features/loyalty/widgets/transaction_list.dart';
import 'package:clean_stream_laundry_app/features/settings/settings.dart';
import 'package:clean_stream_laundry_app/features/settings/widgets/notification_lead.dart';
import 'package:clean_stream_laundry_app/features/start_machine/start_machine.dart';
import 'package:clean_stream_laundry_app/features/widgets/navigation_bar.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_ledger_entry.dart';
import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/home/mocks.dart';
import '../../features/loading/mocks.dart' show MockAppLinks;
import '../../features/loyalty/mocks.dart' show MockPaymentProcessor;
import '../../features/settings/mocks.dart'
    show MockThemeManager, MockTransactionService;

void main() {
  late MockAuthService auth;
  late MockProfileService profiles;
  late MockLocationService locations;
  late MockMachineService machines;
  late MockPaymentProcessor payments;
  late StreamController<bool> events;
  late _Wallet wallet;
  late String? user;
  var profileReads = 0;
  GoRouter? router;
  late MockThemeManager themeManager;

  setUpAll(() => registerFallbackValue(DateTime(2026)));
  setUp(() {
    user = 'A';
    profileReads = 0;
    events = StreamController<bool>.broadcast(sync: true);
    auth = MockAuthService();
    profiles = MockProfileService();
    locations = MockLocationService();
    machines = MockMachineService();
    payments = MockPaymentProcessor();
    wallet = _Wallet(() => user);
    themeManager = MockThemeManager();
    when(() => themeManager.themeData).thenReturn(lightMode);
    when(() => profiles.getNotificationLeadTime()).thenAnswer((_) async => 7);
    when(() => profiles.getCurrentUserRole()).thenAnswer((_) async => 'Customer');
    when(() => auth.getCurrentUserId).thenAnswer((_) => user);
    when(() => auth.onAuthChange).thenAnswer((_) => events.stream);
    when(() => profiles.getUserBalanceById(any())).thenAnswer((call) async {
      profileReads++;
      return {
        'full_name': call.positionalArguments.single,
        'reward_tracker': 0,
      };
    });
    when(() => locations.getLocations()).thenAnswer(
      (_) async => [
        {'id': 1, 'Address': 'One', 'Latitude': 40.0, 'Longitude': -86.0},
        {'id': 2, 'Address': 'Two', 'Latitude': 41.0, 'Longitude': -87.0},
      ],
    );
    when(() => machines.getAvailability(any())).thenAnswer(
      (_) async => MachineAvailability(
        washers: const MachineAvailabilityCount(
          total: 2,
          available: 1,
          busy: 1,
          unknown: 0,
        ),
        dryers: const MachineAvailabilityCount(
          total: 2,
          available: 1,
          busy: 1,
          unknown: 0,
        ),
        configured: true,
        checkedAt: DateTime.now(),
      ),
    );
    GetIt.I.registerSingleton<AuthService>(auth);
    GetIt.I.registerSingleton<ProfileService>(profiles);
    GetIt.I.registerSingleton<LocationService>(locations);
    GetIt.I.registerSingleton<MachineService>(machines);
    GetIt.I.registerSingleton<WalletService>(wallet);
    GetIt.I.registerSingleton<PaymentProcessor>(payments);
    GetIt.I.registerSingleton<TransactionService>(MockTransactionService());
    SharedPreferences.setMockInitialValues({
      'lastSelectedLocation': 'One',
      'locationSelectionMode': 'manual',
    });
  });
  tearDown(() async {
    router?.dispose();
    router = null;
    await events.close();
    await GetIt.I.reset();
  });

  Future<void> mount(
    WidgetTester tester, {
    String path = '/homePage',
    ThemeData? theme,
    Size size = const Size(1200, 900),
    double? textScale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final links = MockAppLinks();
    when(() => links.getInitialLink()).thenAnswer((_) async => null);
    when(() => links.uriLinkStream).thenAnswer((_) => const Stream.empty());
    router = RouterService().createRouter(auth, appLinks: links)..go(path);
    await tester.pumpWidget(ChangeNotifierProvider<ThemeManager>.value(
      value: themeManager,
      child: MaterialApp.router(
      routerConfig: router,
      theme: theme,
      builder: textScale == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  HomePageController home(WidgetTester tester) => tester
      .widget<Header>(find.byType(Header, skipOffstage: false))
      .controller;
  LoyaltyController loyalty(WidgetTester tester) => tester
      .widget<TransactionList>(
        find.byType(TransactionList, skipOffstage: false),
      )
      .controller;
  Future<void> go(WidgetTester tester, String path) async {
    router!.go(path);
    await tester.pumpAndSettle();
  }

  Future<void> tapTab(WidgetTester tester, String name) async {
    await tester.tap(
      find.descendant(of: find.byType(NavBar), matching: find.text(name)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      ['Home', 'Start', 'Wallet', 'Settings'].indexOf(name),
    );
  }

  Future<Completer<PaymentResult>> startFunding(WidgetTester tester) async {
    final payment = Completer<PaymentResult>();
    when(
      () => payments.processPayment(1, 'Loyalty Card'),
    ).thenAnswer((_) => payment.future);
    await tapTab(tester, 'Wallet');
    await tester.ensureVisible(find.text('Load card'));
    await tester.tap(find.text('Load card'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Pay'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Pay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(loyalty(tester).isPaying, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    return payment;
  }

  for (final theme in [lightMode, darkMode]) {
    for (final isHome in [true, false]) {
      testWidgets(
        'compact themed refresh ${theme.brightness.name} ${isHome ? 'Home' : 'Wallet'} preserves content through slow/offline reads',
        (tester) async {
          await mount(
            tester,
            path: isHome ? '/homePage' : '/loyalty',
            theme: theme,
            size: const Size(360, 800),
            textScale: 2,
          );
          addTearDown(() => tester.pumpWidget(const SizedBox()));
          Future<void> capture(String stage) async {
            const output = String.fromEnvironment('REFRESH_RENDER_DIR');
            if (output.isNotEmpty) {
              if (stage == 'loaded') {
                await tester.runAsync(() async {
                  for (final asset in ['assets/Icon.png', 'assets/Slogan.png']) {
                    await precacheImage(
                      AssetImage(asset),
                      tester.element(find.byType(isHome ? HomePage : LoyaltyPage)),
                    );
                  }
                });
                await tester.pump();
              }
              await expectLater(
                find.byType(MaterialApp),
                matchesGoldenFile(Uri.file(
                  '$output/${theme.brightness.name}-${isHome ? 'home' : 'wallet'}-$stage.png',
                )),
              );
            }
          }
          await capture('loaded');
          final page = find.byType(isHome ? HomePage : LoyaltyPage);
          final pageState = tester.state(page);
          final balance = find.text(r'$12.50').first;
          final balanceElement = tester.element(balance);
          Future<void> refresh() => isHome
              ? home(tester).refresh()
              : loyalty(tester).refresh();
          bool loading() => isHome
              ? home(tester).isLoading
              : loyalty(tester).isLoading;
          final reads = wallet.balanceReads;
          final delayed = Completer<WalletBalance>();
          wallet.nextBalance = delayed.future;
          final pending = refresh();
          for (final elapsed in [0, 16, 100, 1000]) {
            await tester.pump(Duration(milliseconds: elapsed));
            expect(loading(), isFalse);
            expect(tester.state(page), same(pageState));
            expect(tester.element(balance), same(balanceElement));
            expect(find.byType(AlertDialog), findsNothing);
          }
          await capture('refreshing');
          delayed.completeError(StateError('synthetic offline'));
          await pending;
          await tester.pumpAndSettle();
          expect(tester.state(page), same(pageState));
          expect(tester.element(balance), same(balanceElement));
          expect(find.textContaining('Showing the last loaded balance.'),
              findsOneWidget);
          await capture('offline');
          await tester.pump(const Duration(seconds: 31));
          expect(wallet.balanceReads, reads + 1,
              reason: 'No periodic retry while the user stays on the page');
          wallet.balanceCents = 1625;
          await refresh();
          await tester.pumpAndSettle();
          expect(find.text(r'$16.25'), findsWidgets);
          expect(find.text(r'$12.50'), findsNothing);
          expect(tester.state(page), same(pageState));
          expect(wallet.balanceReads, reads + 2);
          expect(wallet.writes, 0);
          verifyNever(() => payments.processPayment(any(), any()));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'actual router lazily retains both controllers, map, selection and expanded scroll',
    (tester) async {
      await mount(tester);
      final homeState = tester.state(find.byType(HomePage));
      final homeNav = tester.state(find.byType(BottomNavigationBar));
      final homeController = home(tester);
      final map = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      homeController.selectLocation('Two');
      await tester.pumpAndSettle();
      final camera = map.camera.center;
      expect(find.byType(LoyaltyPage, skipOffstage: false), findsNothing);
      expect(wallet.balanceReads, 1);
      expect(wallet.ledgerReads, 0);
      await tapTab(tester, 'Wallet');
      final walletState = tester.state(find.byType(LoyaltyPage));
      final walletNav = tester.state(find.byType(BottomNavigationBar));
      final walletController = loyalty(tester);
      walletController.toggleTransactionView();
      await tester.pumpAndSettle();
      final scrollFinder = find
          .descendant(
            of: find
                .descendant(
                  of: find.byType(LoyaltyPage),
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
            matching: find.byType(Scrollable),
          )
          .first;
      final scroll = tester.state<ScrollableState>(scrollFinder);
      scroll.position.jumpTo(100);
      await tester.pump();
      final offset = scroll.position.pixels;
      expect(offset, greaterThan(0));
      final reads = (profileReads, wallet.balanceReads, wallet.ledgerReads);
      await tapTab(tester, 'Home');
      expect(tester.state(find.byType(HomePage)), same(homeState));
      expect(tester.state(find.byType(BottomNavigationBar)), same(homeNav));
      expect(home(tester), same(homeController));
      expect(homeController.selectedName, 'Two');
      expect(
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController,
        same(map),
      );
      expect(map.camera.center, camera);
      await tapTab(tester, 'Wallet');
      expect(tester.state(find.byType(LoyaltyPage)), same(walletState));
      expect(tester.state(find.byType(BottomNavigationBar)), same(walletNav));
      expect(loyalty(tester), same(walletController));
      expect(walletController.showPastTransactions, isTrue);
      expect(scroll.position.pixels, offset);
      expect((profileReads, wallet.balanceReads, wallet.ledgerReads), reads);
      verifyNever(() => payments.processPayment(any(), any()));
      expect(wallet.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final (completeWhileHomeVisible, result) in [
    (false, PaymentResult.success),
    (true, PaymentResult.success),
    (false, PaymentResult.pending),
    (true, PaymentResult.pending),
  ]) {
    testWidgets(
      'funding freshness: completion while Home visible=$completeWhileHomeVisible, $result',
      (tester) async {
        await mount(tester);
        addTearDown(() => tester.pumpWidget(const SizedBox()));
        tester.view.physicalSize = const Size(500, 640);
        await tester.pumpAndSettle();
        final homeState = tester.state(find.byType(HomePage));
        final homeController = home(tester);
        final header = tester.element(find.byType(Header));
        homeController.selectLocation('Two');
        await tester.pumpAndSettle();
        final map = tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!;
        final camera = map.camera.center;
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find
                    .descendant(
                      of: find.byType(HomePage),
                      matching: find.byType(SingleChildScrollView),
                    )
                    .first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        scroll.position.jumpTo(100);
        await tester.pumpAndSettle();
        final offset = scroll.position.pixels;
        expect(offset, greaterThan(0));
        expect(homeController.balance!['balance'], 12.50);

        final payment = await startFunding(tester);
        final walletController = loyalty(tester);
        if (completeWhileHomeVisible) await tapTab(tester, 'Home');
        expect(
          homeController.balance!['balance'],
          12.50,
          reason: 'Starting a payment must not optimistically credit Home',
        );

        // The service response, not submitted dollars, determines the new value.
        final homeRead = Completer<WalletBalance>();
        wallet.balanceResponses[4] = homeRead.future;
        wallet.balanceCents = 1625;
        payment.complete(result);
        await tester.pumpAndSettle();
        expect(walletController.userBalance, 16.25);
        if (!completeWhileHomeVisible) {
          expect(wallet.balanceReads, 3, reason: 'Hidden Home defers its read');
          expect(homeController.isRefreshing, isFalse);
          if (result == PaymentResult.pending) {
            expect(find.text('Payment verification pending'), findsOneWidget);
            expect(find.text('Payment Successful!'), findsNothing);
          }
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          await tapTab(tester, 'Home');
        }
        expect(tester.state(find.byType(HomePage)), same(homeState));
        expect(tester.element(find.byType(Header)), same(header));
        expect(home(tester), same(homeController));
        expect(homeController.selectedName, 'Two');
        expect(map.camera.center, camera);
        expect(scroll.position.pixels, offset);
        expect(homeController.isLoading, isFalse);
        expect(homeController.isRefreshing, isTrue);
        expect(homeController.balance!['balance'], 12.50);
        expect(find.text('\$12.50'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(wallet.balanceReads, 4);
        homeRead.complete(wallet.balance());
        await tester.pumpAndSettle();
        expect(homeController.isRefreshing, isFalse);
        expect(tester.state(find.byType(HomePage)), same(homeState));
        expect(tester.element(find.byType(Header)), same(header));
        expect(homeController.selectedName, 'Two');
        expect(map.camera.center, camera);
        expect(scroll.position.pixels, offset);
        verify(() => payments.processPayment(1, 'Loyalty Card')).called(1);
        printOnFailure(
          'authoritative Wallet=${walletController.userBalance}, retained Home=${homeController.balance}, balance reads=${wallet.balanceReads}',
        );
        expect(
          homeController.balance!['balance'],
          16.25,
          reason:
              'A same-account write must quietly invalidate Home before the 30-second no-write TTL',
        );
        expect(find.text('\$16.25'), findsOneWidget);
        await tapTab(tester, 'Wallet');
        await tapTab(tester, 'Home');
        expect(wallet.balanceReads, 4);
        expect(wallet.writes, 0);
      },
    );
  }

  testWidgets(
    'funding invalidation waits for the older Home read and coalesces',
    (tester) async {
      await mount(tester);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final controller = home(tester);
      await tapTab(tester, 'Wallet');
      await tapTab(tester, 'Home');
      final oldBalance = wallet.balance();
      final oldRead = Completer<WalletBalance>();
      wallet.nextBalance = oldRead.future;
      final oldRefresh = controller.refresh();
      await tester.pump();
      expect(wallet.balanceReads, 3);
      final payment = await startFunding(tester);
      wallet.balanceCents = 1625;
      payment.complete(PaymentResult.success);
      await tester.pumpAndSettle();
      expect(loyalty(tester).userBalance, 16.25);
      expect(controller.balance!['balance'], 12.50);
      expect(wallet.balanceReads, 4);
      final duplicateInvalidation = controller.refreshAfterWalletActivity();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tapTab(tester, 'Home');
      expect(wallet.balanceReads, 4);
      final postWriteRead = Completer<WalletBalance>();
      wallet.balanceResponses[5] = postWriteRead.future;
      oldRead.complete(oldBalance);
      await oldRefresh;
      await tester.pumpAndSettle();
      expect(wallet.balanceReads, 5);
      expect(controller.balance!['balance'], 12.50);
      expect(controller.isRefreshing, isTrue);
      postWriteRead.complete(wallet.balance());
      await duplicateInvalidation;
      await tester.pumpAndSettle();
      expect(controller.balance!['balance'], 16.25);
      await tapTab(tester, 'Wallet');
      await tapTab(tester, 'Home');
      expect(wallet.balanceReads, 5);
      verify(() => payments.processPayment(1, 'Loyalty Card')).called(1);
    },
  );

  testWidgets(
    'post-funding Home error keeps stale data without automatic retry',
    (tester) async {
      await mount(tester);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final controller = home(tester);
      controller.selectLocation('Two');
      final payment = await startFunding(tester);
      await tapTab(tester, 'Home');
      final read = Completer<WalletBalance>();
      wallet.balanceResponses[4] = read.future;
      wallet.balanceCents = 1625;
      payment.complete(PaymentResult.pending);
      await tester.pumpAndSettle();
      expect(loyalty(tester).userBalance, 16.25);
      expect(controller.balance!['balance'], 12.50);
      read.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(controller.balance!['balance'], 12.50);
      expect(controller.selectedName, 'Two');
      expect(controller.isLoading, isFalse);
      expect(controller.isRefreshing, isFalse);
      expect(controller.errorMessage, 'Unable to refresh wallet balance');
      expect(
        find.textContaining('Showing the last loaded balance.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(seconds: 31));
      expect(wallet.balanceReads, 4);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(controller.balance!['balance'], 16.25);
      expect(controller.errorMessage, isNull);
      expect(wallet.balanceReads, 5);
      verify(() => payments.processPayment(1, 'Loyalty Card')).called(1);
      expect(wallet.writes, 0);
    },
  );

  testWidgets(
    'failed Wallet reconciliation still invalidates visible Home for pending',
    (tester) async {
      await mount(tester);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final payment = await startFunding(tester);
      await tapTab(tester, 'Home');
      final read = Completer<WalletBalance>();
      wallet.balanceResponses[3] = read.future;
      wallet.balanceCents = 1625;
      payment.complete(PaymentResult.pending);
      await tester.pumpAndSettle();
      expect(wallet.balanceReads, 3);
      expect(home(tester).balance!['balance'], 12.50);
      read.completeError(StateError('reconciliation read failed'));
      await tester.pumpAndSettle();
      expect(loyalty(tester).userBalance, 12.50);
      expect(home(tester).balance!['balance'], 16.25);
      expect(wallet.balanceReads, 4);
      expect(find.byType(AlertDialog), findsNothing);
      verify(() => payments.processPayment(1, 'Loyalty Card')).called(1);
      expect(wallet.writes, 0);
    },
  );

  for (final result in [PaymentResult.canceled, PaymentResult.failed]) {
    testWidgets('non-settling $result does not invalidate fresh Home', (
      tester,
    ) async {
      await mount(tester);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final payment = await startFunding(tester);
      await tapTab(tester, 'Home');
      payment.complete(result);
      await tester.pumpAndSettle();
      await tapTab(tester, 'Wallet');
      await tapTab(tester, 'Home');
      expect(wallet.balanceReads, 2);
      expect(home(tester).balance!['balance'], 12.50);
      expect(find.byType(AlertDialog), findsNothing);
      verify(() => payments.processPayment(1, 'Loyalty Card')).called(1);
    });
  }

  for (final change in ['A/B/A', 'signout/login', 'dispose']) {
    testWidgets('route callback rejects delayed reconciliation after $change', (
      tester,
    ) async {
      await mount(tester);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final oldHome = tester.state(find.byType(HomePage));
      final payment = await startFunding(tester);
      await tapTab(tester, 'Home');
      final read = Completer<WalletBalance>();
      wallet.balanceResponses[3] = read.future;
      payment.complete(PaymentResult.success);
      await tester.pumpAndSettle();
      expect(wallet.balanceReads, 3);
      wallet.balanceCents = 2700;
      if (change == 'dispose') {
        await go(tester, '/legal/privacy');
        expect(oldHome.mounted, isFalse);
        await go(tester, '/homePage');
        expect(tester.state(find.byType(HomePage)), isNot(same(oldHome)));
      } else {
        for (final next
            in change == 'A/B/A' ? ['B', 'A'] : <String?>[null, 'A']) {
          user = next;
          events.add(next != null);
          expect(home(tester).balance, isNull);
          await tester.pumpAndSettle();
        }
      }
      final reads = wallet.balanceReads;
      expect(home(tester).balance!['balance'], 27.00);
      read.complete(wallet.balance());
      await tester.pumpAndSettle();
      expect(wallet.balanceReads, reads);
      expect(home(tester).balance!['balance'], 27.00);
      expect(find.byType(AlertDialog), findsNothing);
      verify(() => payments.processPayment(1, 'Loyalty Card')).called(1);
    });

    testWidgets('queued Home invalidation cannot cross $change', (
      tester,
    ) async {
      final controller = HomePageController();
      await controller.init();
      final oldBalance = wallet.balance();
      final read = Completer<WalletBalance>();
      wallet.nextBalance = read.future;
      final oldRefresh = controller.refresh();
      await tester.pump();
      final invalidation = controller.refreshAfterWalletActivity();
      controller.setActive(false);
      wallet.balanceCents = 2700;
      if (change == 'dispose') {
        controller.dispose();
      } else {
        for (final next
            in change == 'A/B/A' ? ['B', 'A'] : <String?>[null, 'A']) {
          user = next;
          events.add(next != null);
          expect(controller.balance, isNull);
        }
        controller.setActive(true);
        await controller.refresh();
        expect(controller.balance!['balance'], 27.00);
      }
      final reads = wallet.balanceReads;
      read.complete(oldBalance);
      await Future.wait([oldRefresh, invalidation]);
      if (change != 'dispose') {
        await controller.refresh(ifStale: true);
        expect(controller.balance!['balance'], 27.00);
        controller.dispose();
      }
      expect(wallet.balanceReads, reads);
    });
  }

  testWidgets(
    'Home hidden invalidates A/B/A and signout/same-user login without reads',
    (tester) async {
      await mount(tester);
      final hidden = home(tester);
      await go(tester, '/loyalty');
      final epoch = hidden.accountEpoch;
      for (final next in <String?>['B', 'A', null, 'A']) {
        final before = profileReads;
        user = next;
        events.add(next != null);
        expect(hidden.balance, isNull);
        expect(hidden.username, isNull);
        await tester.pumpAndSettle();
        expect(profileReads - before, next == null ? 0 : 1);
      }
      expect(hidden.accountEpoch, epoch + 4);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      final reads = profileReads;
      await go(tester, '/homePage');
      expect(profileReads, reads + 1);
      expect(hidden.username, 'A');
      expect(home(tester), same(hidden));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Wallet hidden clears history and A/B/A cannot restore an old account snapshot',
    (tester) async {
      await mount(tester, path: '/loyalty');
      final hidden = loyalty(tester);
      await go(tester, '/homePage');
      for (final next in <String?>['B', 'A', null, 'A']) {
        final ledgerReads = wallet.ledgerReads;
        final reads = profileReads;
        user = next;
        events.add(next != null);
        expect(hidden.userBalance, isNull);
        expect(hidden.recentTransactions, isEmpty);
        await tester.pumpAndSettle();
        expect(wallet.ledgerReads, ledgerReads);
        expect(profileReads - reads, next == null ? 0 : 1);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      final reads = (profileReads, wallet.ledgerReads);
      await go(tester, '/loyalty');
      expect(profileReads, reads.$1 + 1);
      expect(wallet.ledgerReads, reads.$2 + 2);
      expect(loyalty(tester), same(hidden));
      expect(hidden.userName, 'A');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'same-path repeated Add funds is one shot; restored history has no automatic form or charge',
    (tester) async {
      final history = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
            if (call.method == 'routeInformationUpdated') {
              history.add(call.arguments as Map<dynamic, dynamic>);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.navigation, null),
      );
      await mount(tester, path: '/loyalty');
      final state = tester.state(find.byType(LoyaltyPage));
      for (var i = 0; i < 2; i++) {
        await go(tester, '/loyalty?loadCard=true&tag=one&tag=two');
        expect(find.text('Load Loyalty Card'), findsOneWidget);
        expect(router!.routeInformationProvider.value.uri.queryParametersAll, {
          'tag': ['one', 'two'],
        });
        expect(history.last['uri'], '/loyalty?tag=one&tag=two');
        expect(
          history.last['replace'],
          isTrue,
          reason:
              'The browser entry must be replaced, not append a replayable loadCard entry',
        );
        await go(tester, '/loyalty?loadCard=true&tag=one&tag=two');
        expect(find.text('Load Loyalty Card'), findsOneWidget);
        Navigator.of(tester.element(find.byType(AlertDialog))).pop();
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(LoyaltyPage)), same(state));
      }
      final walletHistory = history.last;
      await go(tester, '/homePage');
      final homeHistory = history.last;
      // Restore the actual encoded history entries emitted to the engine.
      for (final entry in [walletHistory, homeHistory, walletHistory]) {
        await router!.routeInformationProvider.didPushRouteInformation(
          RouteInformation(
            uri: Uri.parse(entry['uri'] as String),
            state: entry['state'],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Load Loyalty Card'), findsNothing);
      }
      expect(tester.state(find.byType(LoyaltyPage)), same(state));
      verifyNever(() => payments.processPayment(any(), any()));
      expect(wallet.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account change dismisses an open form and does not replay it on return',
    (tester) async {
      await mount(tester, path: '/loyalty?loadCard=true');
      expect(find.text('Load Loyalty Card'), findsOneWidget);
      user = 'B';
      events.add(true);
      await tester.pumpAndSettle();
      expect(find.text('Load Loyalty Card'), findsNothing);
      await go(tester, '/homePage');
      await go(tester, '/loyalty');
      expect(find.text('Load Loyalty Card'), findsNothing);
      verifyNever(() => payments.processPayment(any(), any()));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('all four tabs retain loaded content without another initial load', (
    tester,
  ) async {
    await mount(tester);
    final oldHome = home(tester);
    final mapState = tester.state(find.byType(FlutterMap));
    await tapTab(tester, 'Wallet');
    final oldWallet = loyalty(tester);
    await tapTab(tester, 'Settings');
    final settingsState = tester.state(find.byType(Settings));
    final settingsScroll = tester.state<ScrollableState>(
      find.descendant(of: find.byType(Settings), matching: find.byType(Scrollable)),
    );
    settingsScroll.position.jumpTo(80);
    await tester.pump();
    expect(tester.widget<NotificationLead>(find.byType(NotificationLead)).value, 7);
    await tapTab(tester, 'Start');
    final startState = tester.state(find.byType(StartPage));
    final reads = (profileReads, wallet.balanceReads, wallet.ledgerReads);
    for (var cycle = 0; cycle < 2; cycle++) {
      for (final path in ['/homePage', '/loyalty', '/settings']) {
        router!.go(path);
        await tester.pump();
        expect(find.text('Loading wallet...'), findsNothing);
        expect(find.text('Loading...'), findsNothing);
        expect(find.text('Checking availability…'), findsNothing);
        expect(home(tester), same(oldHome));
        expect(loyalty(tester), same(oldWallet));
        await tester.pumpAndSettle();
      }
    }
    expect(profileReads, reads.$1);
    expect(wallet.balanceReads, reads.$2);
    expect(wallet.ledgerReads, reads.$3);
    expect(tester.state(find.byType(Settings)), same(settingsState));
    expect(settingsScroll.position.pixels, 80);
    expect(tester.widget<NotificationLead>(find.byType(NotificationLead)).value, 7);
    expect(tester.state(find.byType(FlutterMap, skipOffstage: false)), same(mapState));
    verify(() => profiles.getNotificationLeadTime()).called(1);
    verify(() => locations.getLocations()).called(1);
    verify(() => machines.getAvailability(1)).called(1);
    await tapTab(tester, 'Start');
    expect(tester.state(find.byType(StartPage)), same(startState));
    expect(profileReads, reads.$1 + 1, reason: 'Start rechecks its door balance');
    verifyNever(() => payments.processPayment(any(), any()));
    expect(wallet.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving the four-branch shell disposes retained state', (
    tester,
  ) async {
    await mount(tester);
    final oldHome = tester.state(find.byType(HomePage));
    await go(tester, '/loyalty');
    final oldWallet = tester.state(find.byType(LoyaltyPage));
    await go(tester, '/legal/privacy');
    expect(oldHome.mounted, isFalse);
    expect(oldWallet.mounted, isFalse);
    final reads = profileReads;
    user = 'B';
    events.add(true);
    await tester.pumpAndSettle();
    expect(profileReads, reads);
    await go(tester, '/homePage');
    expect(tester.state(find.byType(HomePage)), isNot(same(oldHome)));
    expect(find.byType(LoyaltyPage, skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final path in [
    '/legal/loyalty-card',
    '/paymentPage?machineId=synthetic',
    '/pay?machine=synthetic&terminal=12',
  ]) {
    testWidgets(
      'standalone route stays outside the shell with unchanged URI: $path',
      (tester) async {
        user = null;
        final links = MockAppLinks();
        router = RouterService().createRouter(auth, appLinks: links);
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        router!.go(path);
        final matches = await router!.routeInformationParser
            .parseRouteInformationWithDependencies(
              router!.routeInformationProvider.value,
              context,
            );
        expect(matches.isError, isFalse);
        expect(matches.uri, Uri.parse(path));
        expect(matches.matches.whereType<ShellRouteMatch>(), isEmpty);
        expect(wallet.balanceReads, 0);
        expect(wallet.writes, 0);
        verifyNever(() => payments.processPayment(any(), any()));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final isHome in [true, false]) {
    testWidgets(
      '${isHome ? 'Home' : 'Wallet'} active input defers auth and coalesces stale activation',
      (tester) async {
        var now = DateTime(2026, 9, 29);
        final homeController = isHome
            ? HomePageController(now: () => now)
            : null;
        final walletController = isHome
            ? null
            : LoyaltyController(now: () => now);
        void active(bool value) => isHome
            ? homeController!.setActive(value)
            : walletController!.setActive(value);
        Future<void> refresh() => isHome
            ? homeController!.refresh(ifStale: true)
            : walletController!.refresh(ifStale: true);
        active(false);
        await (isHome
            ? homeController!.init()
            : walletController!.initialize());
        for (final next in <String?>[null, 'A', 'B', 'A']) {
          user = next;
          events.add(next != null);
        }
        expect(profileReads, 0);
        expect(wallet.balanceReads, 0);
        verifyNever(() => locations.getLocations());
        active(true);
        await Future.wait([refresh(), refresh()]);
        expect(profileReads, 1);
        if (isHome) verify(() => locations.getLocations()).called(1);
        active(false);
        now = now.add(const Duration(seconds: 31));
        await refresh();
        expect(profileReads, 1);
        active(true);
        await Future.wait([refresh(), refresh()]);
        expect(profileReads, 2);
        await refresh();
        expect(profileReads, 2);
        homeController?.dispose();
        walletController?.dispose();
        user = 'B';
        events.add(true);
        active(true);
        await refresh();
        expect(profileReads, 2);
        await tester.pump();
      },
    );
  }

  testWidgets(
    'hidden Wallet does not start ledger reads after an earlier balance request completes',
    (tester) async {
      final read = Completer<WalletBalance>();
      wallet.nextBalance = read.future;
      final controller = LoyaltyController();
      final initial = controller.initialize();
      await tester.pump();
      controller.setActive(false);
      read.complete(wallet.balance());
      await initial;
      expect(wallet.ledgerReads, 0);
      controller.setActive(true);
      await controller.refresh(ifStale: true);
      expect(wallet.balanceReads, 2);
      expect(wallet.ledgerReads, 2);
      controller.dispose();
    },
  );

  for (final isHome in [true, false]) {
    testWidgets(
      '${isHome ? 'Home' : 'Wallet'} rejects late A data after hidden A/B/A',
      (tester) async {
        final read = Completer<WalletBalance>();
        wallet.nextBalance = read.future;
        final homeController = isHome ? HomePageController() : null;
        final walletController = isHome ? null : LoyaltyController();
        final initial = isHome
            ? homeController!.init()
            : walletController!.initialize();
        await tester.pump();
        homeController?.setActive(false);
        walletController?.setActive(false);
        for (final next in ['B', 'A']) {
          user = next;
          events.add(true);
        }
        read.complete(
          const WalletBalance(
            walletAccountId: 'old-A',
            status: 'active',
            paidBalanceCents: 9900,
            promoBalanceCents: 0,
            totalBalanceCents: 9900,
          ),
        );
        await initial;
        expect(homeController?.balance, isNull);
        expect(walletController?.userBalance, isNull);
        expect(wallet.ledgerReads, 0);
        expect(wallet.balanceReads, 1);
        homeController?.setActive(true);
        walletController?.setActive(true);
        await (isHome
            ? homeController!.refresh(ifStale: true)
            : walletController!.refresh(ifStale: true));
        expect(
          isHome
              ? homeController!.balance!['balance']
              : walletController!.userBalance,
          12.5,
        );
        homeController?.dispose();
        walletController?.dispose();
      },
    );
  }

  testWidgets(
    'hidden payment cannot reconcile into A after an A/B/A session change',
    (tester) async {
      final completion = Completer<PaymentResult>();
      when(
        () => payments.processPayment(5, 'Loyalty Card'),
      ).thenAnswer((_) => completion.future);
      final controller = LoyaltyController();
      await controller.initialize();
      final payment = controller.loadCard(5);
      controller.setActive(false);
      for (final next in ['B', 'A']) {
        user = next;
        events.add(true);
      }
      completion.complete(PaymentResult.success);
      expect(await payment, PaymentResult.pending);
      expect(controller.userBalance, isNull);
      expect(wallet.balanceReads, 1);
      expect(wallet.ledgerReads, 2);
      verify(() => payments.processPayment(5, 'Loyalty Card')).called(1);
      controller.dispose();
    },
  );

  for (final result in [PaymentResult.success, PaymentResult.pending]) {
    testWidgets(
      'hidden payment completion $result keeps exactly one authoritative refresh',
      (tester) async {
        final completion = Completer<PaymentResult>();
        when(
          () => payments.processPayment(5, 'Loyalty Card'),
        ).thenAnswer((_) => completion.future);
        final controller = LoyaltyController();
        await controller.initialize();
        final payment = controller.loadCard(5);
        controller.setActive(false);
        completion.complete(result);
        expect(await payment, result);
        expect(profileReads, 2);
        expect(wallet.balanceReads, 2);
        expect(wallet.ledgerReads, 4);
        controller.setActive(true);
        await controller.refresh(ifStale: true);
        expect(wallet.balanceReads, 2);
        verify(() => payments.processPayment(5, 'Loyalty Card')).called(1);
        controller.dispose();
      },
    );
  }

  for (final change in ['A/B/A', 'signout', 'dispose']) {
    testWidgets(
      'delayed mandatory reconciliation rejects $change while hidden',
      (tester) async {
        when(
          () => payments.processPayment(5, 'Loyalty Card'),
        ).thenAnswer((_) async => PaymentResult.success);
        final controller = LoyaltyController();
        await controller.initialize();
        final read = Completer<WalletBalance>();
        wallet.nextBalance = read.future;
        final payment = controller.loadCard(5);
        controller.setActive(false);
        await tester.pump();
        expect(wallet.balanceReads, 2);
        expect(wallet.ledgerReads, 2);
        if (change == 'dispose') {
          controller.dispose();
        } else {
          for (final next in change == 'A/B/A' ? ['B', 'A'] : <String?>[null]) {
            user = next;
            events.add(next != null);
          }
        }
        read.complete(wallet.balance());
        expect(await payment, PaymentResult.pending);
        expect(wallet.balanceReads, 2);
        expect(wallet.ledgerReads, 2);
        if (change != 'dispose') {
          expect(controller.userBalance, isNull);
          controller.dispose();
        }
        verify(() => payments.processPayment(5, 'Loyalty Card')).called(1);
      },
    );
  }

  testWidgets(
    'activation joins delayed hidden mandatory reconciliation without an extra read',
    (tester) async {
      when(
        () => payments.processPayment(5, 'Loyalty Card'),
      ).thenAnswer((_) async => PaymentResult.pending);
      final controller = LoyaltyController();
      await controller.initialize();
      final read = Completer<WalletBalance>();
      wallet.nextBalance = read.future;
      var completed = false;
      final payment = controller
          .loadCard(5)
          .whenComplete(() => completed = true);
      controller.setActive(false);
      await tester.pump();
      expect(completed, isFalse);
      expect(wallet.balanceReads, 2);
      controller.setActive(true);
      final activation = controller.refresh(ifStale: true);
      await tester.pump();
      expect(wallet.balanceReads, 2);
      read.complete(wallet.balance());
      expect(await payment, PaymentResult.pending);
      await activation;
      expect(wallet.ledgerReads, 4);
      expect(wallet.balanceReads, 2);
      verify(() => payments.processPayment(5, 'Loyalty Card')).called(1);
      controller.dispose();
    },
  );
}

class _Wallet implements WalletService {
  _Wallet(this.user);
  final String? Function() user;
  int balanceReads = 0;
  int ledgerReads = 0;
  int writes = 0;
  int balanceCents = 1250;
  Future<WalletBalance>? nextBalance;
  final balanceResponses = <int, Future<WalletBalance>>{};
  WalletBalance balance() => WalletBalance(
    walletAccountId: 'wallet-${user()}',
    status: 'active',
    paidBalanceCents: balanceCents,
    promoBalanceCents: 0,
    totalBalanceCents: balanceCents,
  );
  @override
  Future<WalletBalance> getBalance() {
    balanceReads++;
    final result = nextBalance ?? balanceResponses.remove(balanceReads);
    nextBalance = null;
    return result ?? Future.value(balance());
  }

  @override
  Future<List<WalletLedgerEntry>> getLedger({
    required String userId,
    required String walletAccountId,
    required DateTime since,
    WalletLedgerEntry? before,
    bool rewardsOnly = false,
  }) async {
    ledgerReads++;
    if (rewardsOnly) return [];
    return List.generate(
      25,
      (i) => WalletLedgerEntry(
        id: 100 - i,
        entryType: 'load_paid',
        amountCents: 100 + i,
        paidAmountCents: 100 + i,
        promoAmountCents: 0,
        createdAt: DateTime.now().subtract(Duration(minutes: i)),
      ),
    );
  }

  @override
  Future<void> loadCard(int amountCents) async {
    writes++;
  }

  @override
  Future<List<RefundableTopup>> listRefundableTopups({
    required Session session,
    String? beforeLoadId,
  }) async => [];

  @override
  Future<List<TopupRefund>> listTopupRefunds({
    required Session session,
    TopupRefund? before,
  }) async => [];

  @override
  Future<TopupRefund> requestTopupRefund({
    required Session session,
    required String loadId,
  }) => throw UnsupportedError('Not used by wallet retention tests');

  @override
  Future<Map<String, dynamic>> redeemForMachine({
    required int machineId,
    required int amountCents,
    String? note,
  }) async {
    writes++;
    return {};
  }
}
