import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/services/supabase/mfa_verification_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('encodes factor as one path segment and sends exact TOTP wire', () async {
    final requests = <http.Request>[];
    final client = _client(
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'id': 'challenge', 'expires_at': 4102444800}),
          200,
        );
      }),
    );
    try {
      await client.challenge(factorId: 'factor/with ?#%');
      // Intentionally return a challenge-shaped response to inspect verify wire only.
      await expectLater(
        client.verify(
          factorId: 'factor/with ?#%',
          challengeId: 'challenge',
          code: '012345',
        ),
        throwsFormatException,
      );
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(request.url.pathSegments, [
          'auth',
          'v1',
          'factors',
          'factor/with ?#%',
          request == requests.first ? 'challenge' : 'verify',
        ]);
        expect(request.url.query, isEmpty);
        expect(request.url.fragment, isEmpty);
        expect(request.headers['authorization'], 'Bearer captured-token');
        expect(request.headers['apikey'], 'public-key');
        expect(request.headers['content-type'], contains('application/json'));
        expect(request.headers['x-supabase-api-version'], '2024-01-01');
      }
      expect(jsonDecode(requests.first.body), <String, dynamic>{});
      expect(jsonDecode(requests.last.body), {
        'challenge_id': 'challenge',
        'code': '012345',
      });
    } finally {
      client.dispose();
    }
  });

  for (final key in ['code', 'error_code']) {
    test('preserves provider status and $key without retry', () async {
      var calls = 0;
      final client = _client(
        MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({'message': 'Rejected', key: 'mfa_verification_failed'}),
            422,
          );
        }),
      );
      try {
        await expectLater(
          client.challenge(factorId: 'factor'),
          throwsA(
            isA<AuthApiException>()
                .having((e) => e.code, 'code', 'mfa_verification_failed')
                .having((e) => e.statusCode, 'status', '422')
                .having((e) => e.message, 'message', 'Rejected'),
          ),
        );
        expect(calls, 1);
      } finally {
        client.dispose();
      }
    });
  }

  for (final failure in ['network', 'timeout', 'server']) {
    test('$failure leaves outcome unknown with no automatic retry', () async {
      var calls = 0;
      final client = _client(
        MockClient((_) async {
          calls++;
          if (failure == 'network') throw http.ClientException('synthetic');
          if (failure == 'timeout') throw TimeoutException('synthetic');
          return http.Response('synthetic', 503);
        }),
      );
      try {
        await expectLater(
          client.challenge(factorId: 'factor'),
          throwsA(isA<AuthRetryableFetchException>()),
        );
        expect(calls, 1);
      } finally {
        client.dispose();
      }
    });
  }
}

MfaVerificationClient _client(http.Client httpClient) => MfaVerificationClient(
  supabaseUrl: 'https://offline.invalid',
  publicKey: 'public-key',
  accessToken: 'captured-token',
  httpClient: httpClient,
);
