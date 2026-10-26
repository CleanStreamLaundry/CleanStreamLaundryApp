import 'package:clean_stream_laundry_app/core/di/di.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'public policy factory uses only public configuration and no Auth transport',
    () async {
      final client = createPublicPolicyClient(
        supabaseUrl: 'http://127.0.0.1:1',
        publicKey: 'synthetic-public-key',
      );
      addTearDown(client.dispose);

      expect(client.url, 'http://127.0.0.1:1/rest/v1');
      expect(client.headers['apikey'], 'synthetic-public-key');
      expect(
        client.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(client.httpClient, isNull);
    },
  );
}
