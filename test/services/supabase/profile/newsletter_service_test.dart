import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../features/newsletter/fixtures.dart';

class _Client extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

class _Functions extends Mock implements FunctionsClient {}

void main() {
  for (final event in ['same-object A-B-A', 'auth error', 'auth closed']) {
    test('service rejects $event independently of session identity', () async {
      final client = _Client();
      final auth = _Auth();
      final functions = _Functions();
      final session = sessionFixture();
      final events = StreamController<AuthState>.broadcast(sync: true);
      final pending = Completer<FunctionResponse>();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => auth.currentUser).thenReturn(session.user);
      when(() => auth.onAuthStateChange).thenAnswer((_) => events.stream);
      when(
        () => functions.invoke(
          'newsletter',
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
          body: {'action': 'status'},
        ),
      ).thenAnswer((_) => pending.future);
      final checked = expectLater(
        SupabaseProfileService(client: client).getNewsletterStatus(),
        throwsStateError,
      );
      if (event == 'same-object A-B-A') {
        events.add(
          AuthState(AuthChangeEvent.signedIn, sessionFixture(id: subjectB)),
        );
        events.add(AuthState(AuthChangeEvent.signedIn, session));
      } else if (event == 'auth error') {
        events.addError(StateError('synthetic auth failure'));
      } else {
        await events.close();
      }
      pending.complete(FunctionResponse(data: newsletterWire(), status: 200));
      await checked;
      expect(events.hasListener, isFalse);
      await events.close();
    });
  }
  for (final action in ['status', 'request', 'withdraw']) {
    late SupabaseClient client;
    late SupabaseProfileService service;
    late Session captured;
    late Future<http.Response> Function(http.Request) reply;
    late List<http.Request> requests;

    Future<NewsletterStatus> call() => switch (action) {
      'request' => service.requestNewsletter('synthetic-newsletter-v2'),
      'withdraw' => service.withdrawNewsletter(),
      _ => service.getNewsletterStatus(),
    };

    group(action, () {
      setUp(() async {
        requests = [];
        reply = (_) async => http.Response(
          jsonEncode(
            newsletterWire(
              state: action == 'request'
                  ? 'pending'
                  : action == 'withdraw'
                  ? 'unsubscribed'
                  : 'not_subscribed',
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
        client = SupabaseClient(
          'https://offline.invalid',
          'synthetic-public-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            expect(request.url.host, 'offline.invalid');
            expect(request.url.path, '/functions/v1/newsletter');
            final response = await reply(request);
            return http.Response.bytes(
              response.bodyBytes,
              response.statusCode,
              headers: response.headers,
              request: request,
            );
          }),
        );
        await client.auth.setInitialSession(
          jsonEncode(sessionFixture().toJson()),
        );
        captured = client.auth.currentSession!;
        service = SupabaseProfileService(client: client);
      });
      tearDown(() => client.dispose());

      test('real SDK sends exact captured bearer and contract once', () async {
        final status = await call();
        expect(status.subjectId, subjectA);
        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.method, 'POST');
        expect(
          request.headers['authorization'],
          'Bearer ${captured.accessToken}',
        );
        expect(
          jsonDecode(request.body),
          action == 'request'
              ? {
                  'action': 'request',
                  'opt_in': true,
                  'version': 'synthetic-newsletter-v2',
                  'source': 'settings',
                }
              : {'action': action},
        );
      });

      if (action == 'status') {
        for (final state in ['not_subscribed', 'subscribed']) {
          test('preserves Edge disabled status for $state', () async {
            reply = (_) async => http.Response(
              jsonEncode(newsletterWire(state: state, enabled: false)),
              200,
              headers: {'content-type': 'application/json'},
            );
            final status = await call();
            expect(status.enabled, isFalse);
            expect(status.subjectId, subjectA);
            expect(
              status.state,
              state == 'subscribed'
                  ? NewsletterState.subscribed
                  : NewsletterState.notSubscribed,
            );
            expect(requests, hasLength(1));
            expect(jsonDecode(requests.single.body), {'action': 'status'});
          });
        }
      }

      if (action == 'withdraw') {
        test('withdraws through Edge while newsletter is disabled', () async {
          reply = (_) async => http.Response(
            jsonEncode(
              newsletterWire(state: 'unsubscribed', enabled: false),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
          final status = await call();
          expect(status.enabled, isFalse);
          expect(status.state, NewsletterState.unsubscribed);
          expect(requests, hasLength(1));
          expect(jsonDecode(requests.single.body), {'action': 'withdraw'});
        });
      }

      for (final change in ['B', 'A-B-A']) {
        test('rejects late transport acknowledgement after $change', () async {
          reply = (request) async {
            expect(
              request.headers['authorization'],
              'Bearer ${captured.accessToken}',
            );
            await client.auth.setInitialSession(
              jsonEncode(sessionFixture(id: subjectB).toJson()),
            );
            if (change == 'A-B-A') {
              await client.auth.setInitialSession(
                jsonEncode(captured.toJson()),
              );
            }
            return http.Response(
              jsonEncode(newsletterWire()),
              200,
              headers: {'content-type': 'application/json'},
            );
          };
          await expectLater(call(), throwsStateError);
          expect(requests, hasLength(1));
        });
      }

      for (final wire in [
        null,
        newsletterWire(subject: subjectB),
        {...newsletterWire(), 'enabled': null},
      ]) {
        test('rejects malformed or wrong-subject response $wire', () async {
          reply = (_) async => http.Response(
            jsonEncode(wire),
            200,
            headers: {'content-type': 'application/json'},
          );
          await expectLater(call(), throwsFormatException);
          expect(requests, hasLength(1));
        });
      }

      for (final code in [400, 401, 403, 429, 503]) {
        test('preserves HTTP $code without business retry', () async {
          reply = (_) async => http.Response(
            '{"message":"synthetic unavailable","code":"PT$code"}',
            code,
            headers: {'content-type': 'application/json'},
          );
          await expectLater(call(), throwsA(isA<Exception>()));
          expect(requests, hasLength(1));
          expect(client.auth.currentUser?.id, subjectA);
        });
      }

      test('missing session rejects before transport', () async {
        // Local session removal needs no provider or logout HTTP call.
        await client.dispose();
        client = SupabaseClient(
          'https://offline.invalid',
          'synthetic-public-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient(
            (_) async => throw StateError('Unexpected HTTP'),
          ),
        );
        service = SupabaseProfileService(client: client);
        await expectLater(call(), throwsStateError);
        expect(requests, isEmpty);
      });

      for (final failure in [false, true]) {
        test(
          'timeout never retries and ignores late failure=$failure',
          () async {
            final pending = Completer<http.Response>();
            reply = (_) => pending.future;
            await expectLater(call(), throwsA(isA<TimeoutException>()));
            expect(requests, hasLength(1));
            if (failure) {
              pending.completeError(
                StateError('synthetic late transport error'),
              );
            } else {
              pending.complete(
                http.Response(
                  jsonEncode(newsletterWire()),
                  200,
                  headers: {'content-type': 'application/json'},
                ),
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
            expect(requests, hasLength(1));
          },
        );
      }
    });
  }
}
