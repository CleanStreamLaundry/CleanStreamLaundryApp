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
  test(
    'REGRESSION: committed preparation with lost response is cleanable before another account opts in',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final slots = <String, String>{};
      final revoked = <String>{};
      final routes = <String>[];
      var losePrepareResponse = true;
      final client = PostgrestClient(
        'https://mock.invalid/rest/v1',
        headers: {'apikey': 'public'},
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          final id = body['p_installation'] as String;
          final actor = request.headers['Authorization'] ?? 'anon';
          routes.add(request.url.path.split('/').last);
          if (request.url.path.endsWith('revoke_push_installation')) {
            revoked.add(id);
          } else if (request.url.path.endsWith('prepare_push_installation')) {
            slots.putIfAbsent(id, () => actor);
            if (losePrepareResponse) {
              losePrepareResponse = false;
              return http.Response(
                '{"code":"PT503","message":"response lost after commit"}',
                503,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            if (slots[id] != actor || revoked.contains(id)) {
              return http.Response(
                '{"code":"PT403","message":"account_restricted"}',
                403,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
          }
          return http.Response('', 204, request: request);
        }),
      );
      SupabasePushTokenStore store() => SupabasePushTokenStore(
        client: client,
        preferences: prefs,
        environment: 'dev',
        platform: 'ios',
      );
      final tokens = store();
      await expectLater(
        tokens.bind(const PushAccount('A', 'Bearer A'), 'test-token-A'),
        throwsA(isA<PostgrestException>()),
      );
      final afterRestart = store();
      await afterRestart.revoke();
      expect(
        routes,
        contains('revoke_push_installation'),
        reason:
            'Prepare is a committed mutation even when its response is lost. Its capability must remain eligible for cleanup.',
      );
      await afterRestart.bind(
        const PushAccount('B', 'Bearer B'),
        'test-token-B',
      );
      expect(slots.length, 2);
    },
  );

  test(
    'token capability and pending cleanup remain scoped to Firebase environment',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final requests = <http.Request>[];
      final client = PostgrestClient(
        'https://mock.invalid/rest/v1',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('', 204, request: request);
        }),
      );
      SupabasePushTokenStore store(String environment) =>
          SupabasePushTokenStore(
            client: client,
            preferences: prefs,
            environment: environment,
            platform: 'android',
          );
      await store('dev').bind(const PushAccount('A', 'Bearer A'), 'dev-token');
      final devInstallation = prefs.getString('firebase.dev.push.installation');
      await store('prod').revoke();
      expect(requests.length, 2);
      await store(
        'prod',
      ).bind(const PushAccount('A', 'Bearer A'), 'prod-token');
      expect(
        prefs.getString('firebase.prod.push.installation'),
        isNot(devInstallation),
      );
      await store('prod').revoke();
      expect(prefs.getBool('firebase.dev.push.pending'), isTrue);
      expect(requests.last.headers['Authorization'], isNull);
    },
  );
}
