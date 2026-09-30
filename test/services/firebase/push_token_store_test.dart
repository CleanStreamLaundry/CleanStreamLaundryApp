import 'dart:convert';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:clean_stream_laundry_app/services/firebase/push_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late SupabasePushTokenStore tokens;
  final requests = <http.Request>[];
  var fail = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    requests.clear();
    fail = false;
    tokens = SupabasePushTokenStore(
      preferences: prefs,
      environment: 'dev',
      platform: 'ios',
      client: PostgrestClient(
        'https://mock.invalid/rest/v1',
        headers: {'apikey': 'public'},
        httpClient: MockClient((request) async {
          requests.add(request);
          final rejected =
              fail && !request.url.path.endsWith('prepare_push_installation');
          return http.Response(
            rejected ? '{"code":"PT503","message":"offline"}' : '',
            rejected ? 503 : 204,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
  });
  test('bind uses explicit captured bearer and no user-id payload', () async {
    await tokens.bind(
      const PushAccount('A', 'Bearer captured-A'),
      'test-token',
    );
    expect(requests.last.headers['Authorization'], 'Bearer captured-A');
    final body = jsonDecode(requests.last.body) as Map;
    expect(
      body.keys,
      unorderedEquals([
        'p_installation',
        'p_secret',
        'p_environment',
        'p_platform',
        'p_token',
      ]),
    );
    expect(body['p_environment'], 'dev');
    expect(body['p_platform'], 'ios');
    expect(prefs.getBool('firebase.dev.push.pending'), isTrue);
  });
  test(
    'revoke uses capability without stale auth and rotates installation',
    () async {
      await tokens.bind(const PushAccount('A', 'Bearer captured-A'), 'token-A');
      final first = jsonDecode(requests.first.body)['p_installation'];
      await tokens.revoke();
      expect(requests.last.headers['Authorization'], isNull);
      expect(jsonDecode(requests.last.body)['p_installation'], first);
      await tokens.bind(const PushAccount('B', 'Bearer captured-B'), 'token-B');
      expect(jsonDecode(requests.last.body)['p_installation'], isNot(first));
    },
  );
  test(
    'failed register persists cleanup capability; failed revoke retains it',
    () async {
      fail = true;
      await expectLater(
        tokens.bind(const PushAccount('A', 'Bearer A'), 'token'),
        throwsA(isA<PostgrestException>()),
      );
      final secret = prefs.getString('firebase.dev.push.secret');
      await expectLater(tokens.revoke(), throwsA(isA<PostgrestException>()));
      expect(prefs.getBool('firebase.dev.push.pending'), isTrue);
      expect(prefs.getString('firebase.dev.push.secret'), secret);
      fail = false;
      await tokens.revoke();
      expect(prefs.getBool('firebase.dev.push.pending'), isFalse);
    },
  );
  test('no recorded installation means no network cleanup', () async {
    await tokens.revoke();
    expect(requests, isEmpty);
  });
}
