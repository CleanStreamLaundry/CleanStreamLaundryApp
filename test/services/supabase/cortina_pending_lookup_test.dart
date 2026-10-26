import 'dart:convert';

import 'package:clean_stream_laundry_app/services/supabase/supabase_cortina_vend_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const origin = 'https://offline.invalid';
  const publicKey = 'sb_publishable_fixture';
  const requestId = '00000000-0000-4000-8000-000000000007';
  const sessionId = '00000000-0000-4000-8000-000000000008';
  late SupabaseClient client;
  late SupabaseCortinaVendService service;
  late MockClient transport;
  late List<http.Request> requests;
  late Object responseBody;
  late int responseCode;
  late bool throwTransport;

  String token(String user) {
    String encode(Map<String, Object> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${encode({'alg': 'none', 'typ': 'JWT'})}.'
        '${encode({'sub': user, 'role': 'authenticated', 'exp': 4102444800})}.fixture';
  }

  Future<void> signIn(String user) => client.auth.setInitialSession(jsonEncode({
    'access_token': token(user), 'refresh_token': 'unused-refresh',
    'token_type': 'bearer', 'expires_in': 3600,
    'user': {
      'id': user, 'aud': 'authenticated', 'created_at': '',
      'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{},
      'is_anonymous': false,
    },
  }));

  setUp(() {
    requests = []; responseCode = 200; throwTransport = false;
    responseBody = {'sessionId': sessionId, 'accessToken': requestId};
    transport = MockClient((request) async {
      requests.add(request);
      expect(request.method, 'POST');
      expect(request.url.toString(), '$origin/functions/v1/cortina-vend/status');
      expect(jsonDecode(request.body), {'clientRequestId': requestId, 'machineId': 7});
      expect(request.headers['apikey'], publicKey);
      if (throwTransport) throw StateError('offline');
      return http.Response(jsonEncode(responseBody), responseCode,
        headers: {'content-type': 'application/json'});
    });
    client = SupabaseClient(origin, publicKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: transport);
    service = SupabaseCortinaVendService(client: client);
  });

  tearDown(() async {
    expect(client.getChannels(), isEmpty);
    expect(client.realtime.isConnected, isFalse);
    await client.dispose(); transport.close();
  });

  test('owner lookup uses existing status URL and explicit human bearer only', () async {
    await signIn('owner');
    final reference = await service.recoverPendingPayment(clientRequestId: requestId, machineId: 7);
    expect(reference.sessionId, sessionId); expect(reference.accessToken, requestId);
    expect(requests, hasLength(1));
    expect(requests.single.headers['authorization'], 'Bearer ${token('owner')}');
    expect(requests.single.url.toString(), isNot(contains(requestId)));
  });

  test('no authenticated session means zero HTTP including no anonymous fallback', () async {
    await expectLater(service.recoverPendingPayment(clientRequestId: requestId, machineId: 7), throwsStateError);
    expect(requests, isEmpty);
  });

  for (final code in [400, 401, 403, 404, 503]) {
    test('lookup HTTP $code is an unresolved error, never an empty success', () async {
      await signIn('owner'); responseCode = code;
      responseBody = {'error': 'Payment recovery unavailable'};
      await expectLater(service.recoverPendingPayment(clientRequestId: requestId, machineId: 7), throwsStateError);
      expect(requests, hasLength(1));
    });
  }

  for (final response in [
    {'sessionId': '', 'accessToken': requestId},
    {'sessionId': sessionId, 'accessToken': 'different-capability'},
    {'accessToken': requestId},
  ]) {
    test('malformed recovered reference is not accepted: $response', () async {
      await signIn('owner'); responseBody = response;
      await expectLater(service.recoverPendingPayment(clientRequestId: requestId, machineId: 7), throwsA(anything));
      expect(requests, hasLength(1));
    });
  }

  test('transport failure is not retried by creating or confirming', () async {
    await signIn('owner'); throwTransport = true;
    await expectLater(
      service.recoverPendingPayment(clientRequestId: requestId, machineId: 7),
      throwsA(isA<FunctionsFetchException>()
        .having((error) => error.status, 'status', 0)
        .having((error) => error.details, 'details',
          isA<StateError>().having((error) => error.message, 'message', 'offline'))
        .having((error) => error.reasonPhrase, 'reasonPhrase', isNull)),
    );
    expect(requests, hasLength(1));
  });

  test('lookup captures original bearer before later account replacement', () async {
    await signIn('owner');
    final pending = service.recoverPendingPayment(clientRequestId: requestId, machineId: 7);
    await signIn('other');
    expect((await pending).sessionId, sessionId);
    expect(requests, hasLength(1));
    expect(requests.single.headers['authorization'], 'Bearer ${token('owner')}');
    expect(client.auth.currentUser?.id, 'other');
  });
}
