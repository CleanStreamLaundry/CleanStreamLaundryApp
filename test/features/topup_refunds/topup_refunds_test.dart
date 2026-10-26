import 'dart:async';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/topup_refunds/topup_refunds.dart';
import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'fixtures.dart';

void main() {
  late RefundHarness h;
  setUp(() {
    h = RefundHarness()..register();
  });
  tearDown(() => h.dispose());

  Future<void> show(
    WidgetTester tester, {
    ThemeData? theme,
    double scale = 1,
    bool boldText = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? lightMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale), boldText: boldText),
          child: child!,
        ),
        home: const TopupRefundsPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    for (
      var i = 0;
      i < 20 &&
          find.text('Request full refund').hitTestable().evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(find.text('Request full refund').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Request full refund'));
    await tester.pumpAndSettle();
  }

  for (final sample in [
    (
      hour: 0,
      paid: 'Paid Jan 2, 2026, 12:05 AM (local time)',
      deadline: 'Server request deadline: Jan 4, 2026, 12:05 AM (local time)',
    ),
    (
      hour: 12,
      paid: 'Paid Jan 2, 2026, 12:05 PM (local time)',
      deadline: 'Server request deadline: Jan 4, 2026, 12:05 PM (local time)',
    ),
  ]) {
    testWidgets('renders literal USD and local date at hour ${sample.hour}', (
      tester,
    ) async {
      final previousLocale = Intl.defaultLocale;
      Intl.defaultLocale = 'en_US';
      addTearDown(() => Intl.defaultLocale = previousLocale);
      final paid = DateTime(2026, 1, 2, sample.hour, 5).toUtc();
      h.topups = [
        RefundableTopup.fromJson({
          ...topupJson(reason: 'refund_window_closed'),
          'principal_cents': 123456,
          'payment_succeeded_at': paid.toIso8601String(),
          'request_deadline': paid
              .add(const Duration(hours: 48))
              .toIso8601String(),
        }),
      ];

      await show(tester);

      expect(find.text(r'$1,234.56 USD'), findsOneWidget);
      expect(find.text(sample.paid), findsOneWidget);
      expect(find.text(sample.deadline), findsOneWidget);
      expect(h.writes, 0);
    });
  }

  testWidgets('honest policy, explicit deadline and full confirmation', (
    tester,
  ) async {
    await show(tester);
    expect(find.textContaining('within 48 hours'), findsOneWidget);
    expect(find.textContaining('Server request deadline'), findsOneWidget);
    await confirm(tester);
    expect(find.text('Request full top-up refund?'), findsOneWidget);
    expect(
      find.textContaining('original payment method. No processing fee'),
      findsOneWidget,
    );
    expect(find.textContaining('reserved immediately'), findsOneWidget);
    expect(
      find.textContaining('A request is not a paid refund'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirm request'));
    await tester.pumpAndSettle();
    expect(h.writes, 1);
    expect(
      find.textContaining('not confirmation of repayment'),
      findsOneWidget,
    );
  });
  testWidgets('cancel sends no request', (tester) async {
    await show(tester);
    await confirm(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.writes, 0);
  });
  testWidgets('A-B-A while real modal open disables stale confirmation', (
    tester,
  ) async {
    await show(tester);
    await confirm(tester);
    final a = h.session;
    h.change(refundSession(id: customerB));
    h.change(a);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm request'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Your session changed'), findsOneWidget);
    expect(h.writes, 0);
  });
  testWidgets('uncertain outcome never shows success or replay control', (
    tester,
  ) async {
    h.writeError = TimeoutException('synthetic');
    await show(tester);
    await confirm(tester);
    await tester.tap(find.text('Confirm request'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not yet confirmed'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Request full refund'),
          )
          .onPressed,
      isNull,
    );
    expect(h.writes, 1);
  });
  testWidgets('cached content survives visible refresh error', (tester) async {
    await show(tester);
    h.topupError = StateError('offline');
    await tester.tap(find.byTooltip('Refresh refunds'));
    await tester.pumpAndSettle();
    expect(find.text('Top-up #9007199254740993'), findsOneWidget);
    expect(find.textContaining('out of date'), findsOneWidget);
  });
  testWidgets('empty lists distinguished from errors', (tester) async {
    h.topups = [];
    await show(tester);
    expect(find.text('No top-ups found.'), findsOneWidget);
    expect(find.text('No refund requests found.'), findsOneWidget);
    expect(find.textContaining('out of date'), findsNothing);
  });
  const labels = {
    'requested': 'Awaiting Owner review',
    'approved': 'Approved - not yet confirmed',
    'unknown': 'Outcome unknown',
    'pending': 'Refund pending',
    'succeeded': 'Refund confirmed by processor',
    'failed': 'Refund failed',
    'canceled': 'Refund canceled',
    'denied': 'Request denied',
  };
  for (final entry in labels.entries) {
    testWidgets('precise ${entry.key} presentation', (tester) async {
      h.topups = [];
      h.refunds = [TopupRefund.fromJson(refundJson(status: entry.key))];
      await show(tester);
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(
        find.textContaining('Bank posting'),
        entry.key == 'succeeded' ? findsOneWidget : findsNothing,
      );
      if (['failed', 'canceled', 'denied'].contains(entry.key)) {
        expect(
          find.textContaining('reservation has been released'),
          findsOneWidget,
        );
      }
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      '320px large text ${dark ? 'dark' : 'light'} page and modal fit',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await show(
          tester,
          theme: dark ? darkMode : lightMode,
          scale: 2,
          boldText: true,
        );
        expect(tester.takeException(), isNull);
        await confirm(tester);
        expect(tester.takeException(), isNull);
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(dialog.scrollable, isTrue);
        expect(
          (dialog.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(8),
        );
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        expect(find.text('Confirm request').hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
        final semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel('Confirm request'), findsOneWidget);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        semantics.dispose();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(h.writes, 0);
      },
    );
  }
  testWidgets(
    'confirmation lives in nearest navigator and vanishes with admitted subtree',
    (tester) async {
      final admitted = ValueNotifier(true);
      addTearDown(admitted.dispose);
      final rootObserver = _Observer();
      final innerObserver = _Observer();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [rootObserver],
          home: ValueListenableBuilder<bool>(
            valueListenable: admitted,
            builder: (_, allowed, _) => allowed
                ? Navigator(
                    observers: [innerObserver],
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const TopupRefundsPage(),
                    ),
                  )
                : const Scaffold(body: Text('Account restricted')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await confirm(tester);
      expect(rootObserver.dialogs, 0);
      expect(innerObserver.dialogs, 1);
      admitted.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Confirm request'), findsNothing);
      expect(h.writes, 0);
    },
  );

  testWidgets('retained inactive page disables an open confirmation', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, value, _) => TopupRefundsPage(active: value),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await confirm(tester);
    active.value = false;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm request'),
          )
          .onPressed,
      isNull,
    );
    expect(h.writes, 0);
  });
}

class _Observer extends NavigatorObserver {
  int dialogs = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is DialogRoute) dialogs++;
  }
}
