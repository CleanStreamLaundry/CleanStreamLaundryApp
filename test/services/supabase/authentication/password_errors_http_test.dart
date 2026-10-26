import 'dart:convert';

import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('existing password login succeeds with a weak_password advisory', () async {
    final requests = <http.Request>[];
    final client = _client(MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode({
        ..._session(),
        'weak_password': {
          'message': 'private-provider-detail',
          'reasons': ['pwned'],
        },
      }), 200);
    }));
    addTearDown(client.dispose);
    final service = SupabaseAuthService(client: client);

    // Existing-password login must not apply signup strength requirements.
    expect(await service.login('user@example.com', 'old'),
        AuthenticationResponses.success);
    expect(client.auth.currentUser?.id, 'synthetic-user');
    expect(client.auth.currentSession, isNotNull);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/auth/v1/token');
    expect(requests.single.url.queryParameters, {'grant_type': 'password'});
    expect(jsonDecode(requests.single.body)['password'], 'old');
  });

  for (final operation in ['signup', 'update']) {
    for (final reasons in <List<String>>[
      ['pwned'], ['length'], [], ['future-reason'],
    ]) {
      test('$operation maps weak_password reasons $reasons without retry', () async {
        final requests = <http.Request>[];
        final client = _client(MockClient((request) async {
          requests.add(request);
          if (operation == 'update' && request.url.path == '/auth/v1/token') {
            return http.Response(jsonEncode(_session()), 200);
          }
          return http.Response(jsonEncode({
            'code': 'weak_password',
            'message': 'private-provider-detail',
            'weak_password': {'reasons': reasons},
          }), 422, headers: {'x-supabase-api-version': '2024-01-01'});
        }));
        addTearDown(client.dispose);
        final service = SupabaseAuthService(client: client);
        if (operation == 'update') {
          expect(await service.login('user@example.com', 'old'),
              AuthenticationResponses.success);
          requests.clear();
        }
        final before = client.auth.currentSession;
        final result = operation == 'signup'
            ? await service.signUp('user@example.com', ' StrongPass1! ', 'Name')
            : await service.updatePassword(' StrongPass1! ');

        expect(result, reasons.contains('pwned')
            ? AuthenticationResponses.compromisedPassword
            : AuthenticationResponses.weakPassword);
        expect(client.auth.currentSession, same(before));
        expect(service.lastSignedUpUserId, isNull);
        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.method, operation == 'signup' ? 'POST' : 'PUT');
        expect(request.url.path, operation == 'signup' ? '/auth/v1/signup' : '/auth/v1/user');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['password'], operation == 'signup' ? ' StrongPass1! ' : 'StrongPass1!');
        if (operation == 'signup') {
          expect(body['email'], 'user@example.com');
          expect(body['data'], {'full_name': 'Name'});
        } else {
          expect(request.headers['authorization'], 'Bearer ${before!.accessToken}');
        }
      });
    }
  }
}

SupabaseClient _client(http.Client httpClient) => SupabaseClient(
  'https://offline.invalid',
  'synthetic-public-key',
  httpClient: httpClient,
  authOptions: AuthClientOptions(
    autoRefreshToken: false,
    pkceAsyncStorage: _MemoryPkceStorage(),
  ),
);

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

Map<String, dynamic> _session() {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final token = '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'sub': 'synthetic-user', 'exp': expiry})}.synthetic';
  return {
    'access_token': token,
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': 'synthetic-user',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'user@example.com',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
}
