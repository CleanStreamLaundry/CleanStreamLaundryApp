import 'dart:convert';

import 'package:clean_stream_laundry_app/core/di/di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const origin = 'https://offline.invalid';
  const publicKey = 'sb_publishable_local_transport_fixture_only';
  const restPath = '/rest/v1/fixture_items';
  const rpcPath = '/rest/v1/rpc/fixture_read';
  const storagePath = '/storage/v1/object/fixture-bucket/fixture.txt';
  const edgePath = '/functions/v1/fixture-read';
  final requests = <http.Request>[];
  late MockClient transport;
  late SupabaseClient client;
  late String accessToken;

  setUp(() {
    String encode(Map<String, dynamic> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    accessToken = '${encode({'alg': 'none', 'typ': 'JWT'})}.'
        '${encode({'sub': 'fixture-user', 'role': 'authenticated', 'exp': 4102444800})}.'
        'U3ludGhldGljU2lnbmF0dXJl';
    requests.clear();
    // Reuse the MockClient wire-test pattern from mfa_http_test; all replies
    // are in memory, and every unexpected route (including Auth) is rejected.
    transport = MockClient((request) async {
      requests.add(request);
      expect(request.url.origin, origin);
      expect(request.url.fragment, isEmpty);
      switch (request.url.path) {
        case restPath:
          expect(request.method, 'GET');
          expect(request.url.queryParameters, {'select': 'id', 'id': 'eq.7'});
          return http.Response('[{"id":7}]', 200,
              request: request,
              headers: {'content-type': 'application/json'});
        case rpcPath:
          expect(request.method, 'POST');
          expect(request.url.query, isEmpty);
          expect(jsonDecode(request.body), {'p_id': 7});
          return http.Response('7', 200,
              request: request,
              headers: {'content-type': 'application/json'});
        case storagePath:
          expect(request.method, 'GET');
          expect(request.url.query, isEmpty);
          return http.Response.bytes(utf8.encode('fixture download'), 200,
              headers: {'content-type': 'application/octet-stream'});
        case edgePath:
          expect(request.method, 'POST');
          expect(request.url.query, isEmpty);
          expect(jsonDecode(request.body), {'id': 7});
          return http.Response('{"ok":true}', 200,
              headers: {'content-type': 'application/json'});
        default:
          throw StateError('Unexpected fixture HTTP path: ${request.url.path}');
      }
    });
    client = SupabaseClient(
      origin,
      publicKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: transport,
    );
  });
  tearDown(() async {
    try {
      expect(client.getChannels(), isEmpty);
      expect(client.realtime.isConnected, isFalse);
      expect(requests.any((request) => request.url.path.startsWith('/auth/')), isFalse);
    } finally {
      await client.dispose();
      transport.close();
    }
  });

  Future<void> seedSession() async {
    // SDK in-memory fixture hydration only: no sign-in, refresh, sign-out,
    // persistent auth storage or remote Auth mutation.
    await client.auth.setInitialSession(jsonEncode({
      'access_token': accessToken,
      'refresh_token': 'fixture-refresh-never-used',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': 'fixture-user',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '',
      },
    }));
    expect(client.auth.currentSession!.accessToken, accessToken);
    expect(requests, isEmpty);
  }

  Future<void> exercise(String path) async {
    switch (path) {
      case restPath:
        expect(await client.from('fixture_items').select('id').eq('id', 7), [
          {'id': 7},
        ]);
      case rpcPath:
        expect(await client.rpc('fixture_read', params: {'p_id': 7}), 7);
      case storagePath:
        final bytes = await client.storage.from('fixture-bucket').download('fixture.txt');
        expect(utf8.decode(bytes), 'fixture download');
      case edgePath:
        final response = await client.functions.invoke('fixture-read', body: {'id': 7});
        expect(response.status, 200);
        expect(response.data, {'ok': true});
    }
  }

  void expectWire(List<String> paths, String? bearer) {
    expect(requests.map((request) => request.url.path), paths);
    for (final request in requests) {
      final headers = request.headers.map((key, value) => MapEntry(key.toLowerCase(), value));
      expect(headers['apikey'], publicKey);
      expect(headers['authorization'], bearer);
      if (bearer == null) expect(headers.containsKey('authorization'), isFalse);
      expect(request.url.toString(), isNot(contains(publicKey)));
      expect(request.url.toString(), isNot(contains(accessToken)));
    }
  }

  for (final path in [restPath, rpcPath, storagePath, edgePath]) {
    test('publishable apikey plus exact signed-in bearer on $path', () async {
      await seedSession();
      final session = client.auth.currentSession;
      await exercise(path);
      expectWire([path], 'Bearer $accessToken');
      expect(client.auth.currentSession, same(session));
      expect(client.auth.currentSession!.refreshToken, 'fixture-refresh-never-used');
    });
  }

  test('signed-out SDK REST/RPC preserve publishable-key fallback bearer', () async {
    await exercise(restPath);
    await exercise(rpcPath);
    expectWire([restPath, rpcPath], 'Bearer $publicKey');
    expect(client.auth.currentSession, isNull);
  });

  test('signed-out SDK Storage download preserves publishable-key fallback bearer', () async {
    await exercise(storagePath);
    expectWire([storagePath], 'Bearer $publicKey');
    expect(client.auth.currentSession, isNull);
  });

  test('signed-out SDK Edge invocation omits publishable key as bearer', () async {
    await exercise(edgePath);
    expectWire([edgePath], null);
    expect(client.auth.currentSession, isNull);
  });

  test('actual public-policy factory sends apikey only despite a signed-in SDK client', () async {
    await seedSession();
    final session = client.auth.currentSession;
    // Intercept the factory's standard http.Client via package:http's supported
    // client zone, without replacing the factory or adding a runtime test seam.
    await http.runWithClient(() async {
      final public = createPublicPolicyClient(supabaseUrl: origin, publicKey: publicKey);
      try {
        expect(await public.from('fixture_items').select('id').eq('id', 7), [
          {'id': 7},
        ]);
        expect(await public.rpc('fixture_read', params: {'p_id': 7}), 7);
      } finally {
        await public.dispose();
      }
    }, () => transport);
    expectWire([restPath, rpcPath], null);
    expect(client.auth.currentSession, same(session));
  });
}
