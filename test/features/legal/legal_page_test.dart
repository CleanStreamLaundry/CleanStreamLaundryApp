import 'dart:async';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/legal/legal_page.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

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
            : 'View current policy';
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        );
        final material = tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)),
        );
        final foreground = DefaultTextStyle.of(tester.element(find.text(label)))
            .style
            .color!;
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
    'public descriptor renders exact selectable text, version and hash without consent',
    (tester) async {
      await mount(tester);
      expect(find.text('abc'), findsOneWidget);
      expect(find.text('Review-only draft'), findsOneWidget);
      expect(find.text('Version: review-only-synthetic'), findsOneWidget);
      expect(
        find.text('SHA-256: ${_descriptor().policySha256}'),
        findsOneWidget,
      );
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
      expect(
        find.text('SHA-256: ${_descriptor().policySha256}'),
        findsOneWidget,
      );
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
      expect(find.text('View current policy'), findsOneWidget);
      expect(find.text('Review-only draft'), findsNothing);
      verifyZeroInteractions(service);
    });
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
