import 'package:clean_stream_laundry_app/features/loyalty/widgets/wallet_pass_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Widget wrapWithRouter(Widget child) {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => child)],
    );

    return MaterialApp.router(routerConfig: router);
  }

  group('WalletPassCard', () {
    test('instantiates correctly', () {
      const walletPass = WalletPassCard(
        username: 'Test Username',
        balance: 12.50,
      );
      expect(walletPass, isA<WalletPassCard>());
    });

    testWidgets('renders the username context', (tester) async {
      await tester.pumpWidget(
        wrapWithRouter(
          const WalletPassCard(username: 'Test Username', balance: 12.50),
        ),
      );

      expect(find.text('For Test Username'), findsOneWidget);
    });

    testWidgets('renders the brand and exact slogan', (tester) async {
      await tester.pumpWidget(
        wrapWithRouter(
          const WalletPassCard(username: 'Test Username', balance: 12.50),
        ),
      );

      expect(find.text('Clean Stream'), findsOneWidget);
      expect(find.text('Where freshness flows.'), findsOneWidget);
      expect(find.byKey(const Key('wallet-pass-slogan')), findsOneWidget);
    });

    testWidgets('renders the available balance', (tester) async {
      await tester.pumpWidget(
        wrapWithRouter(
          const WalletPassCard(username: 'Test Username', balance: 12.50),
        ),
      );

      expect(find.text('Available balance'), findsOneWidget);
      expect(find.text('\$12.50'), findsOneWidget);
      expect(find.byKey(const Key('wallet-pass-balance')), findsOneWidget);
    });

    testWidgets('renders app-native badges', (tester) async {
      await tester.pumpWidget(
        wrapWithRouter(
          const WalletPassCard(username: 'Test Username', balance: 12.50),
        ),
      );

      expect(find.text('Laundry credit'), findsOneWidget);
      expect(find.text('Ready to use'), findsOneWidget);
    });

    testWidgets('fits on a narrow phone without overflowing', (tester) async {
      await tester.pumpWidget(
        wrapWithRouter(
          const Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 328,
                child: WalletPassCard(
                  username: 'Test Username',
                  balance: 12.50,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('does not render old credit-card cues', (tester) async {
      await tester.pumpWidget(
        wrapWithRouter(
          const WalletPassCard(username: 'Test Username', balance: 12.50),
        ),
      );

      expect(find.byKey(const Key('cardChip')), findsNothing);
      expect(find.byKey(const Key('mastercard')), findsNothing);
      expect(find.text('1234   5678   9012   3456'), findsNothing);
    });

    testWidgets('falls back to John Doe when username is null', (tester) async {
      await tester.pumpWidget(
        wrapWithRouter(const WalletPassCard(username: null, balance: 12.50)),
      );

      expect(find.text('For John Doe'), findsOneWidget);
    });

    testWidgets('falls back to John Doe when username is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithRouter(const WalletPassCard(username: '', balance: 12.50)),
      );

      expect(find.text('For John Doe'), findsOneWidget);
    });
  });
}
