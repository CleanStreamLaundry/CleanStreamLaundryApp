import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_action_context.dart';
import 'package:clean_stream_laundry_app/features/loyalty/widgets/load_card_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fixtures/loyalty_action_context.dart';

void main() {
  final amountField = find.byType(TextField);
  final payButton = find.widgetWithText(ElevatedButton, 'Load');

  Future<void> openDialog(
    WidgetTester tester, {
    Future<void> Function(double)? onPay,
    ThemeData? theme,
    double textScale = 1,
    Future<LoyaltyActionContext> Function()? loadConsent,
    void Function(Map<String, dynamic>)? captureConsent,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => LoadCardDialog(
                  loadConsent: loadConsent ?? () async => actionContext(),
                  onPay: (amount, consent) async {
                    captureConsent?.call(consent);
                    await onPay?.call(amount);
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> acceptPurchase(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
  }

  testWidgets('keeps title, default amount, terms and dialog actions', (
    tester,
  ) async {
    await openDialog(tester);
    expect(find.text('Load Loyalty Card'), findsOneWidget);
    expect(tester.widget<TextField>(amountField).controller!.text, '1.00');
    expect(find.text(purchaseAcknowledgement), findsOneWidget);
    expect(find.textContaining('final sale'), findsNothing);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(tester.widget<ElevatedButton>(payButton).onPressed, isNull);
    expect(find.byKey(const Key('purchaseTermsLink')), findsOneWidget);
    expect(find.text('View terms'), findsNothing);
    expect(find.textContaining('Credit is usable only'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(payButton, findsOneWidget);
    expect(find.text('Pay'), findsNothing);
  });

  testWidgets(
    'keeps steppers alongside decimal input and presets without a slider',
    (tester) async {
      await openDialog(tester);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byTooltip('Decrease by 25 cents'), findsOneWidget);
      expect(find.byTooltip('Increase by 25 cents'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(
        tester.widget<TextField>(amountField).keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      for (final amount in [10, 15, 25, 50]) {
        expect(find.text('\$$amount'), findsOneWidget);
      }
      await tester.tap(amountField);
      await tester.pump();
      expect(
        tester.widget<TextField>(amountField).controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
    },
  );

  testWidgets('steppers adjust typed cents and clamp to existing limits', (
    tester,
  ) async {
    await openDialog(tester);
    final minus = find.widgetWithIcon(IconButton, Icons.remove);
    final plus = find.widgetWithIcon(IconButton, Icons.add);
    expect(tester.widget<IconButton>(minus).onPressed, isNull);
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amountField).controller!.text, '1.25');
    await tester.tap(minus);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amountField).controller!.text, '1.00');
    await tester.enterText(amountField, '37.13');
    await tester.pump();
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amountField).controller!.text, '37.38');
    await tester.enterText(amountField, '499.99');
    await tester.pump();
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amountField).controller!.text, '500.00');
    expect(tester.widget<IconButton>(plus).onPressed, isNull);
    await tester.enterText(amountField, '1.01');
    await tester.pump();
    await tester.tap(minus);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amountField).controller!.text, '1.00');
  });

  testWidgets('presets share one stable equal-width row in every selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openDialog(tester);
    final chips = [
      for (final amount in [10, 15, 25, 50])
        find.widgetWithText(ChoiceChip, '\$$amount'),
    ];
    final bounds = chips.map(tester.getRect).toList();
    for (final rect in bounds) {
      expect(rect.top, bounds.first.top);
      expect(rect.width, closeTo(bounds.first.width, .01));
      expect(rect.height, greaterThanOrEqualTo(48));
    }
    for (final chip in chips) {
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(chips.map(tester.getRect).toList(), bounds);
    }
  });

  for (final theme in [lightMode, darkMode]) {
    testWidgets(
      'uses brand header and yellow selection in ${theme.brightness}',
      (tester) async {
        await openDialog(tester, theme: theme);
        final logo = tester.widget<Image>(find.byType(Image));
        final resized = logo.image as ResizeImage;
        expect((resized.imageProvider as AssetImage).assetName, 'assets/Icon.png');
        expect(resized.width, 40 * tester.view.devicePixelRatio);
        expect(logo.width, 40);
        expect(logo.height, 40);
        expect(
          tester.widget<Text>(find.text('Load Loyalty Card')).style!.color,
          Colors.white,
        );
        await tester.tap(find.text('\$50'));
        await tester.pumpAndSettle();
        final selected = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, '\$50'),
        );
        expect(selected.selectedColor, theme.colorScheme.secondary);
        expect(selected.labelStyle!.color, Colors.black);
        expect(selected.selected, isTrue);
      },
    );
  }

  for (final amount in [10, 15, 25, 50]) {
    testWidgets('preset \$$amount updates field and checkout', (tester) async {
      double? captured;
      await openDialog(tester, onPay: (value) async => captured = value);
      await tester.tap(find.text('\$$amount'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(amountField).controller!.text,
        amount.toStringAsFixed(2),
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '\$$amount'))
            .selected,
        isTrue,
      );
      await acceptPurchase(tester);
      await tester.tap(payButton);
      await tester.pumpAndSettle();
      expect(captured, amount.toDouble());
      expect(find.byType(LoadCardDialog), findsNothing);
    });
  }

  for (final input in ['1', '1.', '1.01', '12.34', '49.99', '500', '500.00']) {
    testWidgets('typed $input reaches checkout unchanged', (tester) async {
      double? captured;
      await openDialog(tester, onPay: (value) async => captured = value);
      await tester.enterText(amountField, input);
      await tester.pump();
      await acceptPurchase(tester);
      expect(tester.widget<ElevatedButton>(payButton).onPressed, isNotNull);
      await tester.tap(payButton);
      await tester.pumpAndSettle();
      expect(captured, double.parse(input));
      expect(find.byType(LoadCardDialog), findsNothing);
    });
  }

  for (final input in [
    '',
    '0',
    '0.99',
    '-5',
    '500.01',
    '1000',
    '1.234',
    '1.2.3',
    '1e2',
    'NaN',
    'Infinity',
    'abc',
    '\$50',
    '5,00',
  ]) {
    testWidgets('invalid "$input" cannot start a payment', (tester) async {
      var calls = 0;
      await openDialog(
        tester,
        onPay: (_) async {
          calls++;
        },
      );
      await tester.enterText(amountField, input);
      await tester.pump();
      expect(
        tester.widget<TextField>(amountField).decoration!.errorText,
        isNotNull,
      );
      expect(tester.widget<ElevatedButton>(payButton).onPressed, isNull);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove))
            .onPressed,
        isNull,
      );
      await tester.tap(payButton);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byType(LoadCardDialog), findsOneWidget);
    });
  }

  testWidgets('typing updates selection and presets clear input errors', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(amountField, '50.00');
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '\$50'))
          .selected,
      isTrue,
    );
    await tester.enterText(amountField, '51.25');
    await tester.pump();
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .any((chip) => chip.selected),
      isFalse,
    );
    await tester.enterText(amountField, '');
    await tester.pump();
    await tester.tap(find.text('\$50'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amountField).decoration!.errorText, isNull);
    expect(tester.widget<TextField>(amountField).controller!.text, '50.00');
    expect(tester.widget<ElevatedButton>(payButton).onPressed, isNull);
    await acceptPurchase(tester);
    expect(tester.widget<ElevatedButton>(payButton).onPressed, isNotNull);
  });

  testWidgets('Cancel closes without starting a payment', (tester) async {
    var calls = 0;
    await openDialog(
      tester,
      onPay: (_) async {
        calls++;
      },
    );
    await tester.enterText(amountField, '37.25');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(LoadCardDialog), findsNothing);
    expect(calls, 0);
  });

  testWidgets('default amount reaches the existing checkout callback', (
    tester,
  ) async {
    double? captured;
    await openDialog(tester, onPay: (amount) async => captured = amount);
    await acceptPurchase(tester);
    await tester.tap(payButton);
    await tester.pumpAndSettle();
    expect(captured, 1.0);
  });

  testWidgets('each amount change requires fresh acknowledgement', (tester) async {
    Map<String, dynamic>? sent;
    await openDialog(tester, captureConsent: (value) => sent = value);
    await acceptPurchase(tester);
    await tester.enterText(amountField, '25.00');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(payButton).onPressed, isNull);
    await acceptPurchase(tester);
    await tester.tap(payButton);
    await tester.pumpAndSettle();
    expect(sent, actionContext().acknowledge());
  });

  testWidgets('failed consent load blocks checkout and supports retry', (tester) async {
    var attempts = 0;
    await openDialog(tester, loadConsent: () async {
      if (attempts++ == 0) throw StateError('offline');
      return actionContext();
    });
    expect(tester.widget<ElevatedButton>(payButton).onPressed, isNull);
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text(purchaseAcknowledgement), findsOneWidget);
    expect(tester.widget<ElevatedButton>(payButton).onPressed, isNull);
  });

  testWidgets('reading exact terms keeps amount and does not imply consent', (tester) async {
    await openDialog(tester);
    await tester.enterText(amountField, '37.25');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('purchaseTermsLink')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchaseTermsLink')));
    await tester.pumpAndSettle();
    expect(find.text('Loyalty terms'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amountField).controller!.text, '37.25');
    expect(tester.widget<ElevatedButton>(payButton).onPressed, isNull);
  });

  testWidgets('keeps the terms link readable without accepting an invalid amount', (tester) async {
    await openDialog(tester);
    await tester.enterText(amountField, '0');
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    await tester.ensureVisible(find.byKey(const Key('purchaseTermsLink')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchaseTermsLink')));
    await tester.pumpAndSettle();
    expect(find.text('Loyalty terms'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(tester.widget<ElevatedButton>(payButton).onPressed, isNull);
  });

  for (final theme in [lightMode, darkMode]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('keyboard fits ${theme.brightness.name} at ${scale}x', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await openDialog(tester, theme: theme, textScale: scale);
        expect(
          tester.getTopLeft(find.text('Amount')).dy,
          greaterThanOrEqualTo(
            tester.getTopLeft(find.byType(SingleChildScrollView)).dy,
          ),
        );
        await tester.enterText(amountField, '42.75');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getBottomLeft(payButton).dy, lessThanOrEqualTo(480));
        expect(payButton.hitTestable(), findsOneWidget);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
      });
    }
  }
}
