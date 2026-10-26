import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Google extends Mock implements GoogleSignIn {}

class _Account extends Mock implements GoogleSignInAccount {}

class _Authorization extends Mock implements GoogleSignInAuthorizationClient {}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('native Google on $platform', () {
      late _Google google;
      late _Account account;
      late _Authorization authorization;
      late SupabaseClient client;
      late SupabaseAuthService service;
      late List<http.Request> requests;
      Completer<void>? exchangeStarted;
      Completer<void>? releaseExchange;
      late bool passwordUsesGoogleUser;
      late int? tokenLifetime;

      setUp(() {
        debugDefaultTargetPlatformOverride = platform;
        google = _Google();
        account = _Account();
        authorization = _Authorization();
        requests = [];
        exchangeStarted = null;
        releaseExchange = null;
        passwordUsesGoogleUser = false;
        tokenLifetime = 3600;
        final transport = MockClient((request) async {
          requests.add(request);
          if (request.url.queryParameters['grant_type'] == 'id_token') {
            exchangeStarted?.complete();
            await releaseExchange?.future;
          }
          final passwordLogin =
              request.url.queryParameters['grant_type'] == 'password';
          return http.Response(
            jsonEncode({
              'access_token':
                  'e30.${base64Url.encode(utf8.encode(jsonEncode({'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000, if (tokenLifetime != null) 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + tokenLifetime!})))}.signature',
              'refresh_token': 'synthetic-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': passwordLogin && !passwordUsesGoogleUser
                    ? 'replacement-user'
                    : 'synthetic-user',
                'aud': 'authenticated',
                'email': 'customer@example.com',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-01-01T00:00:00Z',
              },
            }),
            200,
          );
        });
        client = SupabaseClient(
          'https://offline.invalid',
          'synthetic-public-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: transport,
        );
        service = SupabaseAuthService(
          client: client,
          googleSignIn: google,
          googleAuthClientFactory: () => GoTrueClient(
            url: 'https://offline.invalid/auth/v1',
            headers: {'apikey': 'synthetic-public-key'},
            autoRefreshToken: false,
            httpClient: transport,
          ),
        );
        when(
          () => google.initialize(serverClientId: any(named: 'serverClientId')),
        ).thenAnswer((_) async {});
        when(
          () => google.authenticate(scopeHint: ['email', 'profile']),
        ).thenAnswer((_) async => account);
        when(() => account.authentication).thenReturn(
          const GoogleSignInAuthentication(idToken: 'synthetic-google-id'),
        );
        when(() => account.authorizationClient).thenReturn(authorization);
        when(
          () => authorization.authorizationForScopes(['email', 'profile']),
        ).thenAnswer(
          (_) async => const GoogleSignInClientAuthorization(
            accessToken: 'synthetic-google-access',
          ),
        );
      });
      tearDown(() async {
        debugDefaultTargetPlatformOverride = null;
        await client.dispose();
      });

      test(
        'native tokens establish a real SDK session without browser OAuth',
        () async {
          expect(await service.googleSignIn(), isTrue);
          expect(client.auth.currentUser?.id, 'synthetic-user');
          expect(requests, hasLength(1));
          expect(requests.single.url.path, '/auth/v1/token');
          expect(requests.single.url.queryParameters, {
            'grant_type': 'id_token',
          });
          final body = jsonDecode(requests.single.body);
          expect(body['provider'], 'google');
          expect(body['id_token'], 'synthetic-google-id');
          expect(body['access_token'], 'synthetic-google-access');
          verifyNever(() => authorization.authorizeScopes(any()));
        },
      );

      test(
        'cancellation neither creates a session nor contacts Supabase',
        () async {
          when(
            () => google.authenticate(scopeHint: ['email', 'profile']),
          ).thenThrow(
            const GoogleSignInException(
              code: GoogleSignInExceptionCode.canceled,
            ),
          );
          expect(await service.googleSignIn(), isFalse);
          expect(client.auth.currentSession, isNull);
          expect(requests, isEmpty);
        },
      );

      test('missing token is reported without a token exchange', () async {
        when(
          () => account.authentication,
        ).thenReturn(const GoogleSignInAuthentication(idToken: null));
        await expectLater(
          service.googleSignIn(),
          throwsA(isA<AuthException>()),
        );
        expect(requests, isEmpty);
      });

      test('initialization failure can be retried without hiding it', () async {
        var attempts = 0;
        when(
          () => google.initialize(serverClientId: any(named: 'serverClientId')),
        ).thenAnswer((_) async {
          if (++attempts == 1) {
            throw StateError('synthetic initialization failure');
          }
        });
        await expectLater(service.googleSignIn(), throwsStateError);
        expect(await service.googleSignIn(), isTrue);
        expect(attempts, 2);
        expect(requests, hasLength(1));
      });

      test(
        'a changed account blocks exchange after native authentication',
        () async {
          when(
            () => google.authenticate(scopeHint: ['email', 'profile']),
          ).thenAnswer((_) async {
            await client.auth.signInWithPassword(
              email: 'replacement@example.com',
              password: 'synthetic',
            );
            return account;
          });
          await expectLater(
            service.googleSignIn(),
            throwsA(isA<AuthException>()),
          );
          expect(requests, hasLength(1));
          expect(requests.single.url.queryParameters['grant_type'], 'password');
        },
      );

      for (final action in ['replacement', 'logout', 'cancel']) {
        test('late token exchange cannot undo $action', () async {
          exchangeStarted = Completer<void>();
          releaseExchange = Completer<void>();
          final pending = service.googleSignIn();
          final rejected = expectLater(pending, throwsA(isA<AuthException>()));
          await exchangeStarted!.future;
          if (action == 'replacement') {
            await service.login('replacement@example.com', 'synthetic');
          } else if (action == 'logout') {
            await service.logout();
          } else {
            service.cancelGoogleSignIn();
          }
          releaseExchange!.complete();
          await rejected;
          expect(
            client.auth.currentUser?.id,
            action == 'replacement' ? 'replacement-user' : isNull,
          );
        });
      }

      test('same-user login emits the persisted refresh event', () async {
        passwordUsesGoogleUser = true;
        await service.login('customer@example.com', 'synthetic');
        final events = <AuthState>[];
        final subscription = client.auth.onAuthStateChange.listen(events.add);
        await Future<void>.delayed(Duration.zero);
        events.clear();
        expect(await service.googleSignIn(), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(events.single.event, AuthChangeEvent.tokenRefreshed);
        expect(events.single.session, same(client.auth.currentSession));
        expect(
          requests.last.url.queryParameters['grant_type'],
          'refresh_token',
        );
        await subscription.cancel();
      });

      for (final lifetime in <int?>[null, 20]) {
        test(
          'invalid or near-expiry token is not adopted: $lifetime',
          () async {
            tokenLifetime = lifetime;
            await expectLater(
              service.googleSignIn(),
              throwsA(isA<AuthException>()),
            );
            expect(client.auth.currentSession, isNull);
            expect(requests, hasLength(1));
          },
        );
      }
    });
  }
}
