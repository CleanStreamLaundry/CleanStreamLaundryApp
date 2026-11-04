import 'dart:convert';
import 'dart:typed_data';

import 'package:clean_stream_laundry_app/core/config/client_configuration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late DotEnv environment;
  var assetReads = 0;
  const betaUrl = 'https://dnuuhupoxjtwqzaqylvb.supabase.co';
  const betaKey = 'sb_publishable_synthetic';
  const stripeKey = 'pk_test_synthetic';

  setUp(() {
    environment = DotEnv();
    assetReads = 0;
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      assetReads++;
      expect(utf8.decode(message!.buffer.asUint8List()), '.env');
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(
            'SUPABASE_URL=https://local.synthetic.invalid\nANON_KEY=local-public\nSTRIPE_PUBLISHABLE_KEY=pk_live_local\n',
          ),
        ),
      );
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });

  Future<void> load({
    String channel = 'testflight',
    String url = betaUrl,
    String key = betaKey,
    String stripe = stripeKey,
  }) => initializeClientConfiguration(
    target: environment,
    channel: channel,
    supabaseUrl: url,
    publicKey: key,
    stripeKey: stripe,
  );

  test(
    'selected public settings initialize the existing dotenv contract',
    () async {
      await load();
      expect(environment.isInitialized, isTrue);
      expect(environment.env, {
        'SUPABASE_URL': betaUrl,
        'ANON_KEY': betaKey,
        'STRIPE_PUBLISHABLE_KEY': stripeKey,
      });
      expect(assetReads, 0);
    },
  );

  for (final channel in [
    'testflight',
    'play-internal',
    'production-ios',
    'production-android',
  ]) {
    test(
      '$channel replaces stale dotenv state without loading the bundled asset',
      () async {
        environment.loadFromString(
          envString: 'STALE=present\nSTRIPE_PUBLISHABLE_KEY=pk_live_old',
        );
        final live = channel.startsWith('production-');
        final url = live ? 'https://production.synthetic.invalid' : betaUrl;
        final stripe = live ? 'pk_live_synthetic' : stripeKey;
        await load(channel: channel, url: url, stripe: stripe);
        expect(environment.env, {
          'SUPABASE_URL': url,
          'ANON_KEY': betaKey,
          'STRIPE_PUBLISHABLE_KEY': stripe,
        });
        expect(assetReads, 0);
      },
    );
  }

  test(
    'ordinary local development retains the real dotenv asset loader',
    () async {
      await load(channel: '', url: '', key: '', stripe: '');
      expect(
        environment.env['SUPABASE_URL'],
        'https://local.synthetic.invalid',
      );
      expect(environment.env['STRIPE_PUBLISHABLE_KEY'], 'pk_live_local');
      expect(assetReads, 1);
    },
  );

  for (final missing in ['channel', 'url', 'key', 'stripe']) {
    test(
      'missing $missing fails closed instead of using local settings',
      () async {
        environment.loadFromString(envString: 'STALE=present');
        await expectLater(
          load(
            channel: missing == 'channel' ? '' : 'testflight',
            url: missing == 'url' ? '' : betaUrl,
            key: missing == 'key' ? '' : betaKey,
            stripe: missing == 'stripe' ? '' : stripeKey,
          ),
          throwsStateError,
        );
        expect(environment.isInitialized, isFalse);
        expect(assetReads, 0);
      },
    );
  }

  test(
    'beta rejects a live Stripe key and production rejects a test key',
    () async {
      await expectLater(load(stripe: 'pk_live_synthetic'), throwsStateError);
      await expectLater(load(channel: 'production-ios'), throwsStateError);
    },
  );
  test('unknown distribution channel cannot fall back', () async {
    await expectLater(load(channel: 'unknown'), throwsStateError);
  });
  for (final url in [
    'http://example.invalid',
    'https://other.supabase.co',
    'https://user:password@example.invalid',
    '$betaUrl?override=yes',
  ]) {
    test('beta refuses mismatched or malformed backend $url', () async {
      await expectLater(load(url: url), throwsStateError);
      expect(assetReads, 0);
    });
  }
  test('only legacy anon JWTs remain compatible', () async {
    String jwt(String role) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role}))).replaceAll('=', '')}.signature';
    await load(key: jwt('anon'));
    expect(environment.env['ANON_KEY'], jwt('anon'));
    await expectLater(load(key: jwt('service_role')), throwsStateError);
    await expectLater(load(key: 'sb_secret_synthetic'), throwsStateError);
  });
}
