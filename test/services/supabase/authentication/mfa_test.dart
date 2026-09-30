import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/mfa_verification_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mocks.dart';

class _MfaMock extends Mock implements GoTrueMFAApi {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  group('MFA adapters', () {
    late SupabaseMock client;
    late GoTrueMock auth;
    late _MfaMock mfa;
    late AuthService service;

    setUp(() {
      client = SupabaseMock();
      auth = GoTrueMock();
      mfa = _MfaMock();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.mfa).thenReturn(mfa);
      service = SupabaseAuthService(client: client);
    });

    void verifyOnlyMfaCall() {
      verifyNoMoreInteractions(mfa);
      verify(() => auth.mfa).called(1);
      verifyNoMoreInteractions(auth);
      verify(() => client.auth).called(1);
      verifyNoMoreInteractions(client);
    }

    test('construction makes no SDK calls', () {
      verifyZeroInteractions(client);
      verifyZeroInteractions(auth);
      verifyZeroInteractions(mfa);
    });

    test(
      'listMfaFactors returns the unchanged SDK result with one call',
      () async {
        final result = AuthMFAListFactorsResponse(all: [], totp: [], phone: []);
        when(() => mfa.listFactors()).thenAnswer((_) async => result);

        expect(await service.listMfaFactors(), same(result));

        verify(() => mfa.listFactors()).called(1);
        verifyOnlyMfaCall();
      },
    );

    for (final levels in [
      (null, null),
      (AuthenticatorAssuranceLevels.aal1, AuthenticatorAssuranceLevels.aal2),
      (AuthenticatorAssuranceLevels.aal2, AuthenticatorAssuranceLevels.aal2),
    ]) {
      test('getMfaAssurance preserves synchronous SDK levels $levels', () {
        final result = AuthMFAGetAuthenticatorAssuranceLevelResponse(
          currentLevel: levels.$1,
          nextLevel: levels.$2,
          currentAuthenticationMethods: [],
        );
        when(() => mfa.getAuthenticatorAssuranceLevel()).thenReturn(result);

        expect(service.getMfaAssurance(), same(result));

        verify(() => mfa.getAuthenticatorAssuranceLevel()).called(1);
        verifyOnlyMfaCall();
      });
    }

    for (final friendlyName in [null, 'My authenticator']) {
      test('enrollTotp forwards name=$friendlyName and fixed issuer', () async {
        const result = AuthMFAEnrollResponse(
          id: 'synthetic-factor',
          type: FactorType.totp,
          totp: TOTPEnrollment(
            qrCode: 'synthetic-qr',
            secret: 'synthetic-secret',
            uri: 'otpauth://synthetic',
          ),
        );
        when(
          () => mfa.enroll(
            factorType: FactorType.totp,
            issuer: 'Clean Stream Laundry',
            friendlyName: friendlyName,
          ),
        ).thenAnswer((_) async => result);

        final response = friendlyName == null
            ? await service.enrollTotp()
            : await service.enrollTotp(friendlyName: friendlyName);
        expect(response, same(result));

        verify(
          () => mfa.enroll(
            factorType: FactorType.totp,
            issuer: 'Clean Stream Laundry',
            friendlyName: friendlyName,
          ),
        ).called(1);
        verifyOnlyMfaCall();
      });
    }

    test(
      'verifyTotp fails closed without an isolated client factory',
      () async {
        when(
          () => auth.currentSession,
        ).thenReturn(Session.fromJson(_session('aal1')));

        await expectLater(
          service.verifyTotp(factorId: 'synthetic-factor', code: '123456'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              'Isolated MFA client is not configured.',
            ),
          ),
        );

        verifyZeroInteractions(mfa);
      },
    );

