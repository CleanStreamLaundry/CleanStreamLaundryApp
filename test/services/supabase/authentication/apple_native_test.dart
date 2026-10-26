@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    group('native Apple on $platform', () {
      late SupabaseClient client;
      late SupabaseAuthService service;
      late List<http.Request> requests;
      late List<MethodCall> nativeCalls;
      late Map<String, Object?> credential;
      late Map<String, Object?> metadata;
      late int? tokenLifetime;
      late bool passwordUsesAppleUser;
      PlatformException? nativeError;
      Completer<void>? exchangeStarted;
      Completer<void>? releaseExchange;
      Future<void> Function()? beforeCredential;

      setUp(() {
        debugDefaultTargetPlatformOverride = platform;
        requests = [];
        nativeCalls = [];
        metadata = {'full_name': 'Existing Name'};
        tokenLifetime = 3600;
        passwordUsesAppleUser = false;
        nativeError = null;
        exchangeStarted = null;
        releaseExchange = null;
        beforeCredential = null;
        credential = {
          'type': 'appleid',
          'authorizationCode': 'synthetic-authorization-code',
          'identityToken': 'synthetic-apple-id-token',
          'userIdentifier': 'synthetic-apple-subject',
        };
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SignInWithApple.channel, (call) async {
              nativeCalls.add(call);
              if (nativeError != null) throw nativeError!;
              await beforeCredential?.call();
              return credential;
            });

        final transport = MockClient((request) async {
          requests.add(request);
          final grant = request.url.queryParameters['grant_type'];
          if (grant == 'id_token') {
            exchangeStarted?.complete();
            await releaseExchange?.future;
          }
          final user = {
            'id': grant == 'password' && !passwordUsesAppleUser
                ? 'replacement-user'
                : 'apple-user',
            'aud': 'authenticated',
            'email': 'synthetic@privaterelay.appleid.com',
            'app_metadata': {},
            'user_metadata': metadata,
            'created_at': '2026-01-01T00:00:00Z',
          };
          if (request.method == 'PUT' && request.url.path == '/auth/v1/user') {
            metadata = Map<String, Object?>.from(
              jsonDecode(request.body)['data'],
            );
            return http.Response(
              jsonEncode({...user, 'user_metadata': metadata}),
              200,
            );
          }
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final claims = base64Url.encode(
            utf8.encode(
              jsonEncode({
                'iat': now,
                if (tokenLifetime != null) 'exp': now + tokenLifetime!,
              }),
            ),
          );
          return http.Response(
            jsonEncode({
              'access_token': 'e30.$claims.signature',
              'refresh_token': 'synthetic-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': user,
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
          googleAuthClientFactory: () => GoTrueClient(
            url: 'https://offline.invalid/auth/v1',
            headers: {'apikey': 'synthetic-public-key'},
            autoRefreshToken: false,
            httpClient: transport,
          ),
        );
      });

      tearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SignInWithApple.channel, null);
        debugDefaultTargetPlatformOverride = null;
        await client.dispose();
      });

      test('native channel and real SDK exchange bind the raw nonce', () async {
        expect(await service.appleSignIn(), isTrue);
        expect(client.auth.currentUser?.id, 'apple-user');
        expect(requests, hasLength(1));
        expect(requests.single.url.path, '/auth/v1/token');
        expect(requests.single.url.queryParameters, {'grant_type': 'id_token'});
        final body = jsonDecode(requests.single.body);
        expect(body['provider'], 'apple');
        expect(body['id_token'], 'synthetic-apple-id-token');
        expect(body['nonce'], isNotEmpty);
        final nativeRequest =
            (nativeCalls.single.arguments as List).single as Map;
        expect(nativeCalls.single.method, 'performAuthorizationRequest');
        expect(nativeRequest['scopes'], ['email', 'fullName']);
        expect(
          nativeRequest['nonce'],
          sha256.convert(utf8.encode(body['nonce'] as String)).toString(),
        );
        expect(nativeRequest['nonce'], isNot(body['nonce']));
        expect(
          client.auth.currentUser?.userMetadata?['full_name'],
          'Existing Name',
        );
      });

      test(
        'first-consent name is saved using the isolated Apple token',
        () async {
          credential.addAll({'givenName': ' New ', 'familyName': ' Customer '});
          expect(await service.appleSignIn(), isTrue);
          expect(requests, hasLength(2));
          expect(requests.last.url.path, '/auth/v1/user');
          expect(jsonDecode(requests.last.body)['data'], {
            'full_name': 'New Customer',
          });
          expect(
            requests.last.headers['authorization'],
            startsWith('Bearer e30.'),
          );
          expect(
            client.auth.currentUser?.userMetadata?['full_name'],
            'New Customer',
          );
        },
      );

      test(
        'canceling native UI does not exchange tokens or create a session',
        () async {
          nativeError = PlatformException(code: 'authorization-error/canceled');
          expect(await service.appleSignIn(), isFalse);
          expect(requests, isEmpty);
          expect(client.auth.currentSession, isNull);
        },
      );

      test('native errors other than cancellation are not swallowed', () async {
        nativeError = PlatformException(code: 'authorization-error/failed');
        await expectLater(
          service.appleSignIn(),
          throwsA(isA<SignInWithAppleAuthorizationException>()),
        );
        expect(requests, isEmpty);
      });

      for (final token in [null, '']) {
        test('missing or empty ID token ($token) prevents exchange', () async {
          credential['identityToken'] = token;
          await expectLater(
            service.appleSignIn(),
            throwsA(isA<AuthException>()),
          );
          expect(requests, isEmpty);
        });
      }

      for (final lifetime in [null, 30]) {
        test(
          'missing or short token expiry ($lifetime) prevents adoption',
          () async {
            tokenLifetime = lifetime;
            await expectLater(
              service.appleSignIn(),
              throwsA(isA<AuthException>()),
            );
            expect(client.auth.currentSession, isNull);
          },
        );
      }

      test(
        'a replacement login before native completion prevents exchange',
        () async {
          beforeCredential = () async {
            await service.login('replacement@example.com', 'synthetic');
          };
          await expectLater(
            service.appleSignIn(),
            throwsA(isA<AuthException>()),
          );
          expect(requests, hasLength(1));
          expect(requests.single.url.queryParameters['grant_type'], 'password');
          expect(client.auth.currentUser?.id, 'replacement-user');
        },
      );

      for (final action in ['replacement', 'logout', 'cancel']) {
        test(
          'late exchange cannot undo $action or write profile metadata',
          () async {
            credential['givenName'] = 'New';
            exchangeStarted = Completer<void>();
            releaseExchange = Completer<void>();
            final pending = service.appleSignIn();
            final rejected = expectLater(
              pending,
              throwsA(isA<AuthException>()),
            );
            await exchangeStarted!.future;
            if (action == 'replacement') {
              await service.login('replacement@example.com', 'synthetic');
            } else if (action == 'logout') {
              await service.logout();
            } else {
              service.cancelAppleSignIn();
            }
            releaseExchange!.complete();
            await rejected;
            expect(
              client.auth.currentUser?.id,
              action == 'replacement' ? 'replacement-user' : isNull,
            );
            expect(
              requests.where((request) => request.method == 'PUT'),
              isEmpty,
            );
          },
        );
      }

      test('same-user adoption emits the persistence refresh event', () async {
        passwordUsesAppleUser = true;
        await service.login('customer@example.com', 'synthetic');
        final events = <AuthState>[];
        final subscription = client.auth.onAuthStateChange.listen(events.add);
        await Future<void>.delayed(Duration.zero);
        events.clear();
        expect(await service.appleSignIn(), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(events.single.event, AuthChangeEvent.tokenRefreshed);
        expect(events.single.session, same(client.auth.currentSession));
        expect(
          requests.last.url.queryParameters['grant_type'],
          'refresh_token',
        );
        await subscription.cancel();
      });
    });
  }
}
