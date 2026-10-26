import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mocks.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final provider in [OAuthProvider.google, OAuthProvider.apple]) {
      if (!kIsWeb &&
          ((provider == OAuthProvider.google &&
                  platform != TargetPlatform.macOS) ||
              (provider == OAuthProvider.apple &&
                  platform != TargetPlatform.android))) {
        continue;
      }
      test('$provider redirect on $platform, web=$kIsWeb', () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final client = SupabaseMock();
        final auth = GoTrueMock();
        when(() => client.auth).thenReturn(auth);
        final stopBeforeLaunch = StateError('Mocked OAuth URL boundary');
        String? redirect;
        when(
          () => auth.getOAuthSignInUrl(
            provider: provider,
            redirectTo: any(named: 'redirectTo'),
          ),
        ).thenAnswer((invocation) {
          redirect = invocation.namedArguments[#redirectTo] as String;
          throw stopBeforeLaunch;
        });
        final service = SupabaseAuthService(client: client);
        final result = provider == OAuthProvider.google
            ? service.googleSignIn()
            : service.appleSignIn();
        await expectLater(result, throwsA(same(stopBeforeLaunch)));
        final expected = kIsWeb
            ? Uri.parse(
                Uri.base.origin,
              ).replace(path: Uri.base.path, fragment: '/loading').toString()
            : 'clean-stream://oauth';
        expect(redirect, expected);
        verify(
          () =>
              auth.getOAuthSignInUrl(provider: provider, redirectTo: expected),
        ).called(1);
      });
    }
  }
}
