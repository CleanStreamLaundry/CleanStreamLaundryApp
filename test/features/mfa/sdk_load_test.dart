import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clean_stream_laundry_app/features/mfa/controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  for (final enrolled in [false, true]) {
    test(
      'real SDK listing refresh reaches ${enrolled ? 'challenge' : 'ready'} without access callback',
      () async {
        await _withSdk(
          enrolled: enrolled,
          run: (fixture) async {
            final original = fixture.sdk.currentSession;
            final request = fixture.controller.load();
            await fixture.started.future;
            expect(fixture.controller.isBusy, true);
            fixture.release.complete();
            await request;
            expect(fixture.sdk.currentSession, isNot(same(original)));
            expect(fixture.sdk.currentSession!.user.id, 'a');
            expect(fixture.events.map((state) => state.event), [
              AuthChangeEvent.tokenRefreshed,
            ]);
            expect(
              fixture.controller.stage,
              enrolled ? MfaStage.challenge : MfaStage.readyToEnroll,
            );
            expect(
              fixture.controller.factorId,
              enrolled ? 'verified-totp' : null,
            );
            expect(fixture.controller.canRevalidate, false);
            verifyNever(() => fixture.auth.enrollTotp());
            verifyNever(
              () => fixture.auth.verifyTotp(
                factorId: any(named: 'factorId'),
                code: any(named: 'code'),
              ),
            );
          },
        );
      },
    );
  }

  for (final change in ['B', 'A-B-A']) {
    test(
      'real SDK delayed listing after $change keeps controller closed',
      () async {
        await _withSdk(
          enrolled: true,
          run: (fixture) async {
            final request = fixture.controller.load();
            await fixture.started.future;
            await fixture.sdk.setInitialSession(
              jsonEncode(_session('b', 'new')),
            );
            if (change == 'A-B-A') {
              await fixture.sdk.setInitialSession(
                jsonEncode(_session('a', 'initial')),
              );
            }
            final newer = fixture.sdk.currentSession;
            fixture.release.complete();
            await request;
            expect(fixture.sdk.currentSession, same(newer));
            expect(
              fixture.events.where(
                (state) => state.event == AuthChangeEvent.tokenRefreshed,
              ),
              isEmpty,
            );
            expect(fixture.controller.stage, MfaStage.expired);
            expect(fixture.controller.factorId, null);
            expect(fixture.controller.canEnroll, false);
            expect(fixture.controller.canVerify, false);
          },
        );
      },
    );
  }
}

Map<String, dynamic> _session(
  String user,
  String label, {
  bool enrolled = false,
}) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'none'})}.${encode({'sub': user, 'aal': 'aal1', 'amr': [], 'label': label, 'exp': 4102444800})}.synthetic',
    'refresh_token': '$user-$label-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': user,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
      'factors': [if (enrolled) factor().toJson()],
    },
  };
}

class _SdkFixture {
  final sdk = GoTrueClient(
    url: 'https://offline.invalid/auth/v1',
    headers: {'apikey': 'synthetic-public-key'},
    autoRefreshToken: false,
  );
  final auth = MockMfaAuth();
  late final MfaController controller;
  final events = <AuthState>[];
  final started = Completer<void>();
  final release = Completer<void>();
}

Future<void> _withSdk({
  required bool enrolled,
  required Future<void> Function(_SdkFixture) run,
}) async {
  final http = _HttpClient();
  var requests = 0;
  late _SdkFixture fixture;
  when(() => http.openUrl(any(), any())).thenAnswer((call) async {
    requests++;
    expect(call.positionalArguments[0], 'POST');
    expect(
      call.positionalArguments[1],
      Uri.parse(
        'https://offline.invalid/auth/v1/token?grant_type=refresh_token',
      ),
    );
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
    when(() => request.close()).thenAnswer((_) async {
      expect(values['apikey'], 'synthetic-public-key');
      expect(jsonDecode(utf8.decode(bytes)), {
        'refresh_token': 'a-initial-refresh',
      });
      fixture.started.complete();
      await fixture.release.future;
      return _HttpResponse(
        jsonEncode(_session('a', 'listed', enrolled: enrolled)),
      );
    });
    return request;
  });
  // Standard dart:io transport is replaced for the entire zone; no socket/Auth.
  await HttpOverrides.runZoned(() async {
    fixture = _SdkFixture();
    await fixture.sdk.setInitialSession(jsonEncode(_session('a', 'initial')));
    // Delegate only the existing AuthService listing/session seam to the real SDK.
    when(
      () => fixture.auth.currentSession,
    ).thenAnswer((_) => fixture.sdk.currentSession);
    when(
      () => fixture.auth.authStateChanges,
    ).thenAnswer((_) => fixture.sdk.onAuthStateChange);
    when(
      () => fixture.auth.listMfaFactors(),
    ).thenAnswer((_) => fixture.sdk.mfa.listFactors());
    when(
      () => fixture.auth.getMfaAssurance(),
    ).thenAnswer((_) => fixture.sdk.mfa.getAuthenticatorAssuranceLevel());
    fixture.controller = MfaController(
      authService: fixture.auth,
      mode: enrolled ? MfaMode.challenge : MfaMode.enrollment,
    );
    final subscription = fixture.sdk.onAuthStateChange.listen(
      fixture.events.add,
    );
    await Future<void>.delayed(Duration.zero);
    fixture.events.clear();
    try {
      await run(fixture);
      expect(requests, 1);
    } finally {
      if (!fixture.release.isCompleted) fixture.release.complete();
      fixture.controller.dispose();
      await subscription.cancel();
      fixture.sdk.dispose();
    }
  }, createHttpClient: (_) => http);
}

class _HttpClient extends Mock implements HttpClient {}

class _HttpRequest extends Mock implements HttpClientRequest {}

class _HttpHeaders extends Mock implements HttpHeaders {}

class _HttpResponse extends Mock implements HttpClientResponse {
  final List<int> bytes;
  _HttpResponse(String body) : bytes = utf8.encode(body) {
    when(() => statusCode).thenReturn(200);
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
