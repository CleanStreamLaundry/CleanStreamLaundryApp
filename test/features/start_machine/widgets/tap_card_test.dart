import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:clean_stream_laundry_app/features/start_machine/widgets/tap_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TapToPayCard', () {
    testWidgets('button semantics activate the callback once', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TapToPayCard(onTap: () => taps++)),
          ),
        );

        final finder = find.bySemanticsLabel(RegExp(r'^Tap to Pay\n'));
        expect(finder, findsOneWidget);
        final node = tester.getSemantics(finder);
        final data = node.getSemanticsData();
        expect(
          data.label,
          'Tap to Pay\nPay at the machine reader with your mobile wallet.',
        );
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.tap,
            viewId: tester.view.viewId,
            nodeId: node.id,
          ),
        );
        await tester.pump();
        expect(taps, 1);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('without a callback the card has no button or tap action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TapToPayCard())),
        );
        final data = tester
            .getSemantics(find.text('Tap to Pay'))
            .getSemanticsData();
        expect(data.flagsCollection.isButton, isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
      } finally {
        semantics.dispose();
      }
    });

    Widget buildWidget() =>
        const MaterialApp(home: Scaffold(body: TapToPayCard()));

    testWidgets('displays Tap to Pay heading', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Tap to Pay'), findsOneWidget);
    });

    testWidgets('displays description text', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(
        find.text('Pay at the machine reader with your mobile wallet.'),
        findsOneWidget,
      );
    });

    testWidgets('displays tap_and_play icon', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.byIcon(Icons.tap_and_play), findsOneWidget);
    });

    testWidgets('invokes onTap when pressed', (tester) async {
      var didTap = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TapToPayCard(onTap: () => didTap = true)),
        ),
      );

      await tester.tap(find.text('Tap to Pay'));

      expect(didTap, isTrue);
    });
  });
}
