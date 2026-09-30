import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clean_stream_laundry_app/core/di/di.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/mfa_verification_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  test(
    'commits refreshed AAL2 tokens, not the isolated verification tokens',
    () async {
      await _withFixture((f) async {
        final result = await f.verify();
        expect(result.accessToken, f.main.auth.currentSession!.accessToken);
        expect(result.refreshToken, 'a-adopted-refresh');
        expect(result.refreshToken, isNot('a-verified-refresh'));
        expect(result.expiresIn, const Duration(seconds: 3600));
        expect(result.user.id, 'a');
        expect(f.steps, ['challenge', 'verify', 'adopt']);
        expect(f.isolated.single.disposeCount, 1);
        await _tick();
        expect(f.events.map((e) => e.event), [AuthChangeEvent.tokenRefreshed]);
        expect(f.events.single.session, same(f.main.auth.currentSession));
        expect(f.errors, isEmpty);
      });
    },
  );

  for (final stage in ['challenge', 'verify', 'adopt']) {
    for (final change in ['B', 'A-B-A', 'logout']) {
      test(
        '$change during $stage rejects late success and preserves current session',
        () async {
          await _withFixture((f) async {
            f.hold(stage);
            final pending = expectLater(
              f.verify(),
              throwsA(isA<AuthException>()),
            );
            await f.started.future;
            await f.changeSession(change);
            final newer = f.main.auth.currentSession;
            f.release.complete();
            await pending;
            expect(f.main.auth.currentSession, same(newer));
            expect(f.steps, _stepsThrough(stage));
            expect(f.isolated.single.disposeCount, 1);
            await _tick();
            expect(
              f.events.where((e) => e.event == AuthChangeEvent.tokenRefreshed),
              isEmpty,
            );
          });
        },
      );
    }

    for (final failure in ['provider', 'malformed']) {
      for (final switchAccount in [false, true]) {
        test(
          '$failure at $stage, newer account=$switchAccount, disposes without compensation',
          () async {
            await _withFixture((f) async {
              f.hold(stage);
              f.failureStage = stage;
              f.failure = failure;
              final pending = expectLater(
                f.verify(),
                throwsA(
                  failure == 'provider'
                      ? isA<AuthApiException>()
                      : isA<FormatException>(),
                ),
              );
              await f.started.future;
              if (switchAccount) await f.changeSession('B');
              final before = f.main.auth.currentSession;
              f.release.complete();
              await pending;
              // The SDK itself clears an unchanged session on a rejected refresh.
              // Never issue compensating logout or silently report success.
              expect(
                f.main.auth.currentSession,
                stage == 'adopt' && failure == 'provider' && !switchAccount
                    ? isNull
                    : same(before),
              );
              expect(f.steps, _stepsThrough(stage));
              expect(f.isolated.single.disposeCount, 1);
            });
          },
        );
      }
    }

    test(
      'duplicate during $stage is rejected; later attempts get a fresh client',
      () async {
        await _withFixture((f) async {
          f.hold(stage);
          final pending = f.verify();
          await f.started.future;
          await expectLater(
            f.verify(),
            throwsA(
              isA<AuthException>().having(
                (e) => e.message,
                'message',
                'MFA verification is already in progress.',
              ),
            ),
          );
          expect(f.isolated, hasLength(1));
          f.release.complete();
          await pending;
          f.heldStage = null;
          await f.verify();
          expect(f.steps, [
            'challenge',
            'verify',
            'adopt',
            'challenge',
            'verify',
            'adopt',
          ]);
          expect(f.isolated.map((c) => c.disposeCount), [1, 1]);
        });
      },
    );

    test(
      'main disposal during $stage cannot produce a committed success',
      () async {
        await _withFixture((f) async {
          f.hold(stage);
          final before = f.main.auth.currentSession;
          final pending = expectLater(
            f.verify(),
            throwsA(isA<AuthException>()),
          );
          await f.started.future;
          f.main.auth.dispose();
          f.release.complete();
          await pending;
          await _tick();
          expect(f.main.auth.currentSession, same(before));
          expect(f.isolated.single.disposeCount, 1);
          expect(f.steps, ['challenge', 'verify', 'adopt']);
        });
      },
    );
  }

  for (final state in ['missing', 'expired', 'unknown expiry']) {
    test(
      '$state initial session fails before client creation or HTTP',
      () async {
        await _withFixture((f) async {
          if (state == 'missing') {
            await f.changeSession('logout');
          } else {
            f.main.auth.currentSession!.expiresAt = state == 'expired'
                ? 1
                : null;
          }
          await expectLater(f.verify(), throwsA(isA<AuthException>()));
          expect(f.isolated, isEmpty);
          expect(f.steps, isEmpty);
        });
      },
    );
  }

  for (final stage in ['challenge', 'verify']) {
    test(
      'expiry during $stage stops the next request without rotating main refresh token',
      () async {
        await _withFixture((f) async {
          f.hold(stage);
          final before = f.main.auth.currentSession;
          final pending = expectLater(
            f.verify(),
            throwsA(isA<AuthException>()),
          );
          await f.started.future;
          // Session exposes this field; moving only its deadline avoids wall-clock sleeps.
          before!.expiresAt = 1;
          f.release.complete();
          await pending;
          expect(f.main.auth.currentSession, same(before));
          expect(f.steps, _stepsThrough(stage));
          expect(f.isolated.single.disposeCount, 1);
        });
      },
    );
  }

  for (final stage in ['verify', 'adopt']) {
    for (final invalid in ['expired', 'unknown expiry', 'wrong user', 'aal1']) {
      test(
        '$invalid $stage response never reports successful verification',
        () async {
          await _withFixture((f) async {
            f.invalidStage = stage;
            f.invalid = invalid;
            await expectLater(f.verify(), throwsA(isA<AuthException>()));
            expect(f.steps, _stepsThrough(stage));
            expect(f.isolated.single.disposeCount, 1);
            if (stage == 'verify') {
              expect(
                f.main.auth.currentSession!.refreshToken,
                'a-initial-refresh',
              );
            }
          });
        },
      );
    }
  }

  test(
    'already-used refresh fallback to the original session is not adoption',
    () async {
      await _withFixture((f) async {
        f.failureStage = 'adopt';
        f.failure = 'already used';
        final before = f.main.auth.currentSession;
        await expectLater(f.verify(), throwsA(isA<AuthException>()));
        expect(f.main.auth.currentSession, same(before));
        expect(f.isolated.single.disposeCount, 1);
      });
    },
  );

  test('factory failure releases the duplicate guard for a retry', () async {
    await _withFixture((f) async {
      f.factoryFailure = true;
      await expectLater(f.verify(), throwsStateError);
      expect(f.steps, isEmpty);
      f.factoryFailure = false;
      await f.verify();
      expect(f.isolated.single.disposeCount, 1);
    });
  });

  test(
    'refresh reuse after A-B-A with AAL2 cannot masquerade as adoption',
    () async {
      await _withFixture((f) async {
        f.hold('adopt');
        f.failureStage = 'adopt';
        f.failure = 'already used';
        final pending = expectLater(f.verify(), throwsA(isA<AuthException>()));
        await f.started.future;
        await f.changeSession('B');
        await f.main.auth.setInitialSession(
          jsonEncode(_session('a', 'new', aal: 'aal2')),
        );
        final newer = f.main.auth.currentSession;
        f.release.complete();
        await pending;
        expect(f.main.auth.currentSession, same(newer));
        expect(f.isolated.single.disposeCount, 1);
      });
    },
  );

  test('request setup failure still disposes and permits a retry', () async {
    await _withFixture((f) async {
      f.seedFailure = true;
      await expectLater(f.verify(), throwsStateError);
      expect(f.steps, isEmpty);
      expect(f.isolated.single.disposeCount, 1);
      f.seedFailure = false;
      await f.verify();
      expect(f.isolated.map((c) => c.disposeCount), [1, 1]);
    });
  });

  test(
    'DI creates separate HTTP-only clients with captured bearer and no refresh ticker',
    () async {
      final requests = <_Request>[];
      await _withHttp(
        (request) async {
          requests.add(request);
          expect(request.uri.origin, 'https://offline.invalid');
          expect(request.uri.path, '/auth/v1/factors/factor-a/challenge');
          expect(request.uri.queryParameters, isEmpty);
          expect(request.headers['apikey'], 'synthetic-public-key');
          expect(
            request.headers['authorization'],
            'Bearer ${_session('a', 'initial')['access_token']}',
          );
          return (status: 200, body: jsonEncode(_challenge));
        },
        () => runZoned(
          () async {
            final first = createMfaVerificationClient(
              supabaseUrl: 'https://offline.invalid',
              publicKey: 'synthetic-public-key',
              accessToken: _session('a', 'initial')['access_token'] as String,
            );
            final second = createMfaVerificationClient(
              supabaseUrl: 'https://offline.invalid',
              publicKey: 'synthetic-public-key',
              accessToken: 'different-synthetic-token',
            );
            try {
              expect(identical(first, second), isFalse);
              await first.challenge(factorId: 'factor-a');
              expect(requests, hasLength(1));
            } finally {
              first.dispose();
              second.dispose();
            }
          },
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              throw StateError(
                'Temporary Auth must not start a refresh ticker',
              );
            },
          ),
        ),
      );
    },
  );
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);
List<String> _stepsThrough(String stage) => [
  'challenge',
  'verify',
  'adopt',
].take(['challenge', 'verify', 'adopt'].indexOf(stage) + 1).toList();
const _challenge = {'id': 'challenge-a', 'expires_at': 4102444800};

