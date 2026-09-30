@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/services/supabase/mfa_verification_client.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final stage in ['challenge', 'verify', 'adopt']) {
    test('same-origin broadcast B survives late A $stage completion', () async {
      final f = await _BrowserFixture.create(stage);
      try {
        final pending = expectLater(f.verify(), throwsA(isA<AuthException>()));
        await f.started.future;
        await f.broadcastB();
        final newer = f.main.auth.currentSession;
        f.release.complete();
        await pending;
        await _drainMessages();
        expect(f.main.auth.currentSession, same(newer));
        expect(f.peer.currentUser!.id, 'b');
        expect(
          f.steps,
          [
            'challenge',
            'verify',
            'adopt',
          ].take(['challenge', 'verify', 'adopt'].indexOf(stage) + 1),
        );
        expect(
          f.events.where(
            (e) => e.event == AuthChangeEvent.mfaChallengeVerified,
          ),
          isEmpty,
        );
        expect(
          f.peerEvents.where(
            (e) => e.event == AuthChangeEvent.mfaChallengeVerified,
          ),
          isEmpty,
        );
        expect(
          f.events.any((e) => e.session?.refreshToken == 'a-verified-refresh'),
          isFalse,
        );
        expect(
          f.peerEvents.any(
            (e) => e.session?.refreshToken == 'a-verified-refresh',
          ),
          isFalse,
        );
        expect(f.transportHttp.closeCount, 1);
      } finally {
        await f.dispose();
      }
    });
  }

  test(
    'only guarded adoption broadcasts AAL2, never the verification response',
    () async {
      final f = await _BrowserFixture.create('adopt');
      try {
        final pending = f.verify();
        await f.started.future;
        await _drainMessages();
        expect(f.main.auth.currentSession!.refreshToken, 'a-initial-refresh');
        expect(f.peer.currentSession!.refreshToken, 'a-initial-refresh');
        expect(f.events, isEmpty);
        expect(f.peerEvents, isEmpty);
        final received = f.peer.onAuthStateChange
            .firstWhere((e) => e.session?.refreshToken == 'a-adopted-refresh')
            .timeout(const Duration(seconds: 5));
        f.release.complete();
        final result = await pending;
        await received;
        await _drainMessages();
        expect(result.refreshToken, 'a-adopted-refresh');
        expect(f.events.map((e) => e.event), [AuthChangeEvent.tokenRefreshed]);
        expect(f.peerEvents.map((e) => e.event), [
          AuthChangeEvent.tokenRefreshed,
        ]);
        expect(f.transportHttp.closeCount, 1);
      } finally {
        await f.dispose();
      }
    },
  );

  test('HTTP transport ignores inbound same-origin Auth broadcasts', () async {
    final f = await _BrowserFixture.create('challenge');
    final transport = MfaVerificationClient(
      supabaseUrl: _url,
      publicKey: _key,
      accessToken: _session('a', 'initial')['access_token'] as String,
      httpClient: f.transportHttp,
    );
    try {
      final pending = transport.challenge(factorId: 'factor-a');
      await f.started.future;
      await f.broadcastB();
      f.release.complete();
      final challenge = await pending;
      await transport.verify(
        factorId: 'factor-a',
        challengeId: challenge.id,
        code: '123456',
      );
      await _drainMessages();
      // The HTTP fake checks the exact original A bearer on BOTH POSTs.
      expect(f.steps, ['challenge', 'verify']);
      expect(f.main.auth.currentUser!.id, 'b');
      expect(f.peer.currentUser!.id, 'b');
      expect(
        f.events.where((e) => e.event == AuthChangeEvent.mfaChallengeVerified),
        isEmpty,
      );
    } finally {
      transport.dispose();
      await f.dispose();
    }
  });
}

const _url = 'https://offline.invalid';
const _key = 'synthetic-public-key';
Future<void> _drainMessages() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

class _TrackedHttp extends MockClient {
  int closeCount = 0;
  _TrackedHttp(super.fn);
  @override
  void close() {
    closeCount++;
    super.close();
  }
}

