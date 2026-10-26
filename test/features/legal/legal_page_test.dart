import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/legal/legal_page.dart';
import 'package:clean_stream_laundry_app/features/legal/legal_drafts.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:crypto/crypto.dart';

class _ProfileService extends Mock implements ProfileService {}

LoyaltyPolicyDescriptor _descriptor() => LoyaltyPolicyDescriptor.fromJson({
  'required_version': 'review-only-synthetic',
  'policy_text': 'abc',
  'policy_sha256':
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
});

void main() {
  late _ProfileService service;
  late GoRouter router;

  setUp(() {
    service = _ProfileService();
    when(
      () => service.getLoyaltyPolicyDescriptor(),
    ).thenAnswer((_) async => _descriptor());
    router = GoRouter(
      initialLocation: '/legal',
      routes: [
        GoRoute(
          path: '/legal',
          builder: (_, _) => LegalPage(
            type: LegalPageType.loyaltyCard,
            profileService: service,
          ),
        ),
        GoRoute(
          path: '/privacy',
          builder: (_, _) =>
              LegalPage(type: LegalPageType.privacy, profileService: service),
        ),
        GoRoute(
          path: '/terms',
          builder: (_, _) =>
              LegalPage(type: LegalPageType.terms, profileService: service),
        ),
        GoRoute(
          path: '/away',
          builder: (_, _) => const Scaffold(body: Text('Away')),
        ),
      ],
    );
  });
  tearDown(() => router.dispose());

  for (final theme in [lightMode, darkMode]) {
    testWidgets(
      '${theme.brightness.name} formatted sections are selectable at large text',
      (tester) async {
        final content = jsonEncode({
          'title': 'Loyalty Program Terms',
          'effective_date': '2026-10-02',
          'sections': [
            {
              'heading': 'Paid credits',
              'paragraphs': [
                'Paid credits do not expire.',
                'Pending refunds survive deletion.',
              ],
            },
            {
              'heading': 'Promotional credits',
              'paragraphs': ['Promotional credits are canceled on deletion.'],
            },
          ],
        });
        final descriptor = LoyaltyPolicyDescriptor.fromJson({
          'required_version': 'loyalty-2026-10-02',
          'policy_text': content,
          'policy_sha256': sha256.convert(utf8.encode(content)).toString(),
        });
        when(
          () => service.getLoyaltyPolicyDescriptor(),
        ).thenAnswer((_) async => descriptor);
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: theme,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                boldText: true,
              ),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final logo = tester.widget<Image>(
          find.descendant(
            of: find.byType(LoyaltyPolicyText),
            matching: find.byType(Image),
          ),
        );
        expect((logo.image as AssetImage).assetName, 'assets/splash-logo.png');
        expect(logo.semanticLabel, 'Clean Stream Laundry Solutions');
        expect(logo.fit, BoxFit.contain);
        for (final text in [
          'Loyalty Program Terms',
          'Effective October 2, 2026',
          'Version: loyalty-2026-10-02',
          'Paid credits',
          'Paid credits do not expire.',
          'Pending refunds survive deletion.',
          'Promotional credits',
          'Promotional credits are canceled on deletion.',
        ]) {
          final finder = find.widgetWithText(SelectableText, text);
          expect(finder, findsOneWidget);
          final style = tester.widget<SelectableText>(finder).style!;
          final isHeading = const {
            'Loyalty Program Terms',
            'Paid credits',
            'Promotional credits',
          }.contains(text);
          final isMetadata =
              text.startsWith('Effective ') || text.startsWith('Version:');
          expect(
            style.color,
            isHeading
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(
                    alpha: isMetadata ? 0.62 : 0.78,
                  ),
          );
          expect(
            style.fontWeight,
            isHeading ? FontWeight.w600 : FontWeight.w400,
          );
          expect(style.letterSpacing, 0);
          final a = Color.alphaBlend(
            style.color!,
            theme.colorScheme.surface,
          ).computeLuminance();
          final b = theme.colorScheme.surface.computeLuminance();
          expect(
            (a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05)),
            greaterThanOrEqualTo(4.5),
          );
        }
        TextStyle styleOf(String text) => tester
            .widget<SelectableText>(find.widgetWithText(SelectableText, text))
            .style!;
        expect(styleOf('Loyalty Program Terms').fontSize, 22);
        expect(styleOf('Paid credits').fontSize, 16);
        expect(styleOf('Paid credits do not expire.').fontSize, 14);
        expect(styleOf('Effective October 2, 2026').fontSize, 12);
        expect(find.text(content), findsNothing);
        expect(find.textContaining('SHA-256'), findsNothing);
        expect(find.text('Loyalty Card Terms'), findsNothing);
        await tester.ensureVisible(find.text('Public website terms'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        verify(() => service.getLoyaltyPolicyDescriptor()).called(1);
      },
    );
  }

  Future<void> mount(WidgetTester tester, {ThemeData? theme}) async {
    await tester.pumpWidget(
      MaterialApp.router(theme: theme, routerConfig: router),
    );
    await tester.pumpAndSettle();
  }

  for (final theme in [lightMode, darkMode]) {
    for (final route in ['/privacy', '/terms', '/legal']) {
      testWidgets('${theme.brightness.name} $route public action is readable', (
        tester,
      ) async {
        router.go(route);
        await mount(tester, theme: theme);
        final label = route == '/legal'
            ? 'Public website terms'
            : 'Open public website';
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        );
        final material = tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)),
        );
        final foreground = DefaultTextStyle.of(
          tester.element(find.text(label)),
        ).style.color!;
        final iconColor = IconTheme.of(
          tester.element(
            find.descendant(
              of: button,
              matching: find.byIcon(Icons.open_in_new),
            ),
          ),
        ).color;
        final a = foreground.computeLuminance();
        final b = material.color!.computeLuminance();
        final contrast = a > b
            ? (a + 0.05) / (b + 0.05)
            : (b + 0.05) / (a + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5));
        expect(material.color, theme.colorScheme.primary);
        expect(foreground, Colors.white);
        expect(iconColor, Colors.white);
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        expect(
          tester.widget<LegalPage>(find.byType(LegalPage)).publicUrl,
          Uri.parse(
            'https://cleanstreamlaundry.com${route == '/privacy' ? '/privacy' : '/terms'}',
          ),
        );
        if (route == '/legal') {
          verify(() => service.getLoyaltyPolicyDescriptor()).called(1);
          verifyNoMoreInteractions(service);
        } else {
          verifyZeroInteractions(service);
        }
      });
    }
  }

  testWidgets(
    'public descriptor renders selectable text and version without hash or consent',
    (tester) async {
      await mount(tester);
      expect(find.text('abc'), findsOneWidget);
      expect(find.text('Review-only draft'), findsNothing);
      expect(find.text('Version: review-only-synthetic'), findsOneWidget);
      expect(find.text('SHA-256: ${_descriptor().policySha256}'), findsNothing);
      expect(find.byType(SelectableText), findsNWidgets(3));
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Accept and Continue'), findsNothing);
      verify(() => service.getLoyaltyPolicyDescriptor()).called(1);
      verifyNoMoreInteractions(service);
    },
  );

  testWidgets(
    'shared descriptor renderer is read-only and preserves exact content',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LoyaltyPolicyText(descriptor: _descriptor())),
        ),
      );
      expect(find.text('abc'), findsOneWidget);
      expect(find.text('Version: review-only-synthetic'), findsOneWidget);
      expect(find.text('SHA-256: ${_descriptor().policySha256}'), findsNothing);
      expect(find.byType(SelectableText), findsNWidgets(3));
      expect(find.byType(Checkbox), findsNothing);
      verifyZeroInteractions(service);
    },
  );

  testWidgets(
    'failure stays public and explicit retry makes exactly one new request',
    (tester) async {
      when(
        () => service.getLoyaltyPolicyDescriptor(),
      ).thenAnswer((_) async => throw Exception('synthetic failure'));
      await mount(tester);
      expect(router.routeInformationProvider.value.uri.path, '/legal');
      expect(find.text('Unable to load the policy.'), findsOneWidget);
      expect(find.text('abc'), findsNothing);
      when(
        () => service.getLoyaltyPolicyDescriptor(),
      ).thenAnswer((_) async => _descriptor());
      await tester.tap(find.byTooltip('Retry policy'));
      await tester.pumpAndSettle();
      expect(find.text('abc'), findsOneWidget);
      expect(find.text('Unable to load the policy.'), findsNothing);
      verify(() => service.getLoyaltyPolicyDescriptor()).called(2);
      verifyNoMoreInteractions(service);
    },
  );

  testWidgets('refresh failure retains nonsensitive public text', (
    tester,
  ) async {
    await mount(tester);
    when(
      () => service.getLoyaltyPolicyDescriptor(),
    ).thenAnswer((_) async => throw TimeoutException('synthetic timeout'));
    await tester.tap(find.byTooltip('Refresh policy'));
    await tester.pumpAndSettle();
    expect(find.text('abc'), findsOneWidget);
    expect(find.text('Unable to load the policy.'), findsOneWidget);
    verify(() => service.getLoyaltyPolicyDescriptor()).called(2);
    verifyNoMoreInteractions(service);
  });

  testWidgets(
    'rebuild retains account-independent text and does not fetch again',
    (tester) async {
      await mount(tester);
      await tester.pumpWidget(
        MaterialApp.router(theme: ThemeData.dark(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('abc'), findsOneWidget);
      verify(() => service.getLoyaltyPolicyDescriptor()).called(1);
      verifyNoMoreInteractions(service);
    },
  );

  testWidgets('loading disables repeat requests', (tester) async {
    final pending = Completer<LoyaltyPolicyDescriptor>();
    when(
      () => service.getLoyaltyPolicyDescriptor(),
    ).thenAnswer((_) => pending.future);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    final control = find.widgetWithIcon(IconButton, Icons.refresh);
    expect(tester.widget<IconButton>(control).onPressed, isNull);
    await tester.tap(control);
    await tester.pump();
    verify(() => service.getLoyaltyPolicyDescriptor()).called(1);
    pending.complete(_descriptor());
    await tester.pumpAndSettle();
    verifyNoMoreInteractions(service);
  });

  testWidgets('replacement service ignores the previous request completion', (
    tester,
  ) async {
    final pending = Completer<LoyaltyPolicyDescriptor>();
    final replacement = _ProfileService();
    when(
      () => service.getLoyaltyPolicyDescriptor(),
    ).thenAnswer((_) => pending.future);
    when(() => replacement.getLoyaltyPolicyDescriptor()).thenAnswer(
      (_) async => LoyaltyPolicyDescriptor.fromJson({
        'required_version': 'review-only-newer',
        'policy_text': 'abc',
        'policy_sha256': _descriptor().policySha256,
      }),
    );
    final selected = ValueNotifier<ProfileService>(service);
    addTearDown(selected.dispose);
    router.dispose();
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ValueListenableBuilder<ProfileService>(
            valueListenable: selected,
            builder: (_, profile, _) => LegalPage(
              type: LegalPageType.loyaltyCard,
              profileService: profile,
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    selected.value = replacement;
    await tester.pumpAndSettle();
    pending.complete(_descriptor());
    await tester.pumpAndSettle();
    expect(find.text('Version: review-only-newer'), findsOneWidget);
    expect(find.text('Version: review-only-synthetic'), findsNothing);
    verify(() => service.getLoyaltyPolicyDescriptor()).called(1);
    verify(() => replacement.getLoyaltyPolicyDescriptor()).called(1);
  });

  for (final fail in [false, true]) {
    testWidgets('dispose ignores late ${fail ? 'failure' : 'success'}', (
      tester,
    ) async {
      final pending = Completer<LoyaltyPolicyDescriptor>();
      when(
        () => service.getLoyaltyPolicyDescriptor(),
      ).thenAnswer((_) => pending.future);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      router.go('/away');
      await tester.pumpAndSettle();
      if (fail) {
        pending.completeError(Exception('synthetic late failure'));
      } else {
        pending.complete(_descriptor());
      }
      await tester.pumpAndSettle();
      expect(find.text('Away'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final route in ['/privacy', '/terms']) {
    testWidgets('$route stays static and makes no policy request', (
      tester,
    ) async {
      router.go(route);
      await mount(tester);
      expect(
        find.text(route == '/privacy' ? 'Privacy Policy' : 'Terms of Service'),
        findsOneWidget,
      );
      expect(find.text('Open public website'), findsOneWidget);
      expect(find.text(legalDrafts['metadata'] as String), findsOneWidget);
      expect(find.text('Effective October 5, 2026'), findsOneWidget);
      expect(
        find.textContaining(
          RegExp(
            r'draft|not approved|not yet active|does not replace current terms',
            caseSensitive: false,
          ),
        ),
        findsNothing,
      );
      expect(find.byType(Checkbox), findsNothing);
      final key = route == '/privacy' ? 'privacy' : 'terms';
      final document = legalDrafts[key] as Map<String, dynamic>;
      for (final section in document['sections'] as List) {
        expect(
          find.widgetWithText(SelectableText, section['heading'] as String),
          findsOneWidget,
        );
        for (final paragraph in section['paragraphs'] as List) {
          expect(
            find.widgetWithText(SelectableText, paragraph as String),
            findsOneWidget,
          );
        }
      }
      verifyZeroInteractions(service);
    });
  }

  testWidgets('privacy preserves recovery and protects paid credits and refunds', (
    tester,
  ) async {
    router.go('/privacy');
    await mount(tester);
    expect(
      find.text(
        'A deletion request places your account in pending deletion and restricts ordinary access. You may explicitly restore the original account and its wallet links after verifying ownership and completing any required multi-factor authentication, before the exact server-set deadline 90 days after the request. The recovery screen shows the deadline and timezone. Signing in alone does not restore the account. At or after the deadline, restoration is unavailable even if cleanup has not occurred.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'By voluntarily requesting account deletion, you agree to surrender any remaining purchased and promotional laundry credit and unissued reward progress if you do not explicitly restore the account before the server-set 90-day recovery deadline. At that deadline, the remaining credit and reward progress are forfeited, except where applicable law prohibits forfeiture. Deletion does not convert credit into cash or entitle you to a refund. Creating a new account does not restore forfeited credit.',
      ),
      findsOneWidget,
    );
    verifyZeroInteractions(service);
  });

  for (final theme in [lightMode, darkMode]) {
    for (final route in ['/privacy', '/terms']) {
      testWidgets('${theme.brightness.name} $route policy supports large text', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        router.go(route);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: theme,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                boldText: true,
              ),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(legalDrafts['metadata'] as String), findsOneWidget);
        expect(find.widgetWithText(SelectableText, '12. Contact'), findsOneWidget);
        await tester.ensureVisible(find.text('Open public website'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(Checkbox), findsNothing);
        verifyZeroInteractions(service);
      });
    }
  }

  testWidgets('narrow large-text document is scrollable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Public website terms'));
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });
}
