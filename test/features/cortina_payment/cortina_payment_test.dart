import 'dart:async';

import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockVendService extends Mock implements CortinaVendService {}

class MockAuthService extends Mock implements AuthService {}

class MockWalletService extends Mock implements WalletService {}

void main() {
  late MockVendService vend;
  late MockWalletService wallet;
  late MockAuthService auth;
  late GoRouter router;
  var paid = false;

  setUpAll(() {
    registerFallbackValue(
      const CortinaVendReference(sessionId: 'session', accessToken: 'access'),
    );
  });

  setUp(() async {
    await GetIt.instance.reset();
    FlutterSecureStorage.setMockInitialValues({});
    GetIt.instance.registerSingleton<CortinaPendingStore>(
      CortinaPendingStore(project: 'https://test.invalid'),
    );
    paid = false;
    vend = MockVendService();
    wallet = MockWalletService();
    auth = MockAuthService();
    GetIt.instance.registerSingleton<CortinaVendService>(vend);
    GetIt.instance.registerSingleton<WalletService>(wallet);
    GetIt.instance.registerSingleton<AuthService>(auth);
    when(() => auth.getCurrentUserId).thenReturn('user');
    when(() => auth.authStateChanges).thenAnswer((_) => const Stream.empty());
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

  for (final theme in [lightMode, darkMode]) {
    testWidgets('${theme.brightness.name} checkout surfaces match their text', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp.router(theme: theme, routerConfig: router));
      await tester.pumpAndSettle();
      final colors = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, isDark ? colors.surface : const Color(0xFFF4F6F8));
      expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor, colors.surface);
      for (final label in ['Credit or debit card', 'Loyalty wallet', 'Card']) {
        final element = tester.element(find.text(label));
        final material = element.findAncestorWidgetOfExactType<Material>()!;
        expect(material.color, colors.surface);
        final foreground = DefaultTextStyle.of(element).style.color!;
        final light = foreground.computeLuminance();
        final dark = material.color!.computeLuminance();
        final contrast = light > dark
            ? (light + 0.05) / (dark + 0.05)
            : (dark + 0.05) / (light + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
      final notice = find.ancestor(
        of: find.text('Choose your cycle at the washer'),
        matching: find.byWidgetPredicate((widget) => widget is Container && widget.decoration is BoxDecoration),
      );
      expect((tester.widget<Container>(notice).decoration! as BoxDecoration).color, colors.surface);
      expect(tester.widget<Icon>(find.byIcon(Icons.tune_rounded)).color,
          isDark ? colors.secondary : const Color(0xFF165F8C));
      await tester.tap(find.text('Loyalty wallet'));
      await tester.pump();
      expect(find.text('Loyalty wallet'), findsNWidgets(2));
      expect(find.text(r'Pay $4.00'), findsOneWidget);
      expect(paid, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${theme.brightness.name} unavailable wallet surface remains distinct', (
      tester,
    ) async {
      when(() => wallet.getBalance()).thenAnswer((_) async => WalletBalance(
        walletAccountId: 'wallet', status: 'active', paidBalanceCents: 0,
        promoBalanceCents: 0, totalBalanceCents: 0,
      ));
      await tester.pumpWidget(MaterialApp.router(theme: theme, routerConfig: router));
      await tester.pumpAndSettle();
      final element = tester.element(find.text('Loyalty wallet'));
      final material = element.findAncestorWidgetOfExactType<Material>()!;
      expect(material.color, theme.brightness == Brightness.dark
          ? theme.colorScheme.surfaceContainerHighest : const Color(0xFFE9EDF0));
      expect(element.findAncestorWidgetOfExactType<InkWell>()!.onTap, isNull);
      expect(find.text('Card'), findsOneWidget);
      expect(paid, isFalse);
    });
  }

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

  testWidgets('account change revokes an open restored success dialog', (tester) async {
    final events = StreamController<AuthState>.broadcast(sync: true);
    when(() => auth.authStateChanges).thenAnswer((_) => events.stream);
    final store = GetIt.instance<CortinaPendingStore>();
    await store.claim(store.scope(accountId: 'user', machineId: 1), const CortinaPendingPayment(
      requestId: 'original-request', method: 'wallet', amountCents: 400,
      reference: CortinaVendReference(sessionId: 'session', accessToken: 'access'),
    ));
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Machine Started'), findsOneWidget);
    when(() => auth.getCurrentUserId).thenReturn('other');
    events.add(AuthState(AuthChangeEvent.signedOut, null));
    await tester.pumpAndSettle();
    expect(find.text('Machine Started'), findsNothing);
    expect(find.text('Payment Unconfirmed'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet page'), findsNothing);
    expect(find.text('Machine payment'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await events.close();
    expect(tester.takeException(), isNull);
  });

  for (final status in ['support_required', 'started', 'refunded']) {
    testWidgets('restored $status uses status only and never optimistic success', (tester) async {
      final store = GetIt.instance<CortinaPendingStore>();
      final scope = store.scope(accountId: 'user', machineId: 1);
      await store.claim(scope, const CortinaPendingPayment(
        requestId: 'original-request', method: 'wallet', amountCents: 400,
        reference: CortinaVendReference(sessionId: 'session', accessToken: 'access'),
      ));
      when(() => vend.status(any())).thenAnswer((_) async => CortinaVendStatus(status: status));
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text(status == 'started' ? 'Machine Started'
        : status == 'refunded' ? 'Vend Canceled' : 'Payment Unconfirmed'), findsOneWidget);
      expect(find.text('Payment Received'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), status == 'started' ? findsOneWidget : findsNothing);
      verify(() => vend.status(any())).called(1);
      verifyNever(() => vend.payWithWallet(
        machineToken: 'token', terminalId: null, uniQr: null,
        amountCents: any(named: 'amountCents'), clientRequestId: any(named: 'clientRequestId'),
      ));
      verifyNever(() => vend.createCardPayment(
        machineToken: 'token', terminalId: null, uniQr: null,
        amountCents: any(named: 'amountCents'), clientRequestId: any(named: 'clientRequestId'),
      ));
      verifyNever(() => vend.confirmCardPayment(any()));
      expect(await store.read(scope), status == 'support_required' ? isNotNull : isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      if (status == 'started') {
        expect(find.text('Wallet page'), findsOneWidget);
      } else {
        expect(find.text('Machine payment'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final status in ['support_required', 'timed_out', 'unknown', 'transport_error']) {
    testWidgets('$status shows unconfirmed support copy and leaves checkout disabled', (tester) async {
      when(() => vend.status(any())).thenAnswer((_) async {
        if (status == 'transport_error') throw StateError('Connection lost');
        return CortinaVendStatus(
          status: status, failureMessage: 'Payment returned. Try again.',
        );
      });
      await pay(tester);
      expect(find.text('Payment Unconfirmed'), findsOneWidget);
      expect(find.text('Payment Received'), findsNothing);
      expect(find.text('Machine Started'), findsNothing);
      expect(find.text('Payment returned. Try again.'), findsNothing);
      expect(find.textContaining('Please contact Clean Stream support'), findsWidgets);
      final dialog = find.byKey(const ValueKey('cortina-result-dialog'));
      expect(find.descendant(of: dialog, matching: find.byIcon(Icons.check_rounded)), findsNothing);
      expect(find.descendant(of: dialog, matching: find.byIcon(Icons.error_outline_rounded)), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Machine payment'), findsOneWidget);
      final payButton = tester.widget<FilledButton>(find.ancestor(
        of: find.text(r'Pay $4.00'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ));
      expect(payButton.onPressed, isNull);
      final cardTile = tester.widget<InkWell>(find.ancestor(
        of: find.text('Credit or debit card'), matching: find.byType(InkWell),
      ));
      expect(cardTile.onTap, isNull);
      verify(() => vend.payWithWallet(
        machineToken: 'token', terminalId: null, uniQr: null,
        amountCents: 400, clientRequestId: any(named: 'clientRequestId'),
      )).called(1);
      expect(tester.takeException(), isNull);
    });
  }
}