class _BrowserFixture {
  final String heldStage;
  final started = Completer<void>();
  final release = Completer<void>();
  final steps = <String>[];
  final events = <AuthState>[];
  final peerEvents = <AuthState>[];
  late final SupabaseClient main;
  late final GoTrueClient peer;
  late final _TrackedHttp transportHttp;
  late final SupabaseAuthService service;
  late final StreamSubscription<AuthState> subscription;
  late final StreamSubscription<AuthState> peerSubscription;
  _BrowserFixture(this.heldStage);

  static Future<_BrowserFixture> create(String stage) async {
    final f = _BrowserFixture(stage);
    f.transportHttp = _TrackedHttp(f.respond);
    f.main = SupabaseClient(
      _url,
      _key,
      httpClient: MockClient(f.respond),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    f.peer = GoTrueClient(
      url: '$_url/auth/v1',
      autoRefreshToken: false,
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          '$_url/auth/v1/token?grant_type=password',
        );
        expect(request.method, 'POST');
        expect(jsonDecode(request.body)['email'], 'b@offline.invalid');
        return http.Response(jsonEncode(_session('b', 'new')), 200);
      }),
    );
    f.subscription = f.main.auth.onAuthStateChange.listen(f.events.add);
    f.peerSubscription = f.peer.onAuthStateChange.listen(f.peerEvents.add);
    // Initial restoration is local; sign-in/refresh below exercise real broadcasts.
    await f.main.auth.setInitialSession(jsonEncode(_session('a', 'initial')));
    await f.peer.setInitialSession(jsonEncode(_session('a', 'initial')));
    await _drainMessages();
    f.events.clear();
    f.peerEvents.clear();
    f.service = SupabaseAuthService(
      client: f.main,
      mfaClientFactory: (token) => MfaVerificationClient(
        supabaseUrl: _url,
        publicKey: _key,
        accessToken: token,
        httpClient: f.transportHttp,
      ),
    );
    return f;
  }

  Future<void> broadcastB() async {
    // A missing/disabled BroadcastChannel must fail this regression, not pass it.
    final received = main.auth.onAuthStateChange
        .firstWhere((e) => e.session?.refreshToken == 'b-new-refresh')
        .timeout(const Duration(seconds: 5));
    await peer.signInWithPassword(
      email: 'b@offline.invalid',
      password: 'synthetic',
    );
    expect((await received).fromBroadcast, isTrue);
    expect(main.auth.currentUser!.id, 'b');
  }

  Future<AuthMFAVerifyResponse> verify() =>
      service.verifyTotp(factorId: 'factor-a', code: '123456');

  Future<http.Response> respond(http.Request request) async {
    expect(request.url.origin, _url);
    expect(request.method, 'POST');
    final stage = request.url.path.endsWith('/token')
        ? 'adopt'
        : request.url.pathSegments.last;
    expect(['challenge', 'verify', 'adopt'], contains(stage));
    steps.add(stage);
    if (stage == 'adopt') {
      expect(request.url.queryParameters, {'grant_type': 'refresh_token'});
      expect(jsonDecode(request.body), {'refresh_token': 'a-verified-refresh'});
    } else {
      expect(
        request.headers['authorization'],
        'Bearer ${_session('a', 'initial')['access_token']}',
      );
      expect(request.headers['apikey'], _key);
      expect(request.url.path, '/auth/v1/factors/factor-a/$stage');
    }
    if (stage == heldStage) {
      started.complete();
      await release.future;
    }
    return http.Response(
      jsonEncode(
        stage == 'challenge'
            ? {'id': 'challenge-a', 'expires_at': 4102444800}
            : _session(
                'a',
                stage == 'verify' ? 'verified' : 'adopted',
                aal: 'aal2',
              ),
      ),
      200,
    );
  }

  Future<void> dispose() async {
    await subscription.cancel();
    await peerSubscription.cancel();
    peer.dispose();
    await main.dispose();
  }
}

Map<String, dynamic> _session(
  String user,
  String label, {
  String aal = 'aal1',
}) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'none'})}.${encode({'sub': user, 'aal': aal, 'amr': [], 'exp': 4102444800, 'label': label})}.c3ludGhldGlj',
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
