import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  for (final signedIn in [false, true]) {
    test(
      'startup and lifecycle stay disconnected with signedIn=$signedIn',
      () async {
        SharedPreferences.setMockInitialValues({});
        final initialState = binding.lifecycleState;
        var socketClientAttempts = 0;
        var apiAttempts = 0;
        final transport = MockClient((request) async {
          apiAttempts++;
          throw StateError('Unexpected API request: ${request.url.path}');
        });

        // Block the IO transport used by WebSocket.connect, not only REST calls.
        await HttpOverrides.runZoned(
          () async {
            Supabase? sdk;
            try {
              sdk = await Supabase.initialize(
                url: 'https://offline.invalid',
                publishableKey: 'sb_publishable_local_lifecycle_fixture_only',
                httpClient: transport,
                debug: false,
                authOptions: const FlutterAuthClientOptions(
                  autoRefreshToken: false,
                  detectSessionInUri: false,
                  localStorage: EmptyLocalStorage(),
                ),
              );
              if (signedIn) {
                String encode(Map<String, Object> value) => base64Url
                    .encode(utf8.encode(jsonEncode(value)))
                    .replaceAll('=', '');
                await sdk.client.auth.setInitialSession(
                  jsonEncode({
                    'access_token':
                        '${encode({'alg': 'none', 'typ': 'JWT'})}.'
                        '${encode({'sub': 'fixture-user', 'exp': 4102444800})}.'
                        'U3ludGhldGljU2lnbmF0dXJl',
                    'refresh_token': 'fixture-refresh-never-used',
                    'token_type': 'bearer',
                    'expires_in': 3600,
                    'user': {
                      'id': 'fixture-user',
                      'aud': 'authenticated',
                      'app_metadata': <String, Object>{},
                      'user_metadata': <String, Object>{},
                      'created_at': '',
                    },
                  }),
                );
                expect(sdk.client.auth.currentUser?.id, 'fixture-user');
              }

              for (final state in [
                AppLifecycleState.resumed,
                AppLifecycleState.inactive,
                AppLifecycleState.hidden,
                AppLifecycleState.paused,
                AppLifecycleState.hidden,
                AppLifecycleState.inactive,
                AppLifecycleState.resumed,
                AppLifecycleState.inactive,
                AppLifecycleState.hidden,
                AppLifecycleState.paused,
                AppLifecycleState.detached,
                AppLifecycleState.resumed,
              ]) {
                binding.handleAppLifecycleStateChanged(state);
                await pumpEventQueue();
                expect(sdk.client.getChannels(), isEmpty, reason: state.name);
                expect(
                  sdk.client.realtime.isConnected,
                  isFalse,
                  reason: state.name,
                );
                expect(socketClientAttempts, 0, reason: state.name);
                expect(apiAttempts, 0, reason: state.name);
              }
            } finally {
              await sdk?.dispose();
              transport.close();
              if (initialState != null) {
                binding.handleAppLifecycleStateChanged(initialState);
              }
            }
          },
          createHttpClient: (_) {
            socketClientAttempts++;
            throw StateError('Unexpected socket HTTP client');
          },
        );
      },
    );
  }
}
