import 'package:clean_stream_laundry_app/features/loyalty/widgets/header.dart';
import 'package:clean_stream_laundry_app/features/loyalty/widgets/wallet_pass_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../mocks.dart';

void main() {
  late MockLoyaltyController mockController;

  setUp(() {
    mockController = MockLoyaltyController();
    when(() => mockController.userName).thenReturn('Jane Doe');
    when(() => mockController.userBalance).thenReturn(50.0);
    when(() => mockController.paidBalance).thenReturn(35.0);
    when(() => mockController.promoBalance).thenReturn(15.0);
    when(() => mockController.userReward).thenReturn(5.0);
  });

  Widget buildWidget({VoidCallback? onInfoTap}) {
    return MaterialApp(
      home: Scaffold(
        body: Header(controller: mockController, onInfoTap: onInfoTap ?? () {}),
      ),
    );
  }

  group('LoyaltyHeader', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('long name and large balances fit at 320px, ${scale}x', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        when(
          () => mockController.userName,
        ).thenReturn('Alexandria Montgomery-Wellington');
        when(() => mockController.userBalance).thenReturn(1234567.89);
        when(() => mockController.paidBalance).thenReturn(1234500.00);
        when(() => mockController.promoBalance).thenReturn(67.89);
        var infoTapped = false;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Header(
                  controller: mockController,
                  onInfoTap: () => infoTapped = true,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final label in [
          'For Alexandria Montgomery-Wellington',
          '\$1234567.89',
          'Paid \$1234500.00',
          'Promo \$67.89',
          'Laundry credit',
          'Ready to use',
        ]) {
          final finder = find.text(label);
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
          expect(paragraph.textScaler.scale(14), 14 * scale);
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(16));
          expect(rect.right, lessThanOrEqualTo(304));
        }
        expect(find.byType(FittedBox), findsNothing);
        await tester.ensureVisible(find.byTooltip('Rewards program'));
        await tester.tap(find.byTooltip('Rewards program'));
        expect(infoTapped, isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    group('Rendering', () {
      testWidgets('shows WalletPassCard widget', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byType(WalletPassCard), findsOneWidget);
      });

      testWidgets('passes username to WalletPassCard', (tester) async {
        await tester.pumpWidget(buildWidget());
        final card = tester.widget<WalletPassCard>(find.byType(WalletPassCard));
        expect(card.username, 'Jane Doe');
      });

      testWidgets('shows default username when userName is null', (
        tester,
      ) async {
        when(() => mockController.userName).thenReturn(null);
        await tester.pumpWidget(buildWidget());
        final card = tester.widget<WalletPassCard>(find.byType(WalletPassCard));
        expect(card.username, 'John Doe');
      });

      testWidgets('displays formatted balance', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('\$50.00'), findsOneWidget);
      });

      testWidgets('displays default balance when userBalance is null', (
        tester,
      ) async {
        when(() => mockController.userBalance).thenReturn(null);
        await tester.pumpWidget(buildWidget());
        expect(find.text('\$0.00'), findsOneWidget);
      });

      testWidgets('displays paid and promo balances', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('Paid \$35.00'), findsOneWidget);
        expect(find.text('Promo \$15.00'), findsOneWidget);
      });

      testWidgets('displays reward countdown text', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('\$15.00 until next reward'), findsOneWidget);
      });

      testWidgets(
        'displays reward countdown as 20.00 when userReward is null',
        (tester) async {
          when(() => mockController.userReward).thenReturn(null);
          await tester.pumpWidget(buildWidget());
          expect(find.text('\$20.00 until next reward'), findsOneWidget);
        },
      );

      testWidgets('shows the exact slogan', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('Where freshness flows.'), findsOneWidget);
      });

      testWidgets('shows info_outline icon button', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
      });
    });

    group('Info button', () {
      testWidgets('calls onInfoTap when info button tapped', (tester) async {
        var tapped = false;
        await tester.pumpWidget(buildWidget(onInfoTap: () => tapped = true));

        await tester.tap(find.byIcon(Icons.info_outline));

        expect(tapped, isTrue);
      });
    });
  });
}
