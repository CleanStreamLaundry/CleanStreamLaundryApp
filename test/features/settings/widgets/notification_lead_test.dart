import 'dart:ui' show SemanticsAction;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_stream_laundry_app/features/settings/widgets/notification_lead.dart';

void main() {
  Widget createWidgetUnderTest({
    required int value,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    return MaterialApp(
      theme: lightMode,
      home: Scaffold(
        body: NotificationLead(
          value: value,
          onIncrement: onIncrement,
          onDecrement: onDecrement,
        ),
      ),
    );
  }

  testWidgets('renders value correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      createWidgetUnderTest(value: 5, onIncrement: () {}, onDecrement: () {}),
    );

    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('calls onIncrement when + button is tapped', (
    WidgetTester tester,
  ) async {
    bool incrementCalled = false;

    await tester.pumpWidget(
      createWidgetUnderTest(
        value: 0,
        onIncrement: () {
          incrementCalled = true;
        },
        onDecrement: () {},
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(incrementCalled, true);
  });

  testWidgets('calls onDecrement when - button is tapped', (
    WidgetTester tester,
  ) async {
    bool decrementCalled = false;

    await tester.pumpWidget(
      createWidgetUnderTest(
        value: 0,
        onIncrement: () {},
        onDecrement: () {
          decrementCalled = true;
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();

    expect(decrementCalled, true);
  });

  testWidgets('renders both control buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      createWidgetUnderTest(value: 1, onIncrement: () {}, onDecrement: () {}),
    );

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
  });

  testWidgets('lead-time controls expose named button actions', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        createWidgetUnderTest(value: 5, onIncrement: () {}, onDecrement: () {}),
      );
      for (final label in [
        'Decrease notification lead time',
        'Increase notification lead time',
      ]) {
        final button = find.ancestor(
          of: find.byTooltip(label),
          matching: find.byType(IconButton),
        );
        expect(button, findsOneWidget);
        final data = tester.getSemantics(button).getSemanticsData();
        expect(data.tooltip, label);
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('renders decrement before increment', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      createWidgetUnderTest(value: 1, onIncrement: () {}, onDecrement: () {}),
    );

    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();

    expect(icons[0].icon, Icons.remove);
    expect(icons[1].icon, Icons.add);
  });
}
