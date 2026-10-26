import 'package:clean_stream_laundry_app/features/loyalty/widgets/transaction_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../mocks.dart';

void main() {
  late MockLoyaltyController mockController;

  setUpAll(() {
    registerFallbackValue((_) {});
  });

  setUp(() {
    mockController = MockLoyaltyController();
    when(() => mockController.recentTransactions).thenReturn([]);
    when(() => mockController.showPastTransactions).thenReturn(false);
    when(() => mockController.isLoading).thenReturn(false);
    when(() => mockController.isRefreshing).thenReturn(false);
    when(() => mockController.isLoadingMore).thenReturn(false);
    when(() => mockController.hasMoreTransactions).thenReturn(false);
    when(() => mockController.toggleTransactionView()).thenAnswer((_) async {});
  });

  Widget buildWidget() {
    return MaterialApp(
      home: Scaffold(body: TransactionList(controller: mockController)),
    );
  }

  group('TransactionList', () {
    testWidgets('only More transactions fetches a page; loading disables it', (
      tester,
    ) async {
      when(() => mockController.recentTransactions).thenReturn(['First entry']);
      when(() => mockController.showPastTransactions).thenReturn(true);
      when(() => mockController.hasMoreTransactions).thenReturn(true);
      when(
        () => mockController.loadMoreTransactions(),
      ).thenAnswer((_) async {});
      await tester.pumpWidget(buildWidget());
      await tester.tap(find.byKey(const ValueKey('transactions-next-page')));
      verify(() => mockController.loadMoreTransactions()).called(1);
      when(() => mockController.isLoadingMore).thenReturn(true);
      await tester.pumpWidget(buildWidget());
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('transactions-next-page')),
      );
      expect(button.onPressed, isNull);
      expect(find.text('First entry'), findsOneWidget);
    });

    testWidgets('initial error is not a false empty-history message', (
      tester,
    ) async {
      when(
        () => mockController.transactionsError,
      ).thenReturn('Unable to refresh transactions');
      await tester.pumpWidget(buildWidget());
      expect(find.text('Unable to refresh transactions'), findsOneWidget);
      expect(find.text('No transactions found.'), findsNothing);
    });

    group('Empty state', () {
      testWidgets('shows No transactions found text', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('No transactions found.'), findsOneWidget);
      });

      testWidgets('does not show Transactions header', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.text('Transactions'), findsNothing);
      });

      testWidgets('does not show ListView', (tester) async {
        await tester.pumpWidget(buildWidget());
        expect(find.byType(ListView), findsNothing);
      });
    });

    group('Populated state', () {
      setUp(() {
        when(
          () => mockController.recentTransactions,
        ).thenReturn(['Transaction A', 'Transaction B']);
      });

      testWidgets('shows Transactions header', (tester) async {
        await tester.pumpWidget(buildWidget());
        await tester.pump();
        expect(find.text('Transactions'), findsOneWidget);
      });

      testWidgets('shows transaction items', (tester) async {
        await tester.pumpWidget(buildWidget());
        await tester.pump();
        expect(find.text('Transaction A'), findsOneWidget);
        expect(find.text('Transaction B'), findsOneWidget);
      });

      testWidgets('shows receipt_long icon for each transaction', (
        tester,
      ) async {
        await tester.pumpWidget(buildWidget());
        await tester.pump();
        expect(find.byIcon(Icons.receipt_long), findsNWidgets(2));
      });

      testWidgets('wraps each transaction in a Card', (tester) async {
        await tester.pumpWidget(buildWidget());
        await tester.pump();
        expect(find.byType(Card), findsWidgets);
      });
    });

    group('Toggle button', () {
      setUp(() {
        when(
          () => mockController.recentTransactions,
        ).thenReturn(['Transaction A']);
      });

      testWidgets('shows Show More when showPastTransactions is false', (
        tester,
      ) async {
        await tester.pumpWidget(buildWidget());
        await tester.pump();
        expect(find.text('Show More'), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
      });

      testWidgets('shows Show Less when showPastTransactions is true', (
        tester,
      ) async {
        when(() => mockController.showPastTransactions).thenReturn(true);
        await tester.pumpWidget(buildWidget());
        await tester.pump();
        expect(find.text('Show Less'), findsOneWidget);
        expect(find.byIcon(Icons.expand_less), findsOneWidget);
      });

      testWidgets('calls toggleTransactionView when Show More tapped', (
        tester,
      ) async {
        await tester.pumpWidget(buildWidget());
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('transactions-toggle-button')),
        );
        await tester.pump();
        verify(() => mockController.toggleTransactionView()).called(1);
      });

      testWidgets('calls toggleTransactionView when Show Less tapped', (
        tester,
      ) async {
        when(() => mockController.showPastTransactions).thenReturn(true);
        await tester.pumpWidget(buildWidget());
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('transactions-toggle-button')),
        );
        await tester.pump();
        verify(() => mockController.toggleTransactionView()).called(1);
      });
    });
  });
}
