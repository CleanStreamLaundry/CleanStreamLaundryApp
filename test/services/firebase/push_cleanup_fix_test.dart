import 'dart:convert';

import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:clean_stream_laundry_app/services/firebase/push_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FailingPreferences extends Mock implements SharedPreferences {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'firebase.dev.push.';
  late SharedPreferences prefs;
  final requests = <http.Request>[];
  var failRevoke = false;
  late PostgrestClient client;
  SupabasePushTokenStore store() => SupabasePushTokenStore(
    client: client,
    preferences: prefs,
    environment: 'dev',
    platform: 'ios',
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    requests.clear();
    failRevoke = false;
    client = PostgrestClient(
      'https://mock.invalid/rest/v1',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('prepare_push_installation')) {
          expect(
            prefs.getBool('${key}pending'),
            isTrue,
            reason: 'Cleanup must be durable before the first server mutation',
          );
        }
        final fail =
            failRevoke && request.url.path.endsWith('revoke_push_installation');
        return http.Response(
          fail ? '{"code":"PT503","message":"lost response"}' : '',
          fail ? 503 : 204,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  test(
    'failed durable pending write dispatches neither prepare nor register',
    () async {
      final failing = FailingPreferences();
      when(
        () => failing.getString('${key}installation'),
      ).thenReturn('installation');
      when(() => failing.getString('${key}secret')).thenReturn('secret');
      when(() => failing.getBool('${key}retired')).thenReturn(false);
      when(
        () => failing.setBool('${key}pending', true),
      ).thenAnswer((_) async => false);
      prefs = failing;
      await expectLater(
        store().bind(const PushAccount('A', 'Bearer A'), 'token'),
        throwsStateError,
      );
      expect(requests, isEmpty);
    },
  );

  test(
    'uncertain revoke retains capability and retries anonymously after restart',
    () async {
      await store().bind(const PushAccount('A', 'Bearer A'), 'token-A');
      final installation = prefs.getString('${key}installation');
      final secret = prefs.getString('${key}secret');
      failRevoke = true;
      await expectLater(store().revoke(), throwsA(isA<PostgrestException>()));
      expect(prefs.getBool('${key}pending'), isTrue);
      expect(prefs.getString('${key}installation'), installation);
      expect(prefs.getString('${key}secret'), secret);
      failRevoke = false;
      await store().revoke();
      expect(requests.last.headers['Authorization'], isNull);
      expect(jsonDecode(requests.last.body)['p_installation'], installation);
      await store().bind(const PushAccount('B', 'Bearer B'), 'token-B');
      expect(prefs.getString('${key}installation'), isNot(installation));
      expect(prefs.getString('${key}secret'), isNot(secret));
    },
  );

  for (final window in [
    'acknowledged',
    'installation-removed',
    'both-removed',
    'pending-cleared',
  ]) {
    test(
      'restart completes terminal capability rotation after $window',
      () async {
        SharedPreferences.setMockInitialValues({
          '${key}retired': true,
          '${key}pending': window != 'pending-cleared',
          if (window == 'acknowledged')
            '${key}installation': 'old-installation',
          if (window == 'acknowledged' || window == 'installation-removed')
            '${key}secret': 'old-secret',
        });
        prefs = await SharedPreferences.getInstance();
        await store().bind(const PushAccount('B', 'Bearer B'), 'token-B');
        expect(requests.length, 2);
        expect(
          prefs.getString('${key}installation'),
          isNot('old-installation'),
        );
        expect(prefs.getString('${key}secret'), isNot('old-secret'));
        expect(prefs.getBool('${key}retired'), isNull);
        expect(prefs.getBool('${key}pending'), isTrue);
      },
    );
  }

  test(
    'legacy unmarked prepare capability is cleaned before rotation',
    () async {
      await prefs.setString('${key}installation', 'old-installation');
      await prefs.setString('${key}secret', 'old-secret');
      await store().revoke();
      expect(requests.single.url.path, endsWith('revoke_push_installation'));
      expect(requests.single.headers['Authorization'], isNull);
      expect(prefs.getString('${key}installation'), isNull);
      expect(prefs.getString('${key}secret'), isNull);
    },
  );
}
