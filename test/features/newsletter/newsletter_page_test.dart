import 'dart:async';
import 'dart:io';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/newsletter/newsletter_page.dart';
import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'fixtures.dart';

// Read only repository images; no .env, remote assets, or asset manifest needed.
class _FixtureAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    }
    if (!['assets/Icon.png', 'assets/Slogan.png'].contains(key)) {
      throw StateError('Unexpected fixture asset: $key');
    }
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

void main() {
  late NewsletterFixture fixture;
  late GoRouter router;
  setUp(() {
    fixture = NewsletterFixture();
    router = GoRouter(
      initialLocation: '/newsletter',
      routes: [
        GoRoute(
          path: '/newsletter',
          builder: (_, _) => NewsletterPage(
            authService: fixture.auth,
            profileService: fixture.profile,
          ),
        ),
        GoRoute(
          path: '/away',
          builder: (_, _) => const Scaffold(body: Text('Away')),
        ),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    await fixture.events.close();
  });
  Future<void> mount(
    WidgetTester tester, {
    ThemeData? theme,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _FixtureAssets(),
        child: MaterialApp.router(
          theme: (theme ?? lightMode).copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'optional purpose consent starts unchecked; request shows truthful pending',
    (tester) async {
      await mount(tester);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(find.text(newsletter().consentText), findsOneWidget);
      expect(
        find.text('Consent version: synthetic-newsletter-v2'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((widget) => widget is FilledButton),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Request subscription'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Confirmation pending.'), findsOneWidget);
      expect(find.textContaining('Email delivery is unknown.'), findsOneWidget);
      expect(find.text('Withdraw request'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      verify(
        () => fixture.profile.requestNewsletter('synthetic-newsletter-v2'),
      ).called(1);
    },
  );

  for (final state in ['expired', 'suppressed', 'subscribed', 'unsubscribed']) {
    testWidgets('$state is honest and only offers applicable actions', (
      tester,
    ) async {
      when(
        () => fixture.profile.getNewsletterStatus(),
      ).thenAnswer((_) async => newsletter(state: state));
      await mount(tester);
      expect(
        find.textContaining(switch (state) {
          'expired' => 'Confirmation expired.',
          'suppressed' => 'Newsletter email is suppressed.',
          'subscribed' => 'Subscribed.',
          _ => 'Unsubscribed.',
        }),
        findsOneWidget,
      );
      expect(
        find.byType(CheckboxListTile),
        ['expired', 'unsubscribed'].contains(state)
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.text('Unsubscribe'),
        state == 'subscribed' ? findsOneWidget : findsNothing,
      );
      verifyNever(() => fixture.profile.requestNewsletter(any()));
    });
  }

  testWidgets('disabled pending still offers withdrawal, no enrollment', (
    tester,
  ) async {
    when(
      () => fixture.profile.getNewsletterStatus(),
    ).thenAnswer((_) async => newsletter(state: 'pending', enabled: false));
    await mount(tester);
    expect(find.textContaining('currently disabled'), findsOneWidget);
    await tester.tap(find.text('Withdraw request'));
    await tester.pumpAndSettle();
    expect(find.text('Unsubscribed.'), findsOneWidget);
    verify(() => fixture.profile.withdrawNewsletter()).called(1);
  });

  testWidgets(
    'refresh preserves content, blocks duplicate actions, exposes stale failure',
    (tester) async {
      await mount(tester);
      final pending = Completer<NewsletterStatus>();
      when(
        () => fixture.profile.getNewsletterStatus(),
      ).thenAnswer((_) => pending.future);
      await tester.tap(find.byTooltip('Refresh newsletter status'));
      await tester.pump();
      expect(find.text('Not subscribed.'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      pending.completeError(StateError('synthetic offline'));
      await tester.pumpAndSettle();
      expect(find.text('Not subscribed.'), findsOneWidget);
      expect(find.textContaining('out of date'), findsOneWidget);
    },
  );

  testWidgets('A-B-A clears optional intent and old content immediately', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byType(Checkbox));
    final original = fixture.session;
    fixture.change(sessionFixture(id: subjectB));
    fixture.change(original);
    await tester.pumpAndSettle();
    expect(find.text('Not subscribed.'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.byTooltip('Refresh newsletter status'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    verifyNever(() => fixture.profile.requestNewsletter(any()));
  });

  for (final fails in [false, true]) {
    testWidgets('disposed page ignores late mutation fails=$fails', (
      tester,
    ) async {
      await mount(tester);
      final pending = Completer<NewsletterStatus>();
      when(
        () => fixture.profile.requestNewsletter(any()),
      ).thenAnswer((_) => pending.future);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Request subscription'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      verify(() => fixture.profile.requestNewsletter(any())).called(1);
      router.go('/away');
      await tester.pumpAndSettle();
      if (fails) {
        pending.completeError(StateError('synthetic'));
      } else {
        pending.complete(newsletter(state: 'pending'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Away'), findsOneWidget);
      expect(tester.takeException(), isNull);
      verify(() => fixture.profile.getNewsletterStatus()).called(1);
    });
  }

  for (final theme in [lightMode, darkMode]) {
    testWidgets('${theme.brightness.name} narrow large text fits and scrolls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, theme: theme, scale: 2);
      await tester.ensureVisible(find.byTooltip('Refresh newsletter status'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Newsletter preferences'), findsOneWidget);
    });
  }
}
