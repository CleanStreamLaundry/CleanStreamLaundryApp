import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Request-scoped MFA transport: no Auth session, storage, or broadcast channel.
class MfaVerificationClient {
  final Uri _authUrl;
  final Map<String, String> _headers;
  final http.Client _http;

  MfaVerificationClient({
    required String supabaseUrl,
    required String publicKey,
    required String accessToken,
    http.Client? httpClient,
  }) : _authUrl = Uri.parse('$supabaseUrl/auth/v1'),
       _headers = Map.unmodifiable({
         'apikey': publicKey,
         'Authorization': 'Bearer $accessToken',
         'Content-Type': 'application/json',
         'X-Supabase-Api-Version': '2024-01-01',
       }),
       _http = httpClient ?? http.Client();

  Future<AuthMFAChallengeResponse> challenge({
    required String factorId,
  }) async =>
      AuthMFAChallengeResponse.fromJson(await _post(factorId, 'challenge', {}));

  Future<AuthMFAVerifyResponse> verify({
    required String factorId,
    required String challengeId,
    required String code,
  }) async => AuthMFAVerifyResponse.fromJson(
    await _post(factorId, 'verify', {
      'challenge_id': challengeId,
      'code': code,
    }),
  );

  Future<Map<String, dynamic>> _post(
    String factorId,
    String action,
    Map<String, dynamic> body,
  ) async {
    // Path segments encode the factor as one component, including '/' and '?'.
    final uri = _authUrl.replace(
      pathSegments: [..._authUrl.pathSegments, 'factors', factorId, action],
    );
    final http.Response response;
    try {
      response = await _http.post(
        uri,
        headers: _headers,
        body: jsonEncode(body),
      );
    } on Exception {
      // The server outcome is unknown. This transport never retries a POST.
      throw AuthRetryableFetchException(
        message: 'MFA request failed; outcome unknown.',
      );
    }
    if (response.statusCode >= 500) {
      throw AuthRetryableFetchException(
        message: 'MFA server request failed.',
        statusCode: response.statusCode.toString(),
      );
    }
    final bool success =
        response.statusCode >= 200 && response.statusCode < 300;
    final dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      if (success) {
        throw AuthRetryableFetchException(
          message: 'Invalid MFA response; outcome unknown.',
        );
      }
      throw AuthUnknownException(
        message: 'Failed to decode MFA error response.',
        originalError: const FormatException('Invalid MFA error response.'),
      );
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid MFA response.');
    }
    if (!success) {
      throw AuthApiException(
        (data['msg'] ??
                data['message'] ??
                data['error_description'] ??
                data['error'] ??
                'MFA request rejected.')
            .toString(),
        statusCode: response.statusCode.toString(),
        code: (data['code'] ?? data['error_code']) as String?,
      );
    }
    return data;
  }

  void dispose() => _http.close();
}