Map<String, dynamic> _session(
  String user,
  String label, {
  String aal = 'aal1',
  int? expiresAt = 4102444800,
}) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'none'})}.${encode({'sub': user, 'session_id': '$user-session', 'aal': aal, 'amr': [], 'label': label, if (expiresAt != null) 'exp': expiresAt})}.c3ludGhldGlj',
    'refresh_token': '$user-$label-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': user,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '',
    },
  };
}

class _TrackedAuth extends MfaVerificationClient {
  int disposeCount = 0;
  final bool seedFailure;
  _TrackedAuth(this.seedFailure, String accessToken)
    : super(
        supabaseUrl: 'https://offline.invalid',
        publicKey: 'synthetic-public-key',
        accessToken: accessToken,
      );

  @override
  Future<AuthMFAChallengeResponse> challenge({required String factorId}) {
    if (seedFailure) throw StateError('Synthetic request setup failure');
    return super.challenge(factorId: factorId);
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

class _Fixture {
  late final SupabaseClient main;
  late final SupabaseAuthService service;
  final isolated = <_TrackedAuth>[];
  final events = <AuthState>[];
  final errors = <Object>[];
  final steps = <String>[];
  final started = Completer<void>();
  final release = Completer<void>();
  String? heldStage;
  String? failureStage;
  String? failure;
  String? invalidStage;
  String? invalid;
  bool factoryFailure = false;
  bool seedFailure = false;
  int requestedLogouts = 0;
  int logoutCalls = 0;
  String? bearer;

  void hold(String stage) => heldStage = stage;
  Future<AuthMFAVerifyResponse> verify() {
    bearer = 'Bearer ${main.auth.currentSession?.accessToken}';
    return service.verifyTotp(factorId: 'factor-a', code: '123456');
  }

  Future<void> changeSession(String change) async {
    if (change == 'logout') {
      requestedLogouts++;
      await main.auth.signOut(scope: SignOutScope.local);
    } else {
      await main.auth.setInitialSession(jsonEncode(_session('b', 'new')));
      if (change == 'A-B-A') {
        // Same tokens, same user, new Session identity must still invalidate A.
        await main.auth.setInitialSession(jsonEncode(_session('a', 'initial')));
      }
    }
  }

  Future<_Reply> respond(_Request request) async {
    expect(request.uri.host, 'offline.invalid');
    if (request.uri.path.endsWith('/logout')) {
      logoutCalls++;
      expect(logoutCalls, requestedLogouts);
      expect(request.uri.queryParameters['scope'], 'local');
      return (status: 204, body: '');
    }
    expect(request.method, 'POST');
    final stage = request.uri.path.endsWith('/token')
        ? 'adopt'
        : request.uri.path.split('/').last;
    expect(['challenge', 'verify', 'adopt'], contains(stage));
    steps.add(stage);
    expect(request.headers['apikey'], 'synthetic-public-key');
    if (stage == 'adopt') {
      expect(request.uri.queryParameters, {'grant_type': 'refresh_token'});
      expect(request.body, {'refresh_token': 'a-verified-refresh'});
    } else {
      expect(request.headers['authorization'], bearer);
      expect(request.uri.path, '/auth/v1/factors/factor-a/$stage');
      expect(
        request.body,
        stage == 'challenge'
            ? {}
            : {'challenge_id': 'challenge-a', 'code': '123456'},
      );
    }
    if (stage == heldStage) {
      started.complete();
      await release.future;
    }
    if (stage == failureStage) {
      if (failure == 'malformed') {
        return (
          status: 200,
          body:
              '{"access_token":"synthetic","user":"invalid","expires_in":"invalid"}',
        );
      }
      return (
        status: 400,
        body: jsonEncode({
          'msg': 'Synthetic rejection',
          'error_code': failure == 'already used'
              ? 'refresh_token_already_used'
              : 'synthetic_rejection',
        }),
      );
    }
    if (stage == 'challenge') {
      return (status: 200, body: jsonEncode(_challenge));
    }
    final response = _session(
      invalidStage == stage && invalid == 'wrong user' ? 'b' : 'a',
      stage == 'verify' ? 'verified' : 'adopted',
      aal: invalidStage == stage && invalid == 'aal1' ? 'aal1' : 'aal2',
      expiresAt: invalidStage == stage && invalid == 'expired'
          ? 1
          : invalidStage == stage && invalid == 'unknown expiry'
          ? null
          : 4102444800,
    );
    return (status: 200, body: jsonEncode(response));
  }
}

Future<void> _withFixture(Future<void> Function(_Fixture) run) async {
  final f = _Fixture();
  await _withHttp(f.respond, () async {
    f.main = SupabaseClient(
      'https://offline.invalid',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await f.main.auth.setInitialSession(jsonEncode(_session('a', 'initial')));
    f.service = SupabaseAuthService(
      client: f.main,
      mfaClientFactory: (accessToken) {
        if (f.factoryFailure) throw StateError('Synthetic factory failure');
        final client = _TrackedAuth(f.seedFailure, accessToken);
        f.isolated.add(client);
        return client;
      },
    );
    final subscription = f.main.auth.onAuthStateChange.listen(
      f.events.add,
      onError: (Object error) => f.errors.add(error),
    );
    await _tick();
    f.events.clear();
    try {
      await run(f);
      expect(f.main.getChannels(), isEmpty);
      expect(f.main.realtime.isConnected, isFalse);
      expect(f.isolated.every((c) => c.disposeCount == 1), isTrue);
      expect(f.logoutCalls, f.requestedLogouts);
    } finally {
      await subscription.cancel();
      await f.main.dispose();
    }
  });
}

typedef _Request = ({
  String method,
  Uri uri,
  Map<String, String> headers,
  Map<String, dynamic> body,
});
typedef _Reply = ({int status, String body});

class _HttpClient extends Mock implements HttpClient {}

class _HttpRequest extends Mock implements HttpClientRequest {}

class _HttpHeaders extends Mock implements HttpHeaders {}

class _HttpResponse extends Mock implements HttpClientResponse {
  final List<int> bytes;
  _HttpResponse(_Reply reply) : bytes = utf8.encode(reply.body) {
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

Future<void> _withHttp(
  Future<_Reply> Function(_Request) respond,
  Future<void> Function() run,
) async {
  final http = _HttpClient();
  when(() => http.openUrl(any(), any())).thenAnswer((call) async {
    final request = _HttpRequest();
    final headers = _HttpHeaders();
    final values = <String, String>{};
    final bytes = <int>[];
    when(() => request.headers).thenReturn(headers);
    when(() => headers.set(any(), any())).thenAnswer((call) {
      values[(call.positionalArguments[0] as String).toLowerCase()] = call
          .positionalArguments[1]
          .toString();
    });
    when(() => request.addStream(any())).thenAnswer((call) async {
      await for (final chunk
          in call.positionalArguments.single as Stream<List<int>>) {
        bytes.addAll(chunk);
      }
    });
    when(() => request.close()).thenAnswer(
      (_) async => _HttpResponse(
        await respond((
          method: call.positionalArguments[0] as String,
          uri: call.positionalArguments[1] as Uri,
          headers: values,
          body: bytes.isEmpty
              ? {}
              : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        )),
      ),
    );
    return request;
  });
  // Every HTTP client in this zone is synthetic; no socket or real Auth is used.
  await HttpOverrides.runZoned(run, createHttpClient: (_) => http);
}
