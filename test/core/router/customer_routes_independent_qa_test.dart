import 'dart:async';

import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'package:clean_stream_laundry_app/features/admission/admission.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/features/admission/gate.dart';
import 'package:clean_stream_laundry_app/features/home/home.dart';
import 'package:clean_stream_laundry_app/features/login/login.dart';
import 'package:clean_stream_laundry_app/features/loyalty/loyalty.dart';
import 'package:clean_stream_laundry_app/features/loyalty/widgets/transaction_list.dart';
import 'package:clean_stream_laundry_app/features/mfa/mfa.dart';
import 'package:clean_stream_laundry_app/features/newsletter/newsletter_page.dart';
import 'package:clean_stream_laundry_app/features/settings/settings.dart';
import 'package:clean_stream_laundry_app/features/settings/widgets/settings_card.dart';
import 'package:clean_stream_laundry_app/features/topup_refunds/topup_refunds.dart';
import 'package:clean_stream_laundry_app/logic/enums/payment_result_enum.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/admission/mocks.dart';
import '../../features/home/mocks.dart'
    show MockLocationService, MockMachineService;
import '../../features/loyalty/mocks.dart' show MockPaymentProcessor;
import '../../features/mfa/fixtures.dart' as mfa;
import '../../features/newsletter/fixtures.dart' show newsletter;
import '../../features/settings/mocks.dart'
    show MockThemeManager, MockTransactionService;
import '../../features/topup_refunds/fixtures.dart';

