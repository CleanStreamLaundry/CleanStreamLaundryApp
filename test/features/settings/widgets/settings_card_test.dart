import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/settings/widgets/settings_card.dart';

void main() {
  testWidgets('declared control width preserves a fitting row', (tester) async {
    Future<List<Rect>> render(double? controlWidth) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lightMode,
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: SettingsCard(
                icon: Icons.timer,
                title: 'Timer',
                subtitle: 'Minutes',
                trailingWidth: controlWidth,
                trailing: const SizedBox(width: 118, child: Icon(Icons.add)),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      return [
        tester.getRect(find.byType(SettingsCard)),
        tester.getRect(find.text('Timer')),
        tester.getRect(find.text('Minutes')),
        tester.getRect(find.byIcon(Icons.timer)),
        tester.getRect(find.byIcon(Icons.add)),
      ];
    }

    final originalLayout = await render(null);
    expect(await render(118), originalLayout);
  });

  testWidgets('dark subtitle and destructive label have readable contrast', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkMode,
        home: const Scaffold(
          body: Column(
            children: [
              SettingsCard(
                icon: Icons.timer,
                title: 'Notify Before Finish',
                subtitle: "Minutes you're notified before machine finish",
              ),
              SettingsCard(
                icon: Icons.logout,
                title: 'Sign Out',
                isDestructive: true,
              ),
            ],
          ),
        ),
      ),
    );

    for (final label in [
      "Minutes you're notified before machine finish",
      'Sign Out',
    ]) {
      final foreground = tester.widget<Text>(find.text(label)).style!.color!;
      final background = darkMode.cardColor;
      final luminance = Color.alphaBlend(
        foreground,
        background,
      ).computeLuminance();
      final surface = background.computeLuminance();
      final ratio = luminance > surface
          ? (luminance + 0.05) / (surface + 0.05)
          : (surface + 0.05) / (luminance + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: label);
    }
    expect(
      tester.widget<Icon>(find.byIcon(Icons.logout)).color,
      Colors.red.shade700,
    );
  });

  group('SettingsCard Widget Tests', () {
    testWidgets('tappable rows expose labeled button actions', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final title in ['Privacy', 'Sign Out']) {
          var taps = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SettingsCard(
                  icon: Icons.settings,
                  title: title,
                  subtitle: 'Account settings',
                  isDestructive: title == 'Sign Out',
                  onTap: () => taps++,
                ),
              ),
            ),
          );

          final node = tester.getSemantics(find.text(title));
          final data = node.getSemanticsData();
          expect(data.label, '$title\nAccount settings');
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
        }
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('untappable rows preserve independent trailing controls', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var increments = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsCard(
                icon: Icons.timer,
                title: 'Timer',
                trailing: IconButton(
                  tooltip: 'Increase notification lead time',
                  onPressed: () => increments++,
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        );

        final row = tester.getSemantics(find.text('Timer'));
        final rowData = row.getSemanticsData();
        expect(rowData.label, 'Timer');
        expect(rowData.flagsCollection.isButton, isFalse);
        expect(rowData.hasAction(SemanticsAction.tap), isFalse);

        final control = tester.getSemantics(find.byType(IconButton));
        final controlData = control.getSemanticsData();
        expect(control.id, isNot(row.id));
        expect(controlData.tooltip, 'Increase notification lead time');
        expect(controlData.flagsCollection.isButton, isTrue);
        expect(controlData.hasAction(SemanticsAction.tap), isTrue);
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.tap,
            viewId: tester.view.viewId,
            nodeId: control.id,
          ),
        );
        await tester.pump();
        expect(increments, 1);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('renders with title and icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              icon: Icons.settings,
              title: 'Settings',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);

      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('renders with subtitle when provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              icon: Icons.notifications,
              title: 'Notifications',
              subtitle: 'Manage your notification preferences',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Manage your notification preferences'), findsOneWidget);
      expect(find.byIcon(Icons.notifications), findsOneWidget);
    });

    testWidgets('does not render subtitle when null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              icon: Icons.account_circle,
              title: 'Account',
              subtitle: null,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Account'), findsOneWidget);

      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      expect(textWidgets.length, 1);
    });

    testWidgets('calls onTap when tapped', (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              icon: Icons.privacy_tip,
              title: 'Privacy',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();

      expect(tapped, true);
    });

    testWidgets('renders as a flat tappable row', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(icon: Icons.help, title: 'Help', onTap: () {}),
          ),
        ),
      );

      expect(find.byType(Card), findsNothing);
      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('displays correct icon', (WidgetTester tester) async {
      const testIcon = Icons.security;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(icon: testIcon, title: 'Security', onTap: () {}),
          ),
        ),
      );

      expect(find.byIcon(testIcon), findsOneWidget);
    });

    testWidgets('text uses theme colors', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          ),
          home: Scaffold(
            body: SettingsCard(
              icon: Icons.palette,
              title: 'Theme',
              subtitle: 'Customize appearance',
              onTap: () {},
            ),
          ),
        ),
      );

      final titleText = tester.widget<Text>(find.text('Theme'));
      expect(titleText.style?.fontSize, 15);
      expect(titleText.style?.fontWeight, FontWeight.w600);

      final subtitleText = tester.widget<Text>(
        find.text('Customize appearance'),
      );
      expect(subtitleText.style?.fontSize, 12);
    });

    testWidgets('handles long text without overflow', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              icon: Icons.text_fields,
              title: 'Very Long Title That Should Not Overflow The Card Width',
              subtitle:
                  'This is a very long subtitle that should also handle gracefully without causing any overflow issues',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders trailing widgets when provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              icon: Icons.timer,
              title: 'Timer',
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('renders optional chevron', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              icon: Icons.person,
              title: 'Edit Profile',
              showChevron: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('supports destructive styling', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              icon: Icons.logout,
              title: 'Sign Out',
              isDestructive: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final titleText = tester.widget<Text>(find.text('Sign Out'));
      final icon = tester.widget<Icon>(find.byIcon(Icons.logout));

      expect(titleText.style?.color, Colors.red.shade700);
      expect(icon.color, Colors.red.shade700);
    });
  });
}