    for (final operation in ['list', 'assurance', 'enroll']) {
      test(
        '$operation propagates the same provider error without retry',
        () async {
          final error = AuthApiException(
            'Synthetic provider rejection',
            statusCode: '400',
            code: 'synthetic_error',
          );
          switch (operation) {
            case 'list':
              when(() => mfa.listFactors()).thenAnswer((_) async => throw error);
              await expectLater(service.listMfaFactors, throwsA(same(error)));
              verify(() => mfa.listFactors()).called(1);
            case 'assurance':
              when(() => mfa.getAuthenticatorAssuranceLevel()).thenThrow(error);
              expect(service.getMfaAssurance, throwsA(same(error)));
              verify(() => mfa.getAuthenticatorAssuranceLevel()).called(1);
            case 'enroll':
              when(
                () => mfa.enroll(
                  factorType: FactorType.totp,
                  issuer: 'Clean Stream Laundry',
                  friendlyName: null,
                ),
              ).thenAnswer((_) async => throw error);
              await expectLater(service.enrollTotp, throwsA(same(error)));
              verify(
                () => mfa.enroll(
                  factorType: FactorType.totp,
                  issuer: 'Clean Stream Laundry',
                  friendlyName: null,
                ),
              ).called(1);
          }
          verifyOnlyMfaCall();
        },
      );
    }

