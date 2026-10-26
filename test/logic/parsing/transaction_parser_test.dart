import 'package:clean_stream_laundry_app/logic/parsing/transaction_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';


void main(){

  group("Test for TransactionParser",(){

    test('formats fixed dates with literal English month and padded day', () {
      // Future records isolate formatting from rolling history retention.
      final result = Intl.withLocale(
        'en_US',
        () => TransactionParser.formatTransactionsList([
          {
            'amount': 2.75,
            'description': 'Dryer',
            'created_at': '2099-01-02T03:04:05',
          },
          {
            'amount': 10,
            'description': 'Loyalty Card',
            'created_at': '2099-12-31T23:59:00',
          },
        ], 'transactionHistory'),
      );

      expect(result, [
        r'$2.75 - Dryer on Jan 02, 2099',
        r'$10.00 added to Loyalty Card on Dec 31, 2099',
      ]);
    });

    test("Test that transactions are parsed correctly",(){

      final result = TransactionParser.formatTransaction(({"amount": 2.75, "description": "Dryer", "created_at": DateTime.now().toString()}), "transactionHistory");
      expect(result, "\$2.75 - Dryer on ${DateFormat("MMM").format(DateTime.now()).toString()} ${DateFormat("dd").format(DateTime.now()).toString()}, ${DateFormat("y").format(DateTime.now()).toString()}");
    });

    test("Test that transactions are parsed correctly if description is Loyalty Card",(){

      final result = TransactionParser.formatTransaction(({"amount": 2.75, "description": "Loyalty Card", "created_at": DateTime.now().toString()}), "transactionHistory");
      expect(result, "\$2.75 added to Loyalty Card on ${DateFormat("MMM").format(DateTime.now()).toString()} ${DateFormat("dd").format(DateTime.now()).toString()}, ${DateFormat("y").format(DateTime.now()).toString()}");
    });

    test("Test that it can format a list of transactions",(){
      final result = TransactionParser.formatTransactionsList([{"amount": 2.75, "description": "Dryer", "created_at": DateTime.now().toString()},{"amount": 4.75, "description": "Washer", "created_at": "2025-11-12T19:23:24.781326+00:00"}], "transactionHistory");
      expect(result[0], "\$2.75 - Dryer on ${DateFormat("MMM").format(DateTime.now()).toString()} ${DateFormat("dd").format(DateTime.now()).toString()}, ${DateFormat("y").format(DateTime.now()).toString()}");
    });
    
    test("Test for monthly report",(){
      final data = [
        {"amount": 2.75, "description": "washer", "created_at": "2025-11-12T19:23:24.781326+00:00"},
        {"amount": 3.5, "description": "machine", "created_at": "2025-11-11T23:31:57.39522+00:00"},
        {"amount": 3.5, "description": "machine", "created_at": "2025-11-11T23:14:48.968499+00:00"},
        {"amount": 10, "description": "Loyalty Card", "created_at": "2025-11-11T23:09:41.410673+00:00"},
        {"amount": 20, "description": "Loyalty Card", "created_at": "2025-11-11T23:07:14.775736+00:00"},
        {"amount": 2.75, "description": "machine", "created_at": "2025-11-02T16:24:51.685419+00:00"},
        {"amount": 2.75, "description": "dryer", "created_at": "2025-10-28T15:13:24.87605+00:00"},
        {"amount": 2.75, "description": "machine", "created_at": "2025-10-28T14:27:54.429939+00:00"},
        {"amount": 2.75, "description": "loyalty card", "created_at": "2025-10-28T14:26:21.662999+00:00"},
        {"amount": 2.75, "description": "machine", "created_at": "2025-10-27T18:06:40.987278+00:00"},
        {"amount": 2.75, "description": "machine", "created_at": "2025-10-27T00:17:18.01511+00:00"}
      ];

      final result = TransactionParser.getMonthlySums(data);
      expect(result["Oct 2025"]?["directWasher"],0.0);
    });

    test("getMonthlySums correctly adds loyaltyWasher sums", () {
      // Use a date from LAST month so it is included.
      final lastMonth = DateTime.now().subtract(const Duration(days: 30));

      final data = [
        {
          "amount": 5.0,
          "description": "Loyalty Payment on Washer",
          "created_at": lastMonth.toIso8601String(),
        }
      ];

      final result = TransactionParser.getMonthlySums(data);

      final monthKey = DateFormat('MMM yyyy').format(lastMonth);

      expect(result[monthKey]!['loyaltyWasher'], 5.0);
      expect(result[monthKey]!['loyaltyDryer'], 0.0);
    });

    test("getMonthlySums correctly adds loyaltyDryer sums", () {
      final lastMonth = DateTime.now().subtract(const Duration(days: 30));

      final data = [
        {
          "amount": 7.5,
          "description": "Loyalty Payment on Dryer",
          "created_at": lastMonth.toIso8601String(),
        }
      ];

      final result = TransactionParser.getMonthlySums(data);

      final monthKey = DateFormat('MMM yyyy').format(lastMonth);

      expect(result[monthKey]!['loyaltyDryer'], 7.5);
      expect(result[monthKey]!['loyaltyWasher'], 0.0);
    });


  });


  test("getTransactionIDs returns ID for recent transactions", () {
    final recentDate = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();

    final transaction = {
      "id": 42,
      "created_at": recentDate,
    };

    final id = TransactionParser.getTransactionIDs(transaction);

    expect(id, 42);
  });

  test("getTransactionIDs returns -1 for transactions older than 2 weeks", () {
    final oldDate = DateTime.now().subtract(const Duration(days: 20)).toIso8601String();

    final transaction = {
      "id": 7,
      "created_at": oldDate,
    };

    final id = TransactionParser.getTransactionIDs(transaction);

    expect(id, -1);
  });

  test("createTransactionIDList returns list of correct IDs", () {
    final recentDate = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
    final oldDate = DateTime.now().subtract(const Duration(days: 25)).toIso8601String();

    final data = [
      {"id": 1, "created_at": recentDate},
      {"id": 2, "created_at": oldDate},
      {"id": 3, "created_at": recentDate},
    ];

    final result = TransactionParser.createTransactionIDList(data);

    expect(result, [1, -1, 3]);
  });

}
