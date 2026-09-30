import 'package:clean_stream_laundry_app/features/cortina_payment/cortina_payment.dart';
import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockVendService extends Mock implements CortinaVendService {}

class MockAuthService extends Mock implements AuthService {}

class MockWalletService extends Mock implements WalletService {}

void main() {
  late MockVendService vend;
  late MockWalletService wallet;
  late GoRouter router;
  var paid = false;

  setUpAll(() {
    registerFallbackValue(
      const CortinaVendReference(sessionId: 'session', accessToken: 'access'),
    );
  });

  setUp(() async {
    await GetIt.instance.reset();
    paid = false;
    vend = MockVendService();
    wallet = MockWalletService();
    final auth = MockAuthService();
    GetIt.instance.registerSingleton<CortinaVendService>(vend);
    GetIt.instance.registerSingleton<WalletService>(wallet);
    GetIt.instance.registerSingleton<AuthService>(auth);
    when(() => auth.getCurrentUserId).thenReturn('user');
    when(
      () => vend.quote(machineToken: 'token', terminalId: null, uniQr: null),
    ).thenAnswer(
      (_) async => const CortinaQuote(
        machineId: 1,
        machineName: 'Washer 1',
        machineType: 'washer',
        washerSizeLabel: '12 kg',
        amountCents: 400,
        dryerDefaultCents: 150,
        dryerOptions: [],
      ),
    );
    when(() => wallet.getBalance()).thenAnswer(
      (_) async => WalletBalance(
        walletAccountId: 'wallet',
        status: 'active',
        paidBalanceCents: paid ? 700 : 1100,
        promoBalanceCents: 0,
        totalBalanceCents: paid ? 700 : 1100,
      ),
    );
    when(
      () => vend.payWithWallet(
        machineToken: 'token',
        terminalId: null,
        uniQr: null,
        amountCents: 400,
        clientRequestId: any(named: 'clientRequestId'),
      ),
    ).thenAnswer((_) async {
      paid = true;
      return const CortinaVendReference(
        sessionId: 'session',
        accessToken: 'access',
      );
    });
    when(
      () => vend.status(any()),
    ).thenAnswer((_) async => const CortinaVendStatus(status: 'started'));
    router = GoRouter(
      initialLocation: '/pay',
      routes: [
        GoRoute(
          path: '/pay',
          builder: (_, _) => const CortinaPaymentPage(
            machineToken: 'token',
            terminalId: null,
            uniQr: null,
          ),
        ),
        GoRoute(
          path: '/loyalty',
          builder: (_, _) => const Scaffold(body: Text('Wallet page')),
        ),
        GoRoute(
          path: '/homePage',
          builder: (_, _) => const Scaffold(body: Text('Home page')),
        ),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    await GetIt.instance.reset();
  });

  Future<void> pay(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text(r'$11.00 available'), findsOneWidget);
    await tester.tap(find.text('Loyalty wallet').first);
    await tester.pump();
    await tester.tap(find.text(r'Pay $4.00'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'success refreshes funds, disables checkout and closes to wallet',
    (tester) async {
      await pay(tester);
      expect(find.text('Machine Started'), findsOneWidget);
      expect(find.text(r'$7.00 available'), findsOneWidget);
      final payButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(r'Pay $4.00'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      expect(payButton.onPressed, isNull);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Machine payment'), findsNothing);
      expect(find.text('Wallet page'), findsOneWidget);
      expect(tester.takeException(), isNull);
      verify(() => wallet.getBalance()).called(2);
    },
  );

  testWidgets(
    'refunded vend stays on checkout instead of navigating as success',
    (tester) async {
      when(() => vend.status(any())).thenAnswer((_) async {
        paid = false;
        return const CortinaVendStatus(status: 'refunded');
      });
      await pay(tester);
      expect(find.text('Vend Canceled'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Machine payment'), findsOneWidget);
      expect(find.text(r'$11.00 available'), findsOneWidget);
      expect(find.text('Wallet page'), findsNothing);
    },
  );
}