    test('assurance parsing errors are not converted to an admitted state', () {
      const error = FormatException('Synthetic malformed JWT');
      when(() => mfa.getAuthenticatorAssuranceLevel()).thenThrow(error);

      expect(service.getMfaAssurance, throwsA(same(error)));

      verify(() => mfa.getAuthenticatorAssuranceLevel()).called(1);
      verifyOnlyMfaCall();
    });
  });

  group('installed SDK with offline HTTP', () {
    test(
      'list refreshes once and retains SDK filtering and session event',
      () async {
        final factors = [
          _factor('verified-totp', 'totp', 'verified'),
          _factor('unverified-totp', 'totp', 'unverified'),
          _factor('verified-phone', 'phone', 'verified'),
        ];
        await _withSdk(
          [(status: 200, json: _session('aal1', factors: factors))],
          (auth, service, requests, events) async {
            final result = await service.listMfaFactors();
            await Future<void>.delayed(Duration.zero);

            expect(result, isA<AuthMFAListFactorsResponse>());
            expect(result.all.map((f) => f.id), [
              'verified-totp',
              'unverified-totp',
              'verified-phone',
            ]);
            expect(result.totp.map((f) => f.id), ['verified-totp']);
            expect(result.phone.map((f) => f.id), ['verified-phone']);
            _expectRequests(requests, [
              (
                method: 'POST',
                path: '/token?grant_type=refresh_token',
                body: {'refresh_token': 'synthetic-refresh'},
              ),
            ]);
            expect(events.map((e) => e.event), [
              AuthChangeEvent.tokenRefreshed,
            ]);
            expect(auth.currentUser!.factors, result.all);
            expect(
              service.getMfaAssurance().currentLevel,
              AuthenticatorAssuranceLevels.aal1,
            );
            expect(
              service.getMfaAssurance().nextLevel,
              AuthenticatorAssuranceLevels.aal2,
            );
            expect(requests, hasLength(1));
          },
        );
      },
    );

    test('enroll preserves SDK TOTP payload without session changes', () async {
      await _withSdk(
        [
          (
            status: 200,
            json: {
              'id': 'synthetic-factor',
              'type': 'totp',
              'totp': {
                'qr_code': '<svg/>',
                'secret': 'synthetic-secret',
                'uri': 'otpauth://synthetic',
              },
            },
          ),
        ],
        (auth, service, requests, events) async {
          final before = auth.currentSession;
          final result = await service.enrollTotp();
          await Future<void>.delayed(Duration.zero);

          expect(result.totp!.qrCode, 'data:image/svg+xml;utf-8,<svg/>');
          expect(result.totp!.secret, 'synthetic-secret');
          expect(result.totp!.uri, 'otpauth://synthetic');
          _expectRequests(requests, [
            (
              method: 'POST',
              path: '/factors',
              body: {
                'friendly_name': null,
                'factor_type': 'totp',
                'issuer': 'Clean Stream Laundry',
              },
            ),
          ]);
          expect(auth.currentSession, same(before));
          expect(events, isEmpty);
        },
      );
    });

    test(
      'verify adopts one main SDK session and emits one refresh event',
      () async {
        await _withSdk(
          [
            (status: 200, json: _challenge),
            (
              status: 200,
              json: _session(
                'aal2',
                factors: [_factor('synthetic-factor', 'totp', 'verified')],
              ),
            ),
            (status: 200, json: _session('aal2')),
          ],
          (auth, service, requests, events) async {
            final signedInEvents = <bool>[];
            final subscription = service.onAuthChange.listen(
              signedInEvents.add,
            );
            try {
              await Future<void>.delayed(Duration.zero);
              expect(signedInEvents, [true]);
              signedInEvents.clear();
              expect(
                service.getMfaAssurance().currentLevel,
                AuthenticatorAssuranceLevels.aal1,
              );
              final result = await service.verifyTotp(
                factorId: 'synthetic-factor',
                code: '123456',
              );
              await Future<void>.delayed(Duration.zero);

              _expectRequests(requests, [
                ..._verificationRequests,
                (
                  method: 'POST',
                  path: '/token?grant_type=refresh_token',
                  body: {'refresh_token': 'synthetic-refresh'},
                ),
              ]);
              expect(auth.currentSession!.accessToken, result.accessToken);
              expect(auth.currentSession!.refreshToken, result.refreshToken);
              expect(auth.currentUser, result.user);
              expect(
                service.getMfaAssurance().currentLevel,
                AuthenticatorAssuranceLevels.aal2,
              );
              expect(events.map((e) => e.event), [
                AuthChangeEvent.tokenRefreshed,
              ]);
              expect(events.single.session, same(auth.currentSession));
              expect(signedInEvents, [true]);
            } finally {
              await subscription.cancel();
            }
          },
        );
      },
    );

    for (final failChallenge in [true, false]) {
      test(
        'SDK failure challenge=$failChallenge leaves session and events unchanged',
        () async {
          await _withSdk(
            [
              if (!failChallenge) (status: 200, json: _challenge),
              (
                status: 400,
                json: {
                  'msg': 'Synthetic rejection',
                  'error_code': 'synthetic_error',
                },
              ),
            ],
            (auth, service, requests, events) async {
              final before = auth.currentSession;
              await expectLater(
                () => service.verifyTotp(
                  factorId: 'synthetic-factor',
                  code: '123456',
                ),
                throwsA(
                  isA<AuthApiException>()
                      .having((e) => e.code, 'code', 'synthetic_error')
                      .having((e) => e.statusCode, 'statusCode', '400'),
                ),
              );
              await Future<void>.delayed(Duration.zero);

              _expectRequests(
                requests,
                failChallenge
                    ? _verificationRequests.take(1).toList()
                    : _verificationRequests,
              );
              expect(auth.currentSession, same(before));
              expect(
                service.getMfaAssurance().currentLevel,
                AuthenticatorAssuranceLevels.aal1,
              );
              expect(events, isEmpty);
            },
          );
        },
      );
    }
  });
}

typedef _Request = ({String method, String path, Map<String, dynamic> body});
typedef _Reply = ({int status, Map<String, dynamic> json});

void _expectRequests(List<_Request> actual, List<_Request> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].method, expected[i].method);
    expect(actual[i].path, expected[i].path);
    expect(actual[i].body, expected[i].body);
  }
}

const _challenge = {'id': 'synthetic-challenge', 'expires_at': 4102444800};
const List<_Request> _verificationRequests = [
  (
    method: 'POST',
    path: '/auth/v1/factors/synthetic-factor/challenge',
    body: {},
  ),
  (
    method: 'POST',
    path: '/auth/v1/factors/synthetic-factor/verify',
    body: {'challenge_id': 'synthetic-challenge', 'code': '123456'},
  ),
];

