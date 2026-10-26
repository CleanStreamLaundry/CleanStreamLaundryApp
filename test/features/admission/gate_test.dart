import 'dart:async';

import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/features/admission/admission.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/features/admission/gate.dart';
import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mocks.dart';

void main() {
  late MockAdmissionAuthService auth;
  late MockAdmissionProfileService profiles;
  late StreamController<AuthState> events;
  late AdmissionController admission;
  Session? current;

  setUp(() {
    current = admissionSession(
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    auth = MockAdmissionAuthService();
    profiles = MockAdmissionProfileService();
    events = StreamController<AuthState>.broadcast();
    when(() => auth.currentSession).thenAnswer((_) => current);
    when(() => auth.authStateChanges).thenAnswer((_) => events.stream);
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) async => admissionStatus());
    admission = AdmissionController(
      authService: auth,
      profileService: profiles,
    );
  });

  void pageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        admission.dispose();
        await events.close();
      }
    });
  }

  Future<void> mount(WidgetTester tester, {String path = '/homePage'}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdmissionGate(
          controller: admission,
          auth: auth,
          profiles: profiles,
          location: path,
          child: const _Counter(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  pageTest('does not mount protected content before server admission', (
    tester,
  ) async {
    final response = Completer<AdmissionStatus>();
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) => response.future);
    await tester.pumpWidget(
      MaterialApp(
        home: AdmissionGate(
          controller: admission,
          auth: auth,
          profiles: profiles,
          location: '/homePage',
          child: const _Counter(),
        ),
      ),
    );
    expect(find.byType(_Counter), findsNothing);
    response.complete(admissionStatus());
    await tester.pumpAndSettle();
    expect(find.text('Count 0'), findsOneWidget);
    verify(() => profiles.getAdmissionStatus()).called(1);
  });

  pageTest('one-time terms block content and are not automatically accepted', (
    tester,
  ) async {
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) async => admissionStatus(step: 'review_terms'));
    await mount(tester);
    expect(find.byType(AdmissionPage), findsOneWidget);
    expect(find.byType(_Counter), findsNothing);
    verifyNever(() => profiles.acceptLoyaltyPolicy(any()));
  });

  pageTest(
    'support maintenance is allowed before terms only by server status',
    (tester) async {
      when(
        () => profiles.getAdmissionStatus(),
      ).thenAnswer((_) async => admissionStatus(step: 'review_terms'));
      await mount(tester, path: '/maintenancePage');
      expect(find.text('Count 0'), findsOneWidget);
    },
  );

  pageTest('soft refresh retains state but blocks taps and semantics', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Count 0'));
    await tester.pump();
    final response = Completer<AdmissionStatus>();
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) => response.future);
    final check = admission.revalidate();
    await tester.pump();
    await tester.pump();
    expect(find.text('Count 1'), findsOneWidget);
    expect(
      tester
          .widget<AbsorbPointer>(
            find
                .ancestor(
                  of: find.byType(_Counter),
                  matching: find.byType(AbsorbPointer),
                )
                .first,
          )
          .absorbing,
      isTrue,
    );
    await tester.tap(find.text('Count 1'), warnIfMissed: false);
    response.complete(admissionStatus());
    await tester.pump();
    await tester.pumpAndSettle();
    await check;
    expect(find.text('Count 1'), findsOneWidget);
    await tester.tap(find.text('Count 1'));
    await tester.pump();
    expect(find.text('Count 2'), findsOneWidget);
  });

  pageTest('sign-out removes retained content without another read', (
    tester,
  ) async {
    await mount(tester);
    current = null;
    events.add(const AuthState(AuthChangeEvent.signedOut, null));
    await tester.pumpAndSettle();
    expect(find.byType(_Counter), findsNothing);
    expect(find.text('Sign in again'), findsOneWidget);
    verify(() => profiles.getAdmissionStatus()).called(1);
  });

  pageTest('same-user token refresh rechecks access without a refresh loop', (
    tester,
  ) async {
    await mount(tester);
    current = admissionSession(
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      revision: 'new',
    );
    events.add(AuthState(AuthChangeEvent.tokenRefreshed, current));
    await tester.pumpAndSettle();
    expect(find.text('Count 0'), findsOneWidget);
    verify(() => profiles.getAdmissionStatus()).called(2);
  });

  pageTest('account switch discards another account\'s mounted state', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Count 0'));
    await tester.pump();
    current = admissionSession(
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      id: accountB,
    );
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) async => admissionStatus(id: accountB));
    events.add(AuthState(AuthChangeEvent.signedIn, current));
    await tester.pumpAndSettle();
    expect(find.text('Count 0'), findsOneWidget);
    expect(find.text('Count 1'), findsNothing);
  });

  pageTest('failed access check is not repeatedly retried', (tester) async {
    when(
      () => profiles.getAdmissionStatus(),
    ).thenThrow(const PostgrestException(message: 'restricted', code: 'PT403'));
    await mount(tester);
    expect(find.byType(_Counter), findsNothing);
    expect(
      find.text('Unable to confirm account access. Please try again.'),
      findsOneWidget,
    );
    verify(() => profiles.getAdmissionStatus()).called(1);
  });

  pageTest('actual protected router prevents admin page construction', (
    tester,
  ) async {
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) async => admissionStatus(step: 'review_terms'));
    final router = RouterService().createRouter(
      auth,
      admission: admission,
      profiles: profiles,
    );
    router.go('/admin/wallets');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byType(AdmissionPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  pageTest('required MFA can return to public login without admitting Home', (
    tester,
  ) async {
    when(
      () => profiles.getAdmissionStatus(),
    ).thenAnswer((_) async => admissionStatus(step: 'enroll_totp'));
    when(() => auth.listMfaFactors()).thenAnswer(
      (_) async => AuthMFAListFactorsResponse(all: [], totp: [], phone: []),
    );
    when(() => auth.getMfaAssurance()).thenReturn(
      AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: AuthenticatorAssuranceLevels.aal1,
        nextLevel: AuthenticatorAssuranceLevels.aal1,
        currentAuthenticationMethods: [],
      ),
    );
    final router = GoRouter(
      initialLocation: '/homePage',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) =>
              const Scaffold(body: Text('Login / Create Account')),
        ),
        GoRoute(
          path: '/homePage',
          builder: (_, _) => AdmissionGate(
            controller: admission,
            auth: auth,
            profiles: profiles,
            location: '/homePage',
            child: const _Counter(),
          ),
        ),
      ],
    );
    try {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byType(_Counter), findsNothing);
      await tester.tap(find.byTooltip('Back to login'));
      await tester.pumpAndSettle();
      expect(find.text('Login / Create Account'), findsOneWidget);
      expect(find.byType(_Counter), findsNothing);
      verifyNever(() => auth.enrollTotp());
      verifyNever(() => auth.logout());
      expect(admission.canEnterHome, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }
  });

  pageTest('actual public legal route does not require an admission read', (
    tester,
  ) async {
    current = null;
    final router = RouterService().createRouter(
      auth,
      admission: admission,
      profiles: profiles,
    );
    router.go('/legal/terms');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byType(AdmissionPage), findsNothing);
    verifyNever(() => profiles.getAdmissionStatus());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('Count $count'),
    ),
  );
}
