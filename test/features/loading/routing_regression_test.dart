import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clean_stream_laundry_app/features/loading/controller.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mocks.dart';

class MockProfileService extends Mock implements ProfileService {}

void main() {
  late MockAuthService auth;
  late MockAppLinks links;
  late LoadingPageController controller;
  late List<String> routes;
  late List<Object?> extras;
  late bool mounted;

  Future<void> start() => controller.init(
    navigate: (route, {extra}) {
      routes.add(route);
      extras.add(extra);
    },
    isMounted: () => mounted,
  );

  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(const Stream<List<int>>.empty());
  });
  setUp(() {
    auth = MockAuthService();
    links = MockAppLinks();
    when(() => links.getInitialLink()).thenAnswer((_) async => null);
    when(
      () => auth.isLoggedIn(),
    ).thenAnswer((_) async => AuthenticationResponses.failure);
    when(() => auth.getSessionFromURI(any())).thenAnswer((_) async {});
    when(() => auth.refreshSession()).thenAnswer((_) async {});
    when(() => auth.onAuthChange).thenAnswer((_) => const Stream.empty());
    when(() => auth.getCurrentUser()).thenReturn(_user('A'));
    final profile = MockProfileService();
    when(
      () => profile.createAccount(
        id: any(named: 'id'),
        name: any(named: 'name'),
      ),
    ).thenAnswer((_) async {});
    controller = LoadingPageController(
      authService: auth,
      appLinks: links,
      profileService: profile,
    );
    routes = [];
    extras = [];
    mounted = true;
  });

  test('waits for a delayed cold link before checking normal login', () async {
    final initial = Completer<Uri?>();
    when(() => links.getInitialLink()).thenAnswer((_) => initial.future);
    final pending = start();
    await Future<void>.delayed(Duration.zero);
    final prematureRoutes = List<String>.of(routes);
    initial.complete(
      Uri.parse('clean-stream://reset-protected?code=a%2Bb#token=x'),
    );
    await pending;
    expect(prematureRoutes, isEmpty);
    expect(routes, ['/reset-protected?code=a%2Bb#token=x']);
    expect(
      extras.single,
      Uri.parse('clean-stream://reset-protected?code=a%2Bb#token=x'),
    );
    verifyNever(() => auth.isLoggedIn());
  });

  for (final response in AuthenticationResponses.values) {
    test(
      'normal entry uses only the existing auth result: $response',
      () async {
        when(() => auth.isLoggedIn()).thenAnswer((_) async => response);
        await start();
        expect(routes, [
          response == AuthenticationResponses.success ? '/homePage' : '/login',
        ]);
        verify(() => auth.isLoggedIn()).called(1);
      },
    );
  }

  for (final host in ['reset-protected', 'email-verification']) {
    test(
      '$host keeps query, fragment and destination without auto-login',
      () async {
        final uri = Uri.parse(
          'clean-stream://$host?code=a%2Bb&x=1&x=2#access_token=fake%2Ftoken',
        );
        when(() => links.getInitialLink()).thenAnswer((_) async => uri);
        when(
          () => auth.isLoggedIn(),
        ).thenAnswer((_) async => AuthenticationResponses.success);
        await start();
        expect(routes, ['/$host?${uri.query}#${uri.fragment}']);
        verifyNever(() => auth.isLoggedIn());
        verify(() => auth.getSessionFromURI(uri)).called(1);
      },
    );
  }

  for (final response in [
    AuthenticationResponses.success,
    AuthenticationResponses.failure,
  ]) {
    test(
      'change-email checks session before profile navigation: $response',
      () async {
        final uri = Uri.parse(
          'clean-stream://change-email?type=email_change&code=abc#token=fake',
        );
        when(() => links.getInitialLink()).thenAnswer((_) async => uri);
        when(() => auth.isLoggedIn()).thenAnswer((_) async => response);
        await start();
        expect(routes, [
          response == AuthenticationResponses.success
              ? '/editProfile?${uri.query}#${uri.fragment}'
              : '/login',
        ]);
        verify(() => auth.isLoggedIn()).called(1);
      },
    );
  }

  for (final value in [
    'https://change-email',
    'https://oauth?code=abc',
    'clean-stream://oauth.evil?code=abc',
    'clean-stream://user@oauth?code=abc',
    'clean-stream://oauth:123?code=abc',
    'clean-stream://oauth/unexpected?code=abc',
    'clean-stream://change-email?type=recovery',
    'clean-stream://unknown',
  ]) {
    test('invalid external URI stays on normal entry: $value', () async {
      when(
        () => links.getInitialLink(),
      ).thenAnswer((_) async => Uri.parse(value));
      await start();
      expect(routes, ['/login']);
      verifyNever(() => auth.getSessionFromURI(any()));
    });
  }

  test(
    'OAuth waits for exchange before the one session check/navigation',
    () async {
      final uri = Uri.parse(
        'clean-stream://oauth?code=a%2Bb#provider_token=fake',
      );
      final exchange = Completer<void>();
      when(() => links.getInitialLink()).thenAnswer((_) async => uri);
      when(
        () => auth.getSessionFromURI(uri),
      ).thenAnswer((_) => exchange.future);
      when(
        () => auth.isLoggedIn(),
      ).thenAnswer((_) async => AuthenticationResponses.success);
      final pending = start();
      await Future<void>.delayed(Duration.zero);
      final prematureRoutes = List<String>.of(routes);
      exchange.complete();
      await pending;
      expect(prematureRoutes, isEmpty);
      expect(routes, ['/homePage']);
      verify(() => auth.getSessionFromURI(uri)).called(1);
      verify(() => auth.isLoggedIn()).called(1);
    },
  );

  test(
    'OAuth failure cannot use an unrelated existing session as success',
    () async {
      when(
        () => links.getInitialLink(),
      ).thenAnswer((_) async => Uri.parse('clean-stream://oauth?code=bad'));
      when(
        () => auth.getSessionFromURI(any()),
      ).thenThrow(Exception('bad callback'));
      when(
        () => auth.isLoggedIn(),
      ).thenAnswer((_) async => AuthenticationResponses.success);
      await start();
      expect(routes, ['/login']);
      expect(controller.error, isNull);
    },
  );

  for (final dispose in [false, true]) {
    for (final fails in [false, true]) {
      test(
        'pending auth after ${dispose ? 'dispose' : 'unmount'}, fails=$fails',
        () async {
          final session = Completer<AuthenticationResponses>();
          final checking = Completer<void>();
          when(() => auth.isLoggedIn()).thenAnswer((_) {
            checking.complete();
            return session.future;
          });
          final pending = start();
          await checking.future;
          if (dispose) {
            controller.disposeController();
            controller.dispose();
          } else {
            mounted = false;
          }
          if (fails) {
            session.completeError(Exception('late failure'));
          } else {
            session.complete(AuthenticationResponses.success);
          }
          await pending;
          expect(routes, isEmpty);
          expect(controller.error, isNull);
        },
      );
    }
  }

  test('unmount during OAuth session check prevents navigation', () async {
    final session = Completer<AuthenticationResponses>();
    when(
      () => links.getInitialLink(),
    ).thenAnswer((_) async => Uri.parse('clean-stream://oauth?code=abc'));
    when(() => auth.isLoggedIn()).thenAnswer((_) => session.future);
    final pending = start();
    await Future<void>.delayed(Duration.zero);
    mounted = false;
    session.complete(AuthenticationResponses.success);
    await pending;
    expect(routes, isEmpty);
  });

  test(
    'dispose during initial link read prevents exchange and navigation',
    () async {
      final initial = Completer<Uri?>();
      when(() => links.getInitialLink()).thenAnswer((_) => initial.future);
      final pending = start();
      controller.dispose();
      initial.complete(Uri.parse('clean-stream://oauth?code=abc'));
      await pending;
      expect(routes, isEmpty);
      verifyNever(() => auth.getSessionFromURI(any()));
    },
  );

  test('duplicate init shares one callback operation and navigation', () async {
    final exchange = Completer<void>();
    final uri = Uri.parse('clean-stream://oauth?code=duplicate');
    when(() => links.getInitialLink()).thenAnswer((_) async => uri);
    when(() => auth.getSessionFromURI(uri)).thenAnswer((_) => exchange.future);
    final first = start();
    final second = start();
    exchange.complete();
    await Future.wait([first, second]);
    expect(routes, ['/login']);
    verify(() => links.getInitialLink()).called(1);
    verify(() => auth.getSessionFromURI(uri)).called(1);
    verify(() => auth.isLoggedIn()).called(1);
  });

  for (final entry in <Map<String, dynamic>?, String>{
    {'full_name': 'Full Name', 'name': 'Name', 'given_name': 'Given'}:
        'Full Name',
    {'name': 'Name', 'given_name': 'Given'}: 'Name',
    {'given_name': 'Given'}: 'Given',
    null: '',
    {}: '',
    {'full_name': 42, 'name': ' ', 'given_name': 'Given'}: 'Given',
    {'full_name': [], 'name': false}: '',
  }.entries) {
    final metadata = entry.key;
    test('OAuth preserves profile metadata fallback: $metadata', () async {
      final profile = MockProfileService();
      final uri = Uri.parse('clean-stream://oauth?code=profile');
      controller = LoadingPageController(
        authService: auth,
        appLinks: links,
        profileService: profile,
      );
      when(() => links.getInitialLink()).thenAnswer((_) async => uri);
      when(
        () => auth.isLoggedIn(),
      ).thenAnswer((_) async => AuthenticationResponses.success);
      when(() => auth.getCurrentUser()).thenReturn(
        User(
          id: 'profile-id',
          appMetadata: {},
          userMetadata: metadata,
          aud: '',
          createdAt: '',
        ),
      );
      when(
        () => profile.createAccount(
          id: any(named: 'id'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async {});
      await start();
      expect(routes, ['/homePage']);
      verify(
        () => profile.createAccount(id: 'profile-id', name: entry.value),
      ).called(1);
      verify(() => auth.getSessionFromURI(uri)).called(1);
    });
  }

  for (final disposed in [false, true]) {
    test('delayed profile failure is contained, disposed=$disposed', () async {
      final profile = MockProfileService();
      final saving = Completer<void>();
      final started = Completer<void>();
      controller = LoadingPageController(
        authService: auth,
        appLinks: links,
        profileService: profile,
      );
      when(
        () => links.getInitialLink(),
      ).thenAnswer((_) async => Uri.parse('clean-stream://oauth?code=profile'));
      when(
        () => auth.isLoggedIn(),
      ).thenAnswer((_) async => AuthenticationResponses.success);
      when(() => auth.getCurrentUser()).thenReturn(
        User(
          id: 'profile-id',
          appMetadata: {},
          userMetadata: {'name': 'Name'},
          aud: '',
          createdAt: '',
        ),
      );
      when(
        () => profile.createAccount(
          id: any(named: 'id'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) {
        started.complete();
        return saving.future;
      });
      final pending = start();
      await started.future;
      expect(routes, isEmpty);
      if (disposed) controller.dispose();
      saving.completeError(Exception('profile failure'));
      await pending;
      expect(routes, disposed ? isEmpty : ['/login']);
      expect(controller.error, isNull);
    });
  }

  for (final change in [
    'unchanged',
    'B',
    'B-then-A',
    'completion-first-B-then-A',
    'same-user-event',
    'silent-B',
    'stream-error',
    'dispose',
    'route-left',
  ]) {
    for (final fails in [false, true]) {
      test('provision completion guard: $change, fails=$fails', () async {
        final profile = MockProfileService();
        final saving = Completer<void>();
        final started = Completer<void>();
        var current = _user('A');
        var cancellations = 0;
        var notifications = 0;
        final changes = StreamController<bool>.broadcast(
          onCancel: () => cancellations++,
        );
        when(() => auth.onAuthChange).thenAnswer((_) => changes.stream);
        when(() => auth.getCurrentUser()).thenAnswer((_) => current);
        when(
          () => auth.isLoggedIn(),
        ).thenAnswer((_) async => AuthenticationResponses.success);
        final uri = Uri.parse('clean-stream://oauth?code=synthetic-code');
        controller = LoadingPageController(
          authService: auth,
          appLinks: links,
          profileService: profile,
          initialUri: uri,
        );
        controller.addListener(() => notifications++);
        when(
          () => profile.createAccount(id: 'A', name: 'Synthetic A'),
        ).thenAnswer((_) {
          started.complete();
          return saving.future;
        });
        final pending = start();
        await started.future;
        expect(changes.hasListener, isTrue);
        if (change == 'completion-first-B-then-A') {
          if (fails) {
            saving.completeError(
              TimeoutException('synthetic provisioning failure'),
            );
          } else {
            saving.complete();
          }
          current = _user('B');
          changes.add(true);
          current = _user('A');
          changes.add(true);
        }
        if (change == 'B' || change == 'B-then-A' || change == 'silent-B') {
          current = _user('B');
        }
        if (change == 'B' || change == 'B-then-A') changes.add(true);
        if (change == 'B-then-A') {
          await Future<void>.delayed(Duration.zero);
          current = _user('A');
          changes.add(true);
        }
        if (change == 'same-user-event') changes.add(true);
        if (change == 'stream-error') {
          changes.addError(StateError('synthetic stream error'));
        }
        if (change == 'dispose') controller.dispose();
        if (change == 'route-left') mounted = false;
        await Future<void>.delayed(Duration.zero);
        if (change == 'dispose') expect(changes.hasListener, isFalse);
        if (!saving.isCompleted && fails) {
          saving.completeError(
            TimeoutException('synthetic provisioning failure'),
          );
        } else if (!saving.isCompleted) {
          saving.complete();
        }
        await pending;
        await start();
        final stale = !['unchanged', 'dispose', 'route-left'].contains(change);
        expect(
          routes,
          change == 'unchanged' ? [fails ? '/login' : '/homePage'] : isEmpty,
        );
        expect(
          controller.error,
          stale ? 'Your sign-in changed. Please return to Login.' : isNull,
        );
        expect(notifications, stale ? 1 : 0);
        expect(cancellations, 1);
        expect(changes.hasListener, isFalse);
        verify(() => auth.getSessionFromURI(uri)).called(1);
        verify(
          () => profile.createAccount(id: 'A', name: 'Synthetic A'),
        ).called(1);
        await changes.close();
        if (change != 'dispose') controller.dispose();
      });
    }
  }

  for (final cached in [false, true]) {
    for (final switches in [false, true]) {
      test(
        'real SDK replay and PKCE scheduling, cached=$cached switches=$switches',
        () async {
          var exchanges = 0;
          final storage = _Verifier();
          final transport = _HttpClient();
          when(() => transport.openUrl(any(), any())).thenAnswer((call) async {
            expect(call.positionalArguments[0], 'POST');
            expect(
              call.positionalArguments[1].toString(),
              'https://offline.invalid/auth/v1/token?grant_type=pkce',
            );
            final request = _HttpRequest();
            final bytes = <int>[];
            when(() => request.headers).thenReturn(_HttpHeaders());
            when(() => request.addStream(any())).thenAnswer((call) async {
              await for (final chunk
                  in call.positionalArguments.single as Stream<List<int>>) {
                bytes.addAll(chunk);
              }
            });
            when(() => request.close()).thenAnswer((_) async {
              expect(jsonDecode(utf8.decode(bytes)), {
                'auth_code': 'synthetic-code',
                'code_verifier': 'synthetic-verifier',
              });
              exchanges++;
              return _HttpResponse(_sdkSession('A'));
            });
            return request;
          });
          await HttpOverrides.runZoned(() async {
            final client = SupabaseClient(
              'https://offline.invalid',
              'synthetic-public',
              authOptions: AuthClientOptions(
                autoRefreshToken: false,
                pkceAsyncStorage: storage,
              ),
            );
            final events = <AuthChangeEvent>[];
            if (cached) {
              await client.auth.setInitialSession(jsonEncode(_sdkSession('A')));
            }
            final observation = client.auth.onAuthStateChange.listen(
              (event) => events.add(event.event),
            );
            final profile = MockProfileService();
            final saving = Completer<void>();
            final started = Completer<void>();
            when(
              () => profile.createAccount(id: 'A', name: 'Synthetic A'),
            ).thenAnswer((_) {
              started.complete();
              return saving.future;
            });
            controller = LoadingPageController(
              authService: SupabaseAuthService(client: client),
              appLinks: links,
              profileService: profile,
              initialUri: Uri.parse('clean-stream://oauth?code=synthetic-code'),
            );
            final pending = start();
            await started.future.timeout(const Duration(seconds: 2));
            expect(events, [
              if (cached) AuthChangeEvent.initialSession,
              AuthChangeEvent.signedIn,
            ]);
            if (switches) {
              await client.auth.setInitialSession(jsonEncode(_sdkSession('B')));
              await client.auth.setInitialSession(jsonEncode(_sdkSession('A')));
            }
            saving.complete();
            await pending;
            await start();
            expect(routes, switches ? isEmpty : ['/homePage']);
            expect(controller.error, switches ? isNotNull : isNull);
            expect(exchanges, 1);
            expect(storage.reads, 1);
            expect(storage.removals, 1);
            verify(
              () => profile.createAccount(id: 'A', name: 'Synthetic A'),
            ).called(1);
            controller.dispose();
            await observation.cancel();
            await client.dispose();
            transport.close();
          }, createHttpClient: (_) => transport);
        },
      );
    }
  }
}

User _user(String id) => User(
  id: id,
  appMetadata: {},
  userMetadata: {'name': 'Synthetic $id'},
  aud: 'authenticated',
  createdAt: '',
);

Map<String, dynamic> _sdkSession(String id) {
  String part(Object data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return {
    'access_token':
        '${part({'alg': 'HS256'})}.${part({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': _user(id).toJson(),
  };
}

class _Verifier extends GotrueAsyncStorage {
  int reads = 0;
  int removals = 0;
  @override
  Future<String?> getItem({required String key}) async {
    reads++;
    return 'synthetic-verifier';
  }

  @override
  Future<void> removeItem({required String key}) async {
    removals++;
  }

  @override
  Future<void> setItem({required String key, required String value}) async {}
}

class _HttpClient extends Mock implements HttpClient {}

class _HttpRequest extends Mock implements HttpClientRequest {}

class _HttpHeaders extends Mock implements HttpHeaders {}

class _HttpResponse extends Mock implements HttpClientResponse {
  _HttpResponse(Map<String, dynamic> session)
    : bytes = utf8.encode(jsonEncode(session)) {
    when(() => statusCode).thenReturn(200);
    when(() => contentLength).thenReturn(bytes.length);
    when(() => headers).thenReturn(_HttpHeaders());
    when(() => isRedirect).thenReturn(false);
    when(() => redirects).thenReturn([]);
    when(() => persistentConnection).thenReturn(false);
    when(() => reasonPhrase).thenReturn('Synthetic response');
  }
  final List<int> bytes;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