Map<String, dynamic> _factor(String id, String type, String status) => {
  'id': id,
  'factor_type': type,
  'status': status,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

// Unsigned synthetic fixtures are decoded only by the offline SDK under test.
Map<String, dynamic> _session(
  String aal, {
  List<Map<String, dynamic>> factors = const [],
}) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encode({'alg': 'none'})}.${encode({'sub': 'synthetic-user', 'aal': aal, 'amr': [], 'exp': 4102444800})}.c3ludGhldGlj';
  return {
    'access_token': token,
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': 'synthetic-user',
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '',
      'factors': factors,
    },
  };
}

class _HttpClient extends Mock implements HttpClient {}

class _HttpRequest extends Mock implements HttpClientRequest {}

class _HttpHeaders extends Mock implements HttpHeaders {}

class _HttpResponse extends Mock implements HttpClientResponse {
  final List<int> bytes;

  _HttpResponse(_Reply reply) : bytes = utf8.encode(jsonEncode(reply.json)) {
    when(() => statusCode).thenReturn(reply.status);
    when(() => contentLength).thenReturn(bytes.length);
    when(() => headers).thenReturn(_HttpHeaders());
    when(() => isRedirect).thenReturn(false);
    when(() => redirects).thenReturn([]);
    when(() => persistentConnection).thenReturn(false);
    when(() => reasonPhrase).thenReturn('Synthetic response');
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

Future<void> _withSdk(
  List<_Reply> replies,
  Future<void> Function(
    GoTrueClient,
    AuthService,
    List<_Request>,
    List<AuthState>,
  )
  run,
) async {
  final http = _HttpClient();
  final requests = <_Request>[];
  when(() => http.openUrl(any(), any())).thenAnswer((invocation) async {
    final request = _HttpRequest();
    final bytes = <int>[];
    when(() => request.headers).thenReturn(_HttpHeaders());
    when(() => request.addStream(any())).thenAnswer((call) async {
      await for (final chunk
          in call.positionalArguments.single as Stream<List<int>>) {
        bytes.addAll(chunk);
      }
    });
    when(() => request.close()).thenAnswer((_) async {
      final uri = invocation.positionalArguments[1] as Uri;
      expect(uri.origin, 'https://synthetic.invalid');
      requests.add((
        method: invocation.positionalArguments[0] as String,
        path: uri.query.isEmpty ? uri.path : '${uri.path}?${uri.query}',
        body: bytes.isEmpty
            ? {}
            : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      ));
      final index = requests.length - 1;
      return _HttpResponse(
        index < replies.length
            ? replies[index]
            : (status: 400, json: {'msg': 'Unexpected offline request'}),
      );
    });
    return request;
  });

  // Every HTTP client in this zone is a mock: no socket or provider can be reached.
  await HttpOverrides.runZoned(() async {
    final auth = GoTrueClient(
      url: 'https://synthetic.invalid',
      autoRefreshToken: false,
    );
    final events = <AuthState>[];
    await auth.setInitialSession(jsonEncode(_session('aal1')));
    final subscription = auth.onAuthStateChange.listen(events.add);
    final client = SupabaseMock();
    when(() => client.auth).thenReturn(auth);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e.event), [AuthChangeEvent.initialSession]);
      events.clear();
      await run(
        auth,
        SupabaseAuthService(
          client: client,
          mfaClientFactory: (accessToken) => MfaVerificationClient(
            supabaseUrl: 'https://synthetic.invalid',
            publicKey: 'synthetic-public-key',
            accessToken: accessToken,
          ),
        ),
        requests,
        events,
      );
    } finally {
      await subscription.cancel();
      auth.dispose();
    }
  }, createHttpClient: (_) => http);
}
