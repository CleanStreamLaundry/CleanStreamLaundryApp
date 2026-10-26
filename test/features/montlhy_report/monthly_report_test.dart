import 'package:clean_stream_laundry_app/features/monthly_report/monthly_report.dart';
import 'package:clean_stream_laundry_app/features/monthly_report/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

void main() {
  Map<String, dynamic> createTransaction({
    required int monthsAgo,
    required String description,
    required double amount,
  }) {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month - monthsAgo, 15);
    return {
      'created_at': date.toIso8601String(),
      'description': description,
      'amount': amount,
    };
  }

  Widget createWidget(List<Map<String, dynamic>> transactions) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) =>
                MonthlyReport(transactions: transactions),
          ),
        ],
      ),
    );
  }

  Future<void> selectYearFilter(WidgetTester tester, int year) async {
    await tester.tap(find.byKey(const ValueKey('year-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('year-option-$year')));
    await tester.pumpAndSettle();
  }

  group('AppBar', () {
    testWidgets('displays compact Monthly history title', (tester) async {
      await tester.pumpWidget(createWidget([]));
      await tester.pumpAndSettle();
      expect(find.text('Monthly history'), findsOneWidget);
    });

    testWidgets('displays back button', (tester) async {
      await tester.pumpWidget(createWidget([]));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('displays year filter button', (tester) async {
      await tester.pumpWidget(createWidget([]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('year-filter-button')), findsOneWidget);
    });

    testWidgets('back button pops the route', (tester) async {
      await tester.pumpWidget(createWidget([]));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNotNull);
    });
  });

  group('Empty state', () {
    testWidgets('shows no cards when transactions are empty', (tester) async {
      await tester.pumpWidget(createWidget([]));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('shows no transactions message when empty', (tester) async {
      await tester.pumpWidget(createWidget([]));
      await tester.pumpAndSettle();
      expect(
        find.text('No transactions found for this time range.'),
        findsOneWidget,
      );
    });
  });

  group('Content display', () {
    testWidgets('displays card for month with transactions', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();

      final year = DateTime.parse(
          transactions.first['created_at'] as String)
          .year;
      await selectYearFilter(tester, year);

      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('displays correct monthly total', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
        createTransaction(monthsAgo: 1, description: 'Dryer #3', amount: 1.75),
        createTransaction(
            monthsAgo: 1, description: 'loyalty card', amount: 10.00),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.text('\$14.25'), findsOneWidget);
    });

    testWidgets('displays all five transaction category labels', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
        createTransaction(
            monthsAgo: 1,
            description: 'Loyalty Payment on Washer #3',
            amount: 2.00),
        createTransaction(monthsAgo: 1, description: 'Dryer #2', amount: 1.75),
        createTransaction(
            monthsAgo: 1,
            description: 'Loyalty Payment on Dryer #1',
            amount: 1.50),
        createTransaction(
            monthsAgo: 1, description: 'loyalty card', amount: 10.00),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();

      expect(find.text('Direct Washer Payments'), findsOneWidget);
      expect(find.text('Loyalty Washer Payments'), findsOneWidget);
      expect(find.text('Direct Dryer Payments'), findsOneWidget);
      expect(find.text('Loyalty Dryer Payments'), findsOneWidget);
      expect(find.text('Loyalty Card Loads'), findsOneWidget);
    });

    testWidgets('shows zero amounts for categories with no transactions',
            (tester) async {
          final transactions = [
            createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
          ];
          await tester.pumpWidget(createWidget(transactions));
          await tester.pumpAndSettle();
          expect(find.text('\$0.00'), findsWidgets);
        });

    testWidgets('aggregates multiple transactions in the same month',
            (tester) async {
          final transactions = [
            createTransaction(monthsAgo: 1, description: 'Washer #1', amount: 2.50),
            createTransaction(monthsAgo: 1, description: 'Washer #2', amount: 3.00),
            createTransaction(monthsAgo: 1, description: 'Washer #3', amount: 2.75),
          ];
          await tester.pumpWidget(createWidget(transactions));
          await tester.pumpAndSettle();
          expect(find.text('\$8.25'), findsWidgets);
          expect(find.byType(Card), findsOneWidget);
        });

    testWidgets('shows multiple months', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
        createTransaction(monthsAgo: 2, description: 'Washer #5', amount: 3.00),
        createTransaction(monthsAgo: 3, description: 'Washer #5', amount: 3.50),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsAtLeastNWidgets(2));
    });

    testWidgets('sorts months in descending order', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 3, description: 'Washer #5', amount: 2.50),
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 3.00),
        createTransaction(monthsAgo: 2, description: 'Washer #5', amount: 2.75),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();

      final firstCard = find.byType(Card).first;
      final expectedMostRecent = DateFormat('MMM yyyy').format(
        DateTime(DateTime.now().year, DateTime.now().month - 1, 1),
      );
      expect(
        find.descendant(of: firstCard, matching: find.text(expectedMostRecent)),
        findsOneWidget,
      );
    });

    testWidgets('displays scrollbar', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('ListView has correct padding', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.padding, const EdgeInsets.all(16));
    });

    testWidgets('card has correct bottom margin', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.margin, const EdgeInsets.only(bottom: 16));
    });

    testWidgets('displays divider between header and breakdown', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('formats decimal amounts correctly', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.5),
        createTransaction(monthsAgo: 1, description: 'Dryer #3', amount: 1.76),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.text('\$2.50'), findsWidgets);
      expect(find.text('\$1.76'), findsWidgets);
    });

    testWidgets('ignores current month transactions', (tester) async {
      final now = DateTime.now();
      final transactions = [
        {
          'created_at': DateTime(now.year, now.month, 15).toIso8601String(),
          'description': 'Washer #5',
          'amount': 2.50,
        },
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 3.00),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();

      final year = DateTime.parse(
          transactions.first['created_at'] as String)
          .year;
      await selectYearFilter(tester, year);

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('\$3.00'), findsWidgets);
    });
  });

  group('Transaction categories', () {
    testWidgets('handles loyalty washer payments', (tester) async {
      final transactions = [
        createTransaction(
            monthsAgo: 1,
            description: 'Loyalty Payment on Washer #5',
            amount: 2.50),
        createTransaction(
            monthsAgo: 1,
            description: 'loyalty payment on washer #3',
            amount: 3.00),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.text('\$5.50'), findsWidgets);
    });

    testWidgets('handles loyalty dryer payments', (tester) async {
      final transactions = [
        createTransaction(
            monthsAgo: 1,
            description: 'Loyalty Payment on Dryer #2',
            amount: 1.50),
        createTransaction(
            monthsAgo: 1,
            description: 'loyalty payment on dryer #1',
            amount: 1.25),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.text('\$2.75'), findsWidgets);
    });

    testWidgets('handles direct dryer payments', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Dryer #2', amount: 1.50),
        createTransaction(monthsAgo: 1, description: 'DRYER #1', amount: 1.25),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.text('\$2.75'), findsWidgets);
    });

    testWidgets('handles loyalty card loads', (tester) async {
      final transactions = [
        createTransaction(
            monthsAgo: 1, description: 'loyalty card', amount: 10.00),
        createTransaction(
            monthsAgo: 1, description: 'loyalty card', amount: 20.00),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.text('\$30.00'), findsWidgets);
    });

    testWidgets('handles mixed transaction types in same month', (tester) async {
      final transactions = [
        createTransaction(monthsAgo: 1, description: 'Washer #5', amount: 2.50),
        createTransaction(
            monthsAgo: 1,
            description: 'Loyalty Payment on Washer #3',
            amount: 2.00),
        createTransaction(monthsAgo: 1, description: 'Dryer #2', amount: 1.75),
        createTransaction(
            monthsAgo: 1,
            description: 'Loyalty Payment on Dryer #1',
            amount: 1.50),
        createTransaction(
            monthsAgo: 1, description: 'loyalty card', amount: 10.00),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();
      expect(find.text('\$14.25'), findsOneWidget);
    });
  });

  group('Year filter', () {
    testWidgets('shows year options from transaction data', (tester) async {
      final newerDate =
      DateTime(DateTime.now().year, DateTime.now().month - 1, 15);
      final olderDate =
      DateTime(DateTime.now().year, DateTime.now().month - 11, 15);
      final expectedYears = <int>{newerDate.year, olderDate.year}.toList()
        ..sort((a, b) => b.compareTo(a));

      final transactions = [
        {
          'created_at': olderDate.toIso8601String(),
          'description': 'Washer #1',
          'amount': 2.50,
        },
        {
          'created_at': newerDate.toIso8601String(),
          'description': 'Dryer #1',
          'amount': 1.75,
        },
      ];

      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('year-filter-button')));
      await tester.pumpAndSettle();

      expect(
          find.text('Year: ${expectedYears.first}'), findsOneWidget);
      for (final year in expectedYears) {
        expect(find.byKey(ValueKey('year-option-$year')), findsOneWidget);
      }

      await tester.tap(
          find.byKey(ValueKey('year-option-${expectedYears.first}')));
      await tester.pumpAndSettle();
    });

    testWidgets('selecting a year shows only that year data', (tester) async {
      final newerDate =
      DateTime(DateTime.now().year, DateTime.now().month - 1, 15);
      final olderDate =
      DateTime(DateTime.now().year, DateTime.now().month - 11, 15);
      final newerYear = newerDate.year;
      final olderYear = olderDate.year;
      final olderMonthLabel = DateFormat('MMM yyyy')
          .format(DateTime(olderDate.year, olderDate.month, 1));
      final newerMonthLabel = DateFormat('MMM yyyy')
          .format(DateTime(newerDate.year, newerDate.month, 1));

      final transactions = [
        {
          'created_at': olderDate.toIso8601String(),
          'description': 'Washer #5',
          'amount': 2.50,
        },
        {
          'created_at': newerDate.toIso8601String(),
          'description': 'Dryer #2',
          'amount': 3.00,
        },
      ];

      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();

      if (olderYear == newerYear) {
        expect(find.text(newerMonthLabel), findsOneWidget);
        expect(find.text(olderMonthLabel), findsOneWidget);
        return;
      }

      expect(find.text(newerMonthLabel), findsOneWidget);
      expect(find.text(olderMonthLabel), findsNothing);

      await selectYearFilter(tester, olderYear);

      expect(find.text(olderMonthLabel), findsOneWidget);
      expect(find.text(newerMonthLabel), findsNothing);
    });

    testWidgets('can switch between years without errors', (tester) async {
      final newerDate =
      DateTime(DateTime.now().year, DateTime.now().month - 1, 15);
      final olderDate =
      DateTime(DateTime.now().year, DateTime.now().month - 11, 15);
      final olderYear = olderDate.year;
      final newerYear = newerDate.year;

      final transactions = [
        {
          'created_at': olderDate.toIso8601String(),
          'description': 'Dryer #2',
          'amount': 1.75,
        },
        {
          'created_at': newerDate.toIso8601String(),
          'description': 'Washer #2',
          'amount': 2.25,
        },
      ];

      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();

      await selectYearFilter(tester, olderYear);
      expect(tester.takeException(), isNull);

      if (olderYear != newerYear) {
        await selectYearFilter(tester, newerYear);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles transaction from 11 months ago', (tester) async {
      final transactions = [
        createTransaction(
            monthsAgo: 11, description: 'Washer #5', amount: 2.50),
      ];
      await tester.pumpWidget(createWidget(transactions));
      await tester.pumpAndSettle();

      final year = DateTime.parse(
          transactions.first['created_at'] as String)
          .year;
      await selectYearFilter(tester, year);

      expect(find.byType(Card), findsOneWidget);
    });
  });

  group('MonthlyReportController', () {
    test('selectedYear defaults to most recent available year', () {
      final now = DateTime.now();
      final transactions = [
        {
          'created_at':
          DateTime(now.year, now.month - 1, 15).toIso8601String(),
          'description': 'Washer #1',
          'amount': 2.50,
        },
      ];

      final controller =
      MonthlyReportController(transactions: transactions);

      expect(controller.selectedYear, now.year);
    });

    test('selectYear updates selectedYear and notifies listeners', () {
      final now = DateTime.now();
      final olderDate = DateTime(now.year, now.month - 11, 15);
      final transactions = [
        {
          'created_at': olderDate.toIso8601String(),
          'description': 'Washer #1',
          'amount': 2.50,
        },
        {
          'created_at':
          DateTime(now.year, now.month - 1, 15).toIso8601String(),
          'description': 'Dryer #1',
          'amount': 1.75,
        },
      ];

      final controller =
      MonthlyReportController(transactions: transactions);
      var notified = false;
      controller.addListener(() => notified = true);

      if (olderDate.year != now.year) {
        controller.selectYear(olderDate.year);
        expect(controller.selectedYear, olderDate.year);
        expect(notified, isTrue);
      }
    });

    test('selectYear does nothing when same year selected', () {
      final now = DateTime.now();
      final transactions = [
        {
          'created_at':
          DateTime(now.year, now.month - 1, 15).toIso8601String(),
          'description': 'Washer #1',
          'amount': 2.50,
        },
      ];

      final controller =
      MonthlyReportController(transactions: transactions);
      var notified = false;
      controller.addListener(() => notified = true);

      controller.selectYear(controller.selectedYear);
      expect(notified, isFalse);
    });

    test('filteredMonths returns only months for selectedYear', () {
      final now = DateTime.now();
      final transactions = [
        {
          'created_at':
          DateTime(now.year, now.month - 1, 15).toIso8601String(),
          'description': 'Washer #1',
          'amount': 2.50,
        },
      ];

      final controller =
      MonthlyReportController(transactions: transactions);

      for (final month in controller.filteredMonths) {
        final date = DateFormat('MMM yyyy').parse(month);
        expect(date.year, controller.selectedYear);
      }
    });

    test('availableYears contains current year when no transactions', () {
      final controller = MonthlyReportController(transactions: []);
      expect(controller.availableYears, contains(DateTime.now().year));
    });
  });
}
