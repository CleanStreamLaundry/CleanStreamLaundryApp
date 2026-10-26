import 'dart:async';
import 'dart:io';

import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'package:clean_stream_laundry_app/features/not_found/not_found.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/root_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/loading/mocks.dart';
import '../../features/home/mocks.dart'
    show MockProfileService, MockLocationService, MockMachineService;

class MockEdgeService extends Mock implements EdgeFunctionService {}

class MockVendService extends Mock implements CortinaVendService {}

class MockWalletService extends Mock implements WalletService {}

class MockPendingStore extends Mock implements CortinaPendingStore {}

void main() {
  late MockAuthService auth;
  late MockProfileService profile;
  late MockAppLinks links;
  late StreamController<Uri> incoming;
  late GoRouter router;
  late ThemeManager theme;
  late int subscriptions;
  late int cancellations;

  setUpAll(() => registerFallbackValue(Uri()));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    subscriptions = 0;
    cancellations = 0;
    incoming = StreamController<Uri>.broadcast(
      onListen: () => subscriptions++,
      onCancel: () => cancellations++,
    );
    auth = MockAuthService();
    profile = MockProfileService();
    links = MockAppLinks();
    when(() => links.uriLinkStream).thenAnswer((_) => incoming.stream);
    when(() => links.getInitialLink()).thenAnswer((_) async => null);
    when(
      () => auth.isLoggedIn(),
    ).thenAnswer((_) async => AuthenticationResponses.failure);
    when(() => auth.getSessionFromURI(any())).thenAnswer((_) async {});
    when(() => auth.refreshSession()).thenAnswer((_) async {});
    when(() => auth.onAuthChange).thenAnswer((_) => const Stream.empty());
    when(() => auth.authStateChanges)
        .thenAnswer((_) => const Stream<AuthState>.empty());
    when(
      () => profile.getUserNameById(any()),
    ).thenAnswer((_) async => 'Test Person');
    when(() => auth.getCurrentUser()).thenReturn(
      User(
        id: 'user-1',
        appMetadata: {},
        userMetadata: {'full_name': 'Test Person'},
        aud: 'authenticated',
        createdAt: '',
      ),
    );
    when(
      () => profile.createAccount(
        id: any(named: 'id'),
        name: any(named: 'name'),
      ),
    ).thenAnswer((_) async {});
    final locations = MockLocationService();
    when(() => locations.getLocations()).thenAnswer((_) async => []);
    GetIt.I.registerSingleton<AuthService>(auth);
    GetIt.I.registerSingleton<ProfileService>(profile);
    GetIt.I.registerSingleton<LocationService>(locations);
    GetIt.I.registerSingleton<MachineService>(MockMachineService());
    GetIt.I.registerSingleton<EdgeFunctionService>(MockEdgeService());
    GetIt.I.registerSingleton<CortinaPendingStore>(MockPendingStore());
    router = RouterService().createRouter(auth, appLinks: links);
    theme = ThemeManager();
  });

  tearDown(() async {
    router.dispose();
    await incoming.close();
    theme.dispose();
    await GetIt.I.reset();
  });

  Future<void> mount(WidgetTester tester, {String? location}) async {
    if (location != null) router.go(location);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: RootApp(router: router, appLinks: links),
      ),
    );
    await tester.pump();
  }

  String getPath() => router.routerDelegate.currentConfiguration.uri.path;

  for (final signedIn in [false, true]) {
    for (final cold in [false, true]) {
      for (final fails in [false, true]) {
        testWidgets(
          'provisioning cold=$cold signedIn=$signedIn fails=$fails remains single-owner',
          (tester) async {
            final uri = Uri.parse(
              'clean-stream://oauth?code=synthetic-provision',
            );
            final saving = Completer<void>();
            var started = false;
            when(() => auth.isLoggedIn()).thenAnswer(
              (_) async => signedIn
                  ? AuthenticationResponses.success
                  : AuthenticationResponses.failure,
            );
            when(() => auth.getSessionFromURI(uri)).thenAnswer((_) async {
              when(
                () => auth.isLoggedIn(),
              ).thenAnswer((_) async => AuthenticationResponses.success);
            });
            when(
              () => profile.createAccount(id: 'user-1', name: 'Test Person'),
            ).thenAnswer((_) {
              started = true;
              return saving.future;
            });
            if (cold) {
              when(
                () => links.getInitialLink(),
              ).thenAnswer((_) async => uri);
            }
            await mount(tester, location: cold ? null : '/password-reset');
            if (!cold) incoming.add(uri);
            await tester.pump();
            await tester.pump();
            expect(started, isTrue);
            expect(getPath(), '/auth-callback/oauth');
            incoming.add(uri);
            await tester.pump();
            if (fails) {
              saving.completeError(
                const PostgrestException(
                  message: 'synthetic denied',
                  code: 'PT503',
                ),
              );
            } else {
              saving.complete();
            }
            await tester.pumpAndSettle();
            final destination = fails ? '/login' : '/homePage';
            expect(getPath(), destination);
            incoming.add(uri);
            await tester.pumpAndSettle();
            expect(getPath(), destination);
            verify(() => auth.getSessionFromURI(uri)).called(1);
            verify(
              () => profile.createAccount(id: 'user-1', name: 'Test Person'),
            ).called(1);
          },
        );
      }
    }
  }

  for (final fails in [false, true]) {
    testWidgets(
      'stale A-B-A provisioning uses existing error view, fails=$fails',
      (tester) async {
        final changes = StreamController<bool>.broadcast();
        final saving = Completer<void>();
        when(() => auth.onAuthChange).thenAnswer((_) => changes.stream);
        when(
          () => auth.isLoggedIn(),
        ).thenAnswer((_) async => AuthenticationResponses.success);
        when(
          () => profile.createAccount(id: 'user-1', name: 'Test Person'),
        ).thenAnswer((_) => saving.future);
        await mount(tester, location: '/password-reset');
        final uri = Uri.parse('clean-stream://oauth?code=synthetic-switch');
        incoming.add(uri);
        await tester.pump();
        await tester.pump();
        expect(getPath(), '/auth-callback/oauth');
        final original = auth.getCurrentUser();
        when(() => auth.getCurrentUser()).thenReturn(
          User(
            id: 'B',
            appMetadata: {},
            userMetadata: {},
            aud: '',
            createdAt: '',
          ),
        );
        changes.add(true);
        await tester.pump();
        when(() => auth.getCurrentUser()).thenReturn(original);
        changes.add(true);
        await tester.pump();
        if (fails) {
          saving.completeError(StateError('synthetic late failure'));
        } else {
          saving.complete();
        }
        await tester.pumpAndSettle();
        expect(getPath(), '/auth-callback/oauth');
        expect(
          find.text('Your sign-in changed. Please return to Login.'),
          findsOneWidget,
        );
        expect(changes.hasListener, isFalse);
        await tester.tap(find.text('Return to Login'));
        await tester.pumpAndSettle();
        expect(getPath(), '/login');
        incoming.add(uri);
        await tester.pumpAndSettle();
        expect(getPath(), '/login');
        verify(() => auth.getSessionFromURI(uri)).called(1);
        verify(
          () => profile.createAccount(id: 'user-1', name: 'Test Person'),
        ).called(1);
        await changes.close();
      },
    );

    for (final destination in [
      '/reset-protected?token=synthetic#token=fake',
      '/pay?machine=synthetic',
    ]) {
      testWidgets(
        'pending provisioning cannot overwrite $destination, fails=$fails',
        (tester) async {
          final saving = Completer<void>();
          if (destination.startsWith('/pay')) {
            GetIt.I.registerSingleton<CortinaVendService>(MockVendService());
            GetIt.I.registerSingleton<WalletService>(MockWalletService());
          }
          when(
            () => auth.isLoggedIn(),
          ).thenAnswer((_) async => AuthenticationResponses.success);
          when(
            () => profile.createAccount(id: 'user-1', name: 'Test Person'),
          ).thenAnswer((_) => saving.future);
          await mount(tester, location: '/password-reset');
          final uri = Uri.parse('clean-stream://oauth?code=synthetic-old');
          incoming.add(uri);
          await tester.pump();
          await tester.pump();
          expect(getPath(), '/auth-callback/oauth');
          router.go(destination);
          await tester.pumpAndSettle();
          final current = router.routerDelegate.currentConfiguration.uri;
          if (fails) {
            saving.completeError(StateError('synthetic late failure'));
          } else {
            saving.complete();
          }
          await tester.pumpAndSettle();
          expect(router.routerDelegate.currentConfiguration.uri, current);
          expect(current.toString(), destination);
          verify(() => auth.getSessionFromURI(uri)).called(1);
          verify(
            () => profile.createAccount(id: 'user-1', name: 'Test Person'),
          ).called(1);
        },
      );
    }
  }

  for (final signedIn in [false, true]) {
    for (final cold in [false, true]) {
      for (final outcome in ['success', 'invalid-session', 'failure']) {
        testWidgets(
          'OAuth cold=$cold signedIn=$signedIn, $outcome, duplicates',
          (tester) async {
            final uri = Uri.parse(
              'clean-stream://oauth?code=unique#provider_token=fake',
            );
            final exchange = Completer<void>();
            when(() => auth.isLoggedIn()).thenAnswer(
              (_) async => signedIn
                  ? AuthenticationResponses.success
                  : AuthenticationResponses.failure,
            );
            when(
              () => auth.getSessionFromURI(uri),
            ).thenAnswer((_) => exchange.future);
            if (cold) {
              when(
                () => links.getInitialLink(),
              ).thenAnswer((_) async => uri);
            }
            await mount(tester, location: cold ? null : '/password-reset');
            if (!cold) incoming.add(uri);
            await tester.pump();
            await tester.pump();
            incoming.add(uri);
            await tester.pump();
            expect(getPath(), '/auth-callback/oauth');
            expect(
              find.byKey(
                ValueKey(
                  Uri.parse(
                    '/auth-callback/oauth?code=unique#provider_token=fake',
                  ),
                ),
              ),
              findsOneWidget,
            );
            expect(find.byType(NotFound), findsNothing);
            verifyNever(() => auth.isLoggedIn());
            when(() => auth.isLoggedIn()).thenAnswer(
              (_) async => outcome == 'invalid-session'
                  ? AuthenticationResponses.failure
                  : AuthenticationResponses.success,
            );
            if (outcome == 'failure') {
              exchange.completeError(Exception('bad token'));
            } else {
              exchange.complete();
            }
            await tester.pumpAndSettle();
            final expected = outcome == 'success' ? '/homePage' : '/login';
            expect(getPath(), expected);
            incoming.add(uri);
            await tester.pumpAndSettle();
            expect(getPath(), expected);
            verify(() => auth.getSessionFromURI(uri)).called(1);
            if (outcome == 'failure') {
              verifyNever(() => auth.isLoggedIn());
            } else {
              verify(() => auth.isLoggedIn()).called(1);
            }
            if (outcome == 'success') {
              verify(
                () => profile.createAccount(id: 'user-1', name: 'Test Person'),
              ).called(1);
            } else {
              verifyNever(
                () => profile.createAccount(
                  id: any(named: 'id'),
                  name: any(named: 'name'),
                ),
              );
            }
            expect(subscriptions, 1);
          },
        );
      }
    }
  }

  for (final initialFirst in [false, true]) {
    testWidgets('initial and stream duplicate, initialFirst=$initialFirst', (
      tester,
    ) async {
      final uri = Uri.parse('clean-stream://oauth?code=cold');
      final initial = Completer<Uri?>();
      final exchange = Completer<void>();
      when(() => links.getInitialLink()).thenAnswer((_) => initial.future);
      when(
        () => auth.getSessionFromURI(uri),
      ).thenAnswer((_) => exchange.future);
      await mount(tester);
      if (initialFirst) {
        initial.complete(uri);
      } else {
        incoming.add(uri);
      }
      await tester.pump();
      await tester.pump();
      if (initialFirst) {
        incoming.add(uri);
      } else {
        initial.complete(uri);
      }
      await tester.pump();
      exchange.complete();
      await tester.pumpAndSettle();
      expect(getPath(), '/login');
      verify(() => auth.getSessionFromURI(uri)).called(1);
      verify(() => auth.isLoggedIn()).called(1);
      verify(() => links.getInitialLink()).called(1);
      router.go('/');
      await tester.pumpAndSettle();
      expect(getPath(), '/login');
      verifyNever(() => links.getInitialLink());
      verifyNever(() => auth.getSessionFromURI(any()));
    });
  }

  for (final host in ['reset-protected', 'email-verification']) {
    for (final warm in [false, true]) {
      testWidgets('plain $host warm=$warm stays usable without granting Home', (
        tester,
      ) async {
        final uri = Uri.parse('clean-stream://$host');
        when(
          () => auth.isLoggedIn(),
        ).thenAnswer((_) async => AuthenticationResponses.success);
        if (!warm) {
          when(() => links.getInitialLink()).thenAnswer((_) async => uri);
        }
        await mount(tester, location: warm ? '/password-reset' : null);
        if (warm) incoming.add(uri);
        await tester.pumpAndSettle();
        expect(getPath(), '/$host');
        if (host == 'reset-protected') {
          expect(router.routerDelegate.currentConfiguration.extra, uri);
        }
        router.go('/login');
        await tester.pumpAndSettle();
        expect(getPath(), '/login');
        incoming.add(uri);
        await tester.pumpAndSettle();
        expect(getPath(), '/$host');
        if (host == 'reset-protected') {
          expect(router.routerDelegate.currentConfiguration.extra, uri);
        }
        verifyNever(() => auth.getSessionFromURI(any()));
        verifyNever(() => auth.isLoggedIn());
        verifyNever(() => auth.refreshSession());
      });
    }
    for (final warm in [false, true]) {
      testWidgets(
        '$host cold/warm=$warm preserves final payload and never grants Home',
        (tester) async {
          final uri = Uri.parse(
            'clean-stream://$host/?code=a%2Bb#access_token=fake',
          );
          when(
            () => auth.isLoggedIn(),
          ).thenAnswer((_) async => AuthenticationResponses.success);
          if (!warm) {
            when(() => links.getInitialLink()).thenAnswer((_) async => uri);
          }
          await mount(tester, location: warm ? '/password-reset' : null);
          if (warm) incoming.add(uri);
          await tester.pumpAndSettle();
          expect(
            router.routerDelegate.currentConfiguration.uri.toString(),
            '/$host?${uri.query}#${uri.fragment}',
          );
          if (host == 'reset-protected') {
            expect(router.routerDelegate.currentConfiguration.extra, uri);
          }
          router.go('/login');
          await tester.pumpAndSettle();
          expect(getPath(), '/login');
          incoming.add(uri);
          await tester.pumpAndSettle();
          expect(getPath(), '/login');
          verify(() => auth.getSessionFromURI(uri)).called(1);
          verifyNever(() => auth.isLoggedIn());
          expect(find.byType(NotFound), findsNothing);
        },
      );
    }
  }

  for (final host in ['reset-protected', 'email-verification']) {
    testWidgets('failed $host callback cannot use an unrelated session', (
      tester,
    ) async {
      final uri = Uri.parse('clean-stream://$host?code=bad');
      when(
        () => auth.isLoggedIn(),
      ).thenAnswer((_) async => AuthenticationResponses.success);
      when(
        () => auth.getSessionFromURI(uri),
      ).thenThrow(Exception('invalid token'));
      await mount(tester, location: '/password-reset');
      incoming.add(uri);
      await tester.pumpAndSettle();
      expect(getPath(), '/login');
      verify(() => auth.getSessionFromURI(uri)).called(1);
      verifyNever(() => auth.isLoggedIn());
    });
  }

  testWidgets(
    'root disposal cancels its only subscription and pending callback navigation',
    (tester) async {
      final exchange = Completer<void>();
      when(
        () => auth.getSessionFromURI(any()),
      ).thenAnswer((_) => exchange.future);
      await mount(tester, location: '/password-reset');
      incoming.add(Uri.parse('clean-stream://oauth?code=disposed'));
      await tester.pump();
      await tester.pump();
      final pendingRoute = getPath();
      await tester.pumpWidget(const SizedBox());
      exchange.completeError(Exception('late failure'));
      incoming.add(Uri.parse('clean-stream://reset-protected'));
      await tester.pump();
      expect(cancellations, 1);
      expect(getPath(), pendingRoute);
      verifyNever(() => auth.isLoggedIn());
      expect(tester.takeException(), isNull);
    },
  );

  for (final host in [
    'reset-protected',
    'email-verification',
    'change-email',
  ]) {
    for (final payload in ['refresh_token=invalid', 'error_code=invalid']) {
      testWidgets('partial $host $payload cannot use an unrelated session', (
        tester,
      ) async {
        final uri = Uri.parse('clean-stream://$host#$payload');
        when(
          () => auth.isLoggedIn(),
        ).thenAnswer((_) async => AuthenticationResponses.success);
        when(() => auth.getCurrentUserId).thenReturn('user-1');
        when(
          () => auth.getSessionFromURI(uri),
        ).thenThrow(Exception('incomplete callback payload'));
        await mount(tester, location: '/password-reset');
        incoming.add(uri);
        await tester.pumpAndSettle();
        expect(getPath(), '/login');
        incoming.add(uri);
        await tester.pumpAndSettle();
        expect(getPath(), '/login');
        verify(() => auth.getSessionFromURI(uri)).called(1);
        verifyNever(() => auth.isLoggedIn());
        verifyNever(() => auth.refreshSession());
      });
    }
  }

  testWidgets('root ignores malformed external links and stream failures', (
    tester,
  ) async {
    await mount(tester, location: '/password-reset');
    incoming.add(Uri.parse('https://evil.example/homePage'));
    incoming.add(Uri.parse('clean-stream://oauth/extra?code=x'));
    incoming.add(Uri.parse('clean-stream://change-email?type=%FF'));
    incoming.addError(Exception('platform link failure'));
    await tester.pumpAndSettle();
    expect(getPath(), '/password-reset');
    verifyNever(() => auth.getSessionFromURI(any()));
    expect(tester.takeException(), isNull);
  });

  for (final warm in [false, true]) {
    for (final outcome in [
      'valid',
      'signed-out',
      'bad-token',
      'refresh-failure',
    ]) {
      testWidgets(
        'change-email warm=$warm $outcome has one owner and exact destination',
        (tester) async {
          final uri = Uri.parse(
            'clean-stream://change-email?type=email_change&code=abc#access_token=fake',
          );
          when(() => auth.isLoggedIn()).thenAnswer(
            (_) async => outcome == 'signed-out'
                ? AuthenticationResponses.failure
                : AuthenticationResponses.success,
          );
          when(() => auth.getCurrentUserId).thenReturn('user-1');
          if (outcome == 'bad-token') {
            when(
              () => auth.getSessionFromURI(uri),
            ).thenThrow(Exception('invalid callback'));
          }
          if (outcome == 'refresh-failure') {
            when(
              () => auth.refreshSession(),
            ).thenThrow(Exception('refresh failed'));
          }
          if (!warm) {
            when(() => links.getInitialLink()).thenAnswer((_) async => uri);
          }
          await mount(
            tester,
            location: warm ? '/change-email-verification' : null,
          );
          if (warm) incoming.add(uri);
          await tester.pumpAndSettle();
          expect(
            router.routerDelegate.currentConfiguration.uri.toString(),
            outcome == 'valid'
                ? '/editProfile?${uri.query}#${uri.fragment}'
                : '/login',
          );
          incoming.add(uri);
          await tester.pumpAndSettle();
          verify(() => auth.getSessionFromURI(uri)).called(1);
          if (outcome == 'bad-token') {
            verifyNever(() => auth.isLoggedIn());
          } else {
            verify(() => auth.isLoggedIn()).called(1);
          }
          if (outcome == 'valid' || outcome == 'refresh-failure') {
            verify(() => auth.refreshSession()).called(1);
          } else {
            verifyNever(() => auth.refreshSession());
          }
          expect(getPath(), outcome == 'valid' ? '/editProfile' : '/login');
        },
      );
    }
  }

  for (final warm in [false, true]) {
    testWidgets('bare change-email warm=$warm cannot refresh an old session', (
      tester,
    ) async {
      final uri = Uri.parse('clean-stream://change-email');
      when(
        () => auth.isLoggedIn(),
      ).thenAnswer((_) async => AuthenticationResponses.success);
      if (!warm) {
        when(() => links.getInitialLink()).thenAnswer((_) async => uri);
      }
      await mount(tester, location: warm ? '/change-email-verification' : null);
      if (warm) incoming.add(uri);
      await tester.pumpAndSettle();
      expect(getPath(), '/login');
      incoming.add(uri);
      await tester.pumpAndSettle();
      expect(getPath(), '/login');
      verifyNever(() => auth.getSessionFromURI(any()));
      verifyNever(() => auth.isLoggedIn());
      verifyNever(() => auth.refreshSession());
    });
  }

  testWidgets(
    'change-email rejects unrelated type and requires callback payload',
    (tester) async {
      when(
        () => auth.isLoggedIn(),
      ).thenAnswer((_) async => AuthenticationResponses.success);
      when(() => auth.getCurrentUserId).thenReturn('user-1');
      await mount(tester, location: '/change-email-verification');
      incoming.add(Uri.parse('clean-stream://change-email?type=recovery'));
      incoming.add(Uri.parse('clean-stream://change-email#type=recovery'));
      incoming.add(
        Uri.parse(
          'clean-stream://change-email?type=email_change#type=recovery',
        ),
      );
      await tester.pumpAndSettle();
      expect(getPath(), '/change-email-verification');
      verifyNever(() => auth.isLoggedIn());
      incoming.add(Uri.parse('clean-stream://change-email'));
      await tester.pumpAndSettle();
      expect(getPath(), '/login');
      verifyNever(() => auth.getSessionFromURI(any()));
      verifyNever(() => auth.isLoggedIn());
      verifyNever(() => auth.refreshSession());
      incoming.add(Uri.parse('clean-stream://change-email?code=valid'));
      await tester.pumpAndSettle();
      expect(getPath(), '/editProfile');
      verify(
        () => auth.getSessionFromURI(
          Uri.parse('clean-stream://change-email?code=valid'),
        ),
      ).called(1);
      verify(() => auth.isLoggedIn()).called(1);
      verify(() => auth.refreshSession()).called(1);
    },
  );

  for (final authFirst in [false, true]) {
    testWidgets(
      'warm reset wins over pending normal auth, authFirst=$authFirst',
      (tester) async {
        final authResult = Completer<AuthenticationResponses>();
        final exchange = Completer<void>();
        when(() => auth.isLoggedIn()).thenAnswer((_) => authResult.future);
        when(
          () => auth.getSessionFromURI(any()),
        ).thenAnswer((_) => exchange.future);
        await mount(tester);
        await tester.pump();
        incoming.add(Uri.parse('clean-stream://reset-protected?code=reset'));
        await tester.pump();
        await tester.pump();
        if (authFirst) {
          authResult.complete(AuthenticationResponses.success);
        } else {
          exchange.complete();
        }
        await tester.pump();
        if (authFirst) {
          exchange.complete();
        } else {
          authResult.complete(AuthenticationResponses.success);
        }
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/reset-protected?code=reset',
        );
        verify(() => auth.isLoggedIn()).called(1);
        verify(() => auth.getSessionFromURI(any())).called(1);
      },
    );
  }

  for (final warm in [false, true]) {
    testWidgets(
      'allowlisted HTTPS payment warm=$warm retains query without auth exchange',
      (tester) async {
        final uri = Uri.parse(
          'https://cleanstreamlaundry.com/pay?machine=a%2Bb&terminal=12&uniqr=fake',
        );
        final vend = MockVendService();
        when(
          () =>
              vend.quote(machineToken: 'a+b', terminalId: '12', uniQr: 'fake'),
        ).thenThrow(Exception('synthetic unavailable machine'));
        GetIt.I.registerSingleton<CortinaVendService>(vend);
        GetIt.I.registerSingleton<WalletService>(MockWalletService());
        if (!warm) {
          when(() => links.getInitialLink()).thenAnswer((_) async => uri);
        }
        await mount(tester, location: warm ? '/password-reset' : null);
        if (warm) incoming.add(uri);
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/pay?${uri.query}',
        );
        verify(
          () =>
              vend.quote(machineToken: 'a+b', terminalId: '12', uniQr: 'fake'),
        ).called(1);
        verifyNever(() => auth.getSessionFromURI(any()));
        verifyNever(() => auth.isLoggedIn());
      },
    );
  }

  test('DI and native flags leave exactly one app callback owner', () {
    final di = File('lib/core/di/di.dart').readAsStringSync();
    expect(
      RegExp(r'detectSessionInUri\s*:\s*false').allMatches(di),
      hasLength(1),
    );
    final android = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      android,
      contains(
        'android:name="flutter_deeplinking_enabled" android:value="false"',
      ),
    );
    final ios = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>').hasMatch(ios),
      isTrue,
    );
  });

  for (final payload in [
    'code=web-code',
    'error=access_denied&error_description=canceled',
  ]) {
    testWidgets(
      'web loading callback $payload fails closed and is not parsed twice',
      (tester) async {
        when(
          () => auth.getSessionFromURI(any()),
        ).thenThrow(Exception('invalid callback'));
        when(
          () => auth.isLoggedIn(),
        ).thenAnswer((_) async => AuthenticationResponses.success);
        await mount(tester, location: '/loading?$payload');
        await tester.pumpAndSettle();
        expect(getPath(), '/login');
        router.go('/loading?$payload');
        await tester.pumpAndSettle();
        expect(getPath(), '/login');
        verify(
          () => auth.getSessionFromURI(
            Uri.parse('clean-stream://oauth?$payload'),
          ),
        ).called(1);
        verifyNever(() => auth.isLoggedIn());
      },
    );
  }
}