void main() {
  late RefundHarness h;
  late MockAdmissionProfileService profiles;
  late MockPaymentProcessor payments;
  late AdmissionController admission;
  late AdmissionStatus result;
  GoRouter? router;
  Future<AdmissionStatus>? heldAdmission;
  var balanceReads = 0;
  var paidCents = 2000;
  var newsletterReads = 0;

  AdmissionStatus status({
    String step = 'home',
    String? reason,
    bool pending = false,
  }) => AdmissionStatus.fromJson({
    'subject_id': h.session!.user.id,
    'account_access': const ['home', 'review_terms'].contains(step)
        ? 'eligible'
        : 'restricted',
    'next_step': step,
    'reason': reason,
    'account_state': pending ? 'pending_deletion' : 'legacy_active',
    'restore_until': pending
        ? (reason == 'restore_expired'
              ? '2020-01-01T00:00:00Z'
              : '2099-01-01T00:00:00Z')
        : null,
  });

  setUpAll(() => registerFallbackValue(DateTime(2026)));
  setUp(() {
    h = RefundHarness()..register();
    profiles = MockAdmissionProfileService();
    payments = MockPaymentProcessor();
    result = status();
    heldAdmission = null;
    balanceReads = newsletterReads = 0;
    paidCents = 2000;
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) => heldAdmission ?? Future.value(result));
    when(
      () => h.auth.onAuthChange,
    ).thenAnswer((_) => h.changes.stream.map((event) => event.session != null));
    when(() => h.auth.listMfaFactors()).thenAnswer(
      (_) async => AuthMFAListFactorsResponse(
        all: [mfa.factor()],
        totp: [mfa.factor()],
        phone: [],
      ),
    );
    when(() => h.auth.getMfaAssurance()).thenReturn(
      AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: AuthenticatorAssuranceLevels.aal1,
        nextLevel: AuthenticatorAssuranceLevels.aal2,
        currentAuthenticationMethods: [],
      ),
    );
    when(
      () => profiles.getUserBalanceById(any()),
    ).thenAnswer((_) async => {'full_name': 'QA', 'reward_tracker': 0});
    when(() => profiles.getNotificationLeadTime()).thenAnswer((_) async => 5);
    when(() => profiles.getCurrentUserRole()).thenAnswer((_) async => null);
    when(() => profiles.getNewsletterStatus()).thenAnswer((_) async {
      newsletterReads++;
      return newsletter(subject: h.session!.user.id);
    });
    when(
      () => profiles.requestNewsletter(any()),
    ).thenAnswer((_) async => newsletter(state: 'pending'));
    when(
      () => profiles.withdrawNewsletter(),
    ).thenAnswer((_) async => newsletter(state: 'unsubscribed'));
    when(() => h.wallet.getBalance()).thenAnswer((_) async {
      balanceReads++;
      return WalletBalance(
        walletAccountId: 'qa-wallet',
        status: 'active',
        paidBalanceCents: paidCents,
        promoBalanceCents: 0,
        totalBalanceCents: paidCents,
      );
    });
    when(
      () => h.wallet.getLedger(
        userId: any(named: 'userId'),
        walletAccountId: any(named: 'walletAccountId'),
        since: any(named: 'since'),
        rewardsOnly: any(named: 'rewardsOnly'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => payments.processPayment(any(), any()),
    ).thenAnswer((_) async => PaymentResult.canceled);
    final locations = MockLocationService();
    when(() => locations.getLocations()).thenAnswer((_) async => []);
    GetIt.I.registerSingleton<ProfileService>(profiles);
    GetIt.I.registerSingleton<PaymentProcessor>(payments);
    GetIt.I.registerSingleton<LocationService>(locations);
    GetIt.I.registerSingleton<MachineService>(MockMachineService());
    GetIt.I.registerSingleton<TransactionService>(MockTransactionService());
    SharedPreferences.setMockInitialValues({});
    admission = AdmissionController(
      authService: h.auth,
      profileService: profiles,
    );
  });

  void qa(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await body(tester);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        router?.dispose();
        router = null;
        admission.dispose();
        await h.dispose();
      }
    });
  }

  Future<void> mount(
    WidgetTester tester,
    String path, {
    double textScale = 1,
  }) async {
    router = RouterService().createRouter(
      h.auth,
      admission: admission,
      profiles: profiles,
    )..go(path);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeManager>.value(
        value: MockThemeManager(),
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> go(WidgetTester tester, String path) async {
    router!.go(path);
    await tester.pumpAndSettle();
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openRefund(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Request full refund'));
    await tester.tap(find.text('Request full refund'));
    await tester.pumpAndSettle();
    expect(find.text('Request full top-up refund?'), findsOneWidget);
  }

  Future<void> consentNewsletter(WidgetTester tester) async {
    final checkbox = find.byType(CheckboxListTile);
    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
  }

  for (final reason in ['explicit_restore_required', 'restore_expired']) {
    qa('real router $reason grants refunds only and Back returns to recovery', (
      tester,
    ) async {
      result = status(step: 'blocked', reason: reason, pending: true);
      await mount(tester, '/admission');
      expect(
        find.text('Restore account'),
        reason == 'restore_expired' ? findsNothing : findsOneWidget,
      );
      await tester.tap(find.text('Top-up refunds'));
      await tester.pumpAndSettle();
      expect(router!.routeInformationProvider.value.uri.path, '/topup-refunds');
      expect(find.byType(TopupRefundsPage), findsOneWidget);
      expect(admission.canUseTopupRefunds, isTrue);
      expect(admission.canEnterHome, isFalse);
      expect(h.topupReads, 1);
      await openRefund(tester);
      await tester.tap(find.text('Confirm request'));
      await tester.pumpAndSettle();
      expect(h.writes, 1);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(router!.routeInformationProvider.value.uri.path, '/admission');
      for (final path in [
        '/homePage',
        '/loyalty?loadCard=true',
        '/newsletter',
      ]) {
        await go(tester, path);
        expect(find.byType(AdmissionPage), findsOneWidget);
        expect(find.byType(HomePage), findsNothing);
        expect(find.byType(LoyaltyPage), findsNothing);
        expect(find.byType(NewsletterPage), findsNothing);
        expect(find.text('Pay'), findsNothing);
      }
      expect(balanceReads, 0);
      expect(newsletterReads, 0);
      verifyNever(() => payments.processPayment(any(), any()));
      verifyNever(() => profiles.restoreAccount());
    });
  }

  for (final step in ['verify_email', 'enroll_totp', 'challenge_totp']) {
    for (final path in ['/topup-refunds', '/newsletter']) {
      qa(
        'pending account $step cannot enter $path before current security checks',
        (tester) async {
          result = status(step: step, pending: true);
          await mount(tester, path);
          expect(admission.canUseTopupRefunds, isFalse);
          expect(admission.canEnterHome, isFalse);
          expect(find.byType(TopupRefundsPage), findsNothing);
          expect(find.byType(NewsletterPage), findsNothing);
          expect(
            find.byType(step == 'verify_email' ? AdmissionPage : MfaPage),
            findsOneWidget,
          );
          expect(
            (h.topupReads, h.refundReads, h.writes, newsletterReads),
            (0, 0, 0, 0),
          );
          verifyNever(() => profiles.requestNewsletter(any()));
        },
      );
    }
  }

  qa(
    'refund confirmation is below admission and inactive throughout a soft check',
    (tester) async {
      await mount(tester, '/topup-refunds');
      await openRefund(tester);
      final dialogContext = tester.element(find.byType(AlertDialog));
      expect(
        Navigator.of(dialogContext),
        isNot(same(Navigator.of(dialogContext, rootNavigator: true))),
      );
      expect(
        find.ancestor(
          of: find.byType(AlertDialog),
          matching: find.byType(AdmissionGate),
        ),
        findsOneWidget,
      );
      final pending = Completer<AdmissionStatus>();
      heldAdmission = pending.future;
      final check = admission.revalidate();
      await frames(tester);
      expect(
        tester.widget<TopupRefundsPage>(find.byType(TopupRefundsPage)).active,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm request'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Confirm request'), warnIfMissed: false);
      expect(h.writes, 0);
      pending.complete(result);
      heldAdmission = null;
      await tester.pumpAndSettle();
      await check;
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm request'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await openRefund(tester);
      await tester.tap(find.text('Confirm request'));
      await tester.pumpAndSettle();
      expect(h.writes, 1);
    },
  );

  qa('new MFA restriction removes an already open refund dialog', (
    tester,
  ) async {
    await mount(tester, '/topup-refunds');
    await openRefund(tester);
    result = status(step: 'challenge_totp');
    unawaited(admission.revalidate());
    await tester.pumpAndSettle();
    expect(find.byType(MfaPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.writes, 0);
  });

  for (final leave in [false, true]) {
    for (final fail in [false, true]) {
      qa(
        'refund late ${fail ? 'error' : 'ack'} after ${leave ? 'route exit' : 'A-B-A'} cannot repopulate or navigate',
        (tester) async {
          final pending = Completer<TopupRefund>();
          h.nextWrite = pending.future;
          final original = h.session;
          await mount(tester, '/topup-refunds');
          await openRefund(tester);
          await tester.tap(find.text('Confirm request'));
          await frames(tester);
          expect(h.writes, 1);
          expect(h.dispatchedSessions.single, same(original));
          if (leave) {
            router!.go('/legal/privacy');
          } else {
            h.change(refundSession(id: customerB));
            h.change(original);
          }
          await frames(tester);
          final reads = (h.topupReads, h.refundReads);
          final uri = router!.routeInformationProvider.value.uri;
          if (fail) {
            pending.completeError(Exception('late response'));
          } else {
            pending.complete(TopupRefund.fromJson(refundJson()));
          }
          await tester.pumpAndSettle();
          expect(router!.routeInformationProvider.value.uri, uri);
          expect((h.topupReads, h.refundReads), reads);
          expect(h.writes, 1);
          expect(find.textContaining('Request recorded.'), findsNothing);
          expect(
            find.textContaining('outcome is not yet confirmed'),
            findsNothing,
          );
        },
      );
    }
  }

  for (final newerAccount in [false, true]) {
    qa(
      newerAccount
          ? 'Settings sign-out completion preserves a newer account route'
          : 'Settings sign-out completion reaches Login after admission disposes Settings',
      (tester) async {
        final logout = Completer<void>();
        when(() => h.auth.logout()).thenAnswer((_) => logout.future);
        await mount(tester, '/settings');
        final settingsState = tester.state(find.byType(Settings));
        expect(
          find.ancestor(
            of: find.byType(Settings),
            matching: find.byType(AdmissionGate),
          ),
          findsOneWidget,
        );
        final signOut = find.widgetWithText(SettingsCard, 'Sign Out');
        await tester.ensureVisible(signOut);
        await tester.tap(signOut);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Out'));
        await tester.pumpAndSettle();
        verify(() => h.auth.logout()).called(1);

        h.change(null);
        await tester.pumpAndSettle();
        expect(logout.isCompleted, isFalse);
        expect(settingsState.mounted, isFalse);
        expect(find.byType(Settings), findsNothing);
        expect(find.byType(AdmissionPage), findsOneWidget);
        expect(
          router!.routerDelegate.currentConfiguration.uri.path,
          '/settings',
        );

        final replacement = newerAccount ? refundSession(id: customerB) : null;
        if (replacement != null) {
          h.change(replacement);
          result = status();
          await go(tester, '/homePage');
          expect(find.byType(HomePage), findsOneWidget);
        }

        logout.complete();
        await tester.pumpAndSettle();
        expect(h.auth.currentSession, same(replacement));
        expect(
          router!.routerDelegate.currentConfiguration.uri.path,
          newerAccount ? '/homePage' : '/login',
        );
        expect(
          find.byType(Login),
          newerAccount ? findsNothing : findsOneWidget,
        );
        expect(find.byType(AdmissionPage), findsNothing);
        if (newerAccount) expect(find.byType(HomePage), findsOneWidget);
      },
    );
  }

  qa(
    'Settings newsletter entry is distinct and requires unchecked purpose consent',
    (tester) async {
      await mount(tester, '/settings');
      final entry = find.widgetWithText(SettingsCard, 'Newsletter');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(router!.routeInformationProvider.value.uri.path, '/newsletter');
      expect(
        find.ancestor(
          of: find.byType(NewsletterPage),
          matching: find.byType(AdmissionGate),
        ),
        findsOneWidget,
      );
      verifyNever(() => profiles.requestNewsletter(any()));
      await consentNewsletter(tester);
      await tester.tap(find.text('Request subscription'));
      await tester.pumpAndSettle();
      verify(
        () => profiles.requestNewsletter('synthetic-newsletter-v2'),
      ).called(1);
      expect(
        find.textContaining('not subscribed until you confirm'),
        findsOneWidget,
      );
      expect(h.writes, 0);
    },
  );

  qa(
    'newsletter consent cannot dispatch while shell admission is unconfirmed',
    (tester) async {
      await mount(tester, '/newsletter');
      await consentNewsletter(tester);
      final pending = Completer<AdmissionStatus>();
      heldAdmission = pending.future;
      final check = admission.revalidate();
      await frames(tester);
      await tester.tap(find.text('Request subscription'), warnIfMissed: false);
      await frames(tester);
      verifyNever(() => profiles.requestNewsletter(any()));
      pending.complete(result);
      heldAdmission = null;
      await tester.pumpAndSettle();
      await check;
    },
  );

  for (final leave in [false, true]) {
    for (final fail in [false, true]) {
      qa(
        'newsletter late ${fail ? 'error' : 'ack'} after ${leave ? 'route exit' : 'A-B-A'} stays detached',
        (tester) async {
          final pending = Completer<NewsletterStatus>();
          when(
            () => profiles.requestNewsletter(any()),
          ).thenAnswer((_) => pending.future);
          await mount(tester, '/newsletter');
          await consentNewsletter(tester);
          await tester.tap(find.text('Request subscription'));
          await frames(tester);
          verify(() => profiles.requestNewsletter(any())).called(1);
          if (leave) {
            router!.go('/legal/privacy');
          } else {
            final original = h.session;
            h.change(refundSession(id: customerB));
            h.change(original);
          }
          await frames(tester);
          final uri = router!.routeInformationProvider.value.uri;
          final reads = newsletterReads;
          if (fail) {
            pending.completeError(Exception('late response'));
          } else {
            pending.complete(newsletter(state: 'pending'));
          }
          await tester.pumpAndSettle();
          expect(router!.routeInformationProvider.value.uri, uri);
          expect(newsletterReads, reads);
          expect(find.textContaining('Confirmation pending.'), findsNothing);
          expect(
            find.textContaining('earlier change was not retried'),
            findsNothing,
          );
        },
      );
    }
  }

  qa('Wallet refund entry and return read authoritative changed balance', (
    tester,
  ) async {
    await mount(tester, '/loyalty');
    expect(
      tester
          .widget<TransactionList>(find.byType(TransactionList))
          .controller
          .userBalance,
      20,
    );
    final before = balanceReads;
    await tester.tap(find.byTooltip('Top-up refunds'));
    await tester.pumpAndSettle();
    expect(find.byType(TopupRefundsPage), findsOneWidget);
    await openRefund(tester);
    await tester.tap(find.text('Confirm request'));
    await tester.pumpAndSettle();
    expect(h.writes, 1);
    paidCents = 0;
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router!.routeInformationProvider.value.uri.path, '/loyalty');
    expect(balanceReads, greaterThan(before));
    expect(
      tester
          .widget<TransactionList>(find.byType(TransactionList))
          .controller
          .userBalance,
      0,
    );
    verifyNever(() => payments.processPayment(any(), any()));
  });

  for (final scale in [1.0, 2.0]) {
    qa('Wallet title actions fit at 320px and ${scale}x text', (tester) async {
      tester.view.physicalSize = const Size(320, 1100);
      await mount(tester, '/loyalty', textScale: scale);
      expect(
        tester.takeException(),
        isNull,
        reason: 'No narrow-screen layout overflow',
      );
      final refund = find.byTooltip('Top-up refunds');
      final refresh = find.byTooltip('Refresh wallet');
      final rewards = find.byKey(const ValueKey('rewards-sheet-button'));
      final title = find
          .descendant(
            of: find.byType(LoyaltyPage),
            matching: find.text('Wallet'),
          )
          .first;
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.didExceedMaxLines, isFalse);
      final boxes = [
        title,
        refresh,
        refund,
        rewards,
      ].map(tester.getRect).toList();
      for (final box in boxes) {
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(320));
      }
      for (var i = 0; i < boxes.length - 1; i++) {
        expect(boxes[i].overlaps(boxes[i + 1]), isFalse);
      }
      expect(refund.hitTestable(), findsOneWidget);
      expect(refresh.hitTestable(), findsOneWidget);
      expect(rewards.hitTestable(), findsOneWidget);
      await tester.tap(refund);
      await tester.pumpAndSettle();
      expect(find.byType(TopupRefundsPage), findsOneWidget);
      expect(router!.routeInformationProvider.value.uri.path, '/topup-refunds');
    });
  }

  for (final path in ['/homePage', '/loyalty', '/newsletter']) {
    qa(
      'fresh pending-deletion verdict replaces $path with refund/recovery access',
      (tester) async {
        await mount(tester, path);
        result = status(
          step: 'blocked',
          reason: 'explicit_restore_required',
          pending: true,
        );
        unawaited(admission.revalidate());
        await tester.pumpAndSettle();
        expect(admission.canEnterHome, isFalse);
        expect(admission.canUseTopupRefunds, isTrue);
        expect(
          find.byType(AdmissionPage),
          findsOneWidget,
          reason:
              'A resolved lifecycle restriction must expose recovery/refunds, not leave the old route frozen.',
        );
        expect(find.text('Restore account'), findsOneWidget);
        expect(find.text('Top-up refunds').hitTestable(), findsOneWidget);
        expect(find.byType(HomePage), findsNothing);
        expect(find.byType(LoyaltyPage), findsNothing);
        expect(find.byType(NewsletterPage), findsNothing);
      },
    );
  }
}
