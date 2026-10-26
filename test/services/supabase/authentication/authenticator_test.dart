import 'dart:async';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late SupabaseAuthService authenticator;
  late SupabaseMock client;
  late GoTrueMock supabaseAuth;

  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(OAuthProvider.google);
    registerFallbackValue(UserAttributesFake());
    registerFallbackValue(OtpType.recovery);
  });

  group('read-only typed session access', () {
    test('currentSession returns the exact SDK snapshot or null', () {
      final client = SupabaseMock();
      final auth = GoTrueMock();
      when(() => client.auth).thenReturn(auth);
      final service = SupabaseAuthService(client: client);
      final session = Session(
        accessToken: 'fake',
        tokenType: 'bearer',
        refreshToken: 'fake',
        user: const User(
          id: 'synthetic-user',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '',
        ),
      );
      when(() => auth.currentSession).thenReturn(session);
      expect(identical(service.currentSession, session), isTrue);
      when(() => auth.currentSession).thenReturn(null);
      expect(service.currentSession, isNull);
      verify(() => client.auth).called(2);
      verify(() => auth.currentSession).called(2);
      verifyNoMoreInteractions(client);
      verifyNoMoreInteractions(auth);
    });

    test(
      'typed events/errors pass through while the bool stream is preserved',
      () async {
        final client = SupabaseMock();
        final auth = GoTrueMock();
        final source = StreamController<AuthState>.broadcast();
        when(() => client.auth).thenReturn(auth);
        when(() => auth.onAuthStateChange).thenAnswer((_) => source.stream);
        final service = SupabaseAuthService(client: client);
        final typed = <AuthState>[];
        final booleans = <bool>[];
        final errors = <Object>[];
        final typedSubscription = service.authStateChanges.listen(
          typed.add,
          onError: errors.add,
        );
        final boolSubscription = service.onAuthChange.listen(
          booleans.add,
          onError: errors.add,
        );
        final session = Session(
          accessToken: 'fake',
          tokenType: 'bearer',
          refreshToken: 'fake',
          user: const User(
            id: 'synthetic-user',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '',
          ),
        );
        final states = [
          AuthState(AuthChangeEvent.initialSession, session),
          AuthState(AuthChangeEvent.mfaChallengeVerified, session),
          const AuthState(AuthChangeEvent.signedOut, null),
        ];
        for (final state in states) {
          source.add(state);
        }
        final error = AuthRetryableFetchException(message: 'synthetic offline');
        source.addError(error);
        await Future<void>.delayed(Duration.zero);
        expect(typed.length, states.length);
        for (var i = 0; i < states.length; i++) {
          expect(identical(typed[i], states[i]), isTrue);
        }
        expect(booleans, [true, true, false]);
        expect(errors.length, 2);
        expect(errors.every((item) => identical(item, error)), isTrue);
        await typedSubscription.cancel();
        await boolSubscription.cancel();
        expect(source.hasListener, isFalse);
        await source.close();
        verify(() => client.auth).called(2);
        verify(() => auth.onAuthStateChange).called(2);
        verifyNoMoreInteractions(client);
        verifyNoMoreInteractions(auth);
      },
    );
  });

  group("authentication Tests", () {
    setUp(() {
      client = SupabaseMock();
      supabaseAuth = GoTrueMock();
      when(() => client.auth).thenReturn(supabaseAuth);

      authenticator = SupabaseAuthService(client: client);

      final mockUser = User(
        id: '11111111-1111-1111-1111-111111111111',
        aud: 'authenticated',
        role: 'authenticated',
        email: 'testemail@test.com',
        emailConfirmedAt: null,
        phone: '',
        lastSignInAt: '',
        appMetadata: {},
        userMetadata: {},
        identities: [],
        createdAt: '',
        updatedAt: '',
      );
      when(() => supabaseAuth.currentUser).thenReturn(mockUser);

      when(
        () => supabaseAuth.refreshSession(),
      ).thenAnswer((_) async => AuthResponse());
      when(() => supabaseAuth.signOut()).thenAnswer((_) async {});
      when(
        () => supabaseAuth.resend(
          type: OtpType.signup,
          email: any(named: 'email'),
        ),
      ).thenAnswer((_) async => ResendResponse());
    });

    test("Tests if login is successful", () async {
      when(
        () => supabaseAuth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => AuthResponse(
          user: const User(
            id: '11111111-1111-1111-1111-111111111111',
            aud: 'authenticated',
            role: 'authenticated',
            email: 'example@email.com',
            emailConfirmedAt: '2024-01-01T00:00:00Z',
            phone: '',
            lastSignInAt: '2024-01-01T00:00:00Z',
            appMetadata: {
              'provider': 'email',
              'providers': ['email'],
            },
            userMetadata: {},
            identities: [
              UserIdentity(
                identityId: '22222222-2222-2222-2222-222222222222',
                id: '11111111-1111-1111-1111-111111111111',
                userId: '11111111-1111-1111-1111-111111111111',
                identityData: {
                  'email': 'example@email.com',
                  'email_verified': false,
                  'phone_verified': false,
                  'sub': '11111111-1111-1111-1111-111111111111',
                },
                provider: 'email',
                lastSignInAt: '2024-01-01T00:00:00Z',
                createdAt: '2024-01-01T00:00:00Z',
                updatedAt: '2024-01-01T00:00:00Z',
              ),
            ],
            createdAt: '2024-01-01T00:00:00Z',
            updatedAt: '2024-01-01T00:00:00Z',
          ),
          session: Session(
            accessToken: '<ACCESS_TOKEN>',
            tokenType: 'bearer',
            expiresIn: 3600,
            refreshToken: '<REFRESH_TOKEN>',
            user: const User(
              id: '11111111-1111-1111-1111-111111111111',
              aud: 'authenticated',
              role: 'authenticated',
              email: 'example@email.com',
              emailConfirmedAt: '2024-01-01T00:00:00Z',
              phone: '',
              lastSignInAt: '2024-01-01T00:00:00Z',
              appMetadata: {
                'provider': 'email',
                'providers': ['email'],
              },
              userMetadata: {},
              identities: [
                UserIdentity(
                  identityId: '22222222-2222-2222-2222-222222222222',
                  id: '11111111-1111-1111-1111-111111111111',
                  userId: '11111111-1111-1111-1111-111111111111',
                  identityData: {
                    'email': 'example@email.com',
                    'email_verified': false,
                    'phone_verified': false,
                    'sub': '11111111-1111-1111-1111-111111111111',
                  },
                  provider: 'email',
                  lastSignInAt: '2024-01-01T00:00:00Z',
                  createdAt: '2024-01-01T00:00:00Z',
                  updatedAt: '2024-01-01T00:00:00Z',
                ),
              ],
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          ),
        ),
      );

      final response = await authenticator.login(
        "testemail@test.com",
        "testpassword",
      );

      expect(response, AuthenticationResponses.success);
    });

    test("Sign up test", () async {
      when(
        () => supabaseAuth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          data: {"full_name": "testname"},
        ),
      ).thenAnswer(
        (_) async => AuthResponse(
          user: const User(
            id: '11111111-1111-1111-1111-111111111111',
            aud: 'authenticated',
            role: 'authenticated',
            email: 'example@email.com',
            emailConfirmedAt: '2024-01-01T00:00:00Z',
            phone: '',
            lastSignInAt: '2024-01-01T00:00:00Z',
            appMetadata: {
              'provider': 'email',
              'providers': ['email'],
            },
            userMetadata: {},
            identities: [
              UserIdentity(
                identityId: '22222222-2222-2222-2222-222222222222',
                id: '11111111-1111-1111-1111-111111111111',
                userId: '11111111-1111-1111-1111-111111111111',
                identityData: {
                  'email': 'example@email.com',
                  'email_verified': false,
                  'phone_verified': false,
                  'sub': '11111111-1111-1111-1111-111111111111',
                },
                provider: 'email',
                lastSignInAt: '2024-01-01T00:00:00Z',
                createdAt: '2024-01-01T00:00:00Z',
                updatedAt: '2024-01-01T00:00:00Z',
              ),
            ],
            createdAt: '2024-01-01T00:00:00Z',
            updatedAt: '2024-01-01T00:00:00Z',
          ),
          session: Session(
            accessToken: '<ACCESS_TOKEN>',
            tokenType: 'bearer',
            expiresIn: 3600,
            refreshToken: '<REFRESH_TOKEN>',
            user: const User(
              id: '11111111-1111-1111-1111-111111111111',
              aud: 'authenticated',
              role: 'authenticated',
              email: 'example@email.com',
              emailConfirmedAt: '2024-01-01T00:00:00Z',
              phone: '',
              lastSignInAt: '2024-01-01T00:00:00Z',
              appMetadata: {
                'provider': 'email',
                'providers': ['email'],
              },
              userMetadata: {},
              identities: [
                UserIdentity(
                  identityId: '22222222-2222-2222-2222-222222222222',
                  id: '11111111-1111-1111-1111-111111111111',
                  userId: '11111111-1111-1111-1111-111111111111',
                  identityData: {
                    'email': 'example@email.com',
                    'email_verified': false,
                    'phone_verified': false,
                    'sub': '11111111-1111-1111-1111-111111111111',
                  },
                  provider: 'email',
                  lastSignInAt: '2024-01-01T00:00:00Z',
                  createdAt: '2024-01-01T00:00:00Z',
                  updatedAt: '2024-01-01T00:00:00Z',
                ),
              ],
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          ),
        ),
      );

      final response = await authenticator.signUp(
        "testemail",
        "testpassword123G@",
        "testname",
      );

      expect(response, AuthenticationResponses.success);
    });

    test('signup awaiting confirmation does not request a second email', () async {
      const email = 'new-customer@example.test';
      when(() => supabaseAuth.signUp(
        email: email,
        password: 'ValidPassword1!',
        data: {'full_name': 'New Customer'},
      )).thenAnswer((_) async => AuthResponse(user: const User(
        id: 'new-customer',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
      )));

      expect(
        await authenticator.signUp(email, 'ValidPassword1!', 'New Customer'),
        AuthenticationResponses.success,
      );
      expect(authenticator.getLastSignedUpUserId(), 'new-customer');
      verify(() => supabaseAuth.signUp(
        email: email,
        password: 'ValidPassword1!',
        data: {'full_name': 'New Customer'},
      )).called(1);
      verifyNever(() => supabaseAuth.resend(
        type: OtpType.signup,
        email: any(named: 'email'),
      ));
    });

    test('signed-out customer can explicitly resend confirmation', () async {
      when(() => supabaseAuth.currentUser).thenReturn(null);
      expect(
        await authenticator.resendVerification(email: 'new-customer@example.test'),
        AuthenticationResponses.success,
      );
      verify(() => supabaseAuth.resend(
        type: OtpType.signup,
        email: 'new-customer@example.test',
      )).called(1);
    });

    test("Sign up test has no digit", () async {
      when(
        () => supabaseAuth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => AuthResponse(
          user: const User(
            id: '11111111-1111-1111-1111-111111111111',
            aud: 'authenticated',
            role: 'authenticated',
            email: 'example@email.com',
            emailConfirmedAt: '2024-01-01T00:00:00Z',
            phone: '',
            lastSignInAt: '2024-01-01T00:00:00Z',
            appMetadata: {
              'provider': 'email',
              'providers': ['email'],
            },
            userMetadata: {},
            identities: [
              UserIdentity(
                identityId: '22222222-2222-2222-2222-222222222222',
                id: '11111111-1111-1111-1111-111111111111',
                userId: '11111111-1111-1111-1111-111111111111',
                identityData: {
                  'email': 'example@email.com',
                  'email_verified': false,
                  'phone_verified': false,
                  'sub': '11111111-1111-1111-1111-111111111111',
                },
                provider: 'email',
                lastSignInAt: '2024-01-01T00:00:00Z',
                createdAt: '2024-01-01T00:00:00Z',
                updatedAt: '2024-01-01T00:00:00Z',
              ),
            ],
            createdAt: '2024-01-01T00:00:00Z',
            updatedAt: '2024-01-01T00:00:00Z',
          ),
          session: Session(
            accessToken: '<ACCESS_TOKEN>',
            tokenType: 'bearer',
            expiresIn: 3600,
            refreshToken: '<REFRESH_TOKEN>',
            user: const User(
              id: '11111111-1111-1111-1111-111111111111',
              aud: 'authenticated',
              role: 'authenticated',
              email: 'example@email.com',
              emailConfirmedAt: '2024-01-01T00:00:00Z',
              phone: '',
              lastSignInAt: '2024-01-01T00:00:00Z',
              appMetadata: {
                'provider': 'email',
                'providers': ['email'],
              },
              userMetadata: {},
              identities: [
                UserIdentity(
                  identityId: '22222222-2222-2222-2222-222222222222',
                  id: '11111111-1111-1111-1111-111111111111',
                  userId: '11111111-1111-1111-1111-111111111111',
                  identityData: {
                    'email': 'example@email.com',
                    'email_verified': false,
                    'phone_verified': false,
                    'sub': '11111111-1111-1111-1111-111111111111',
                  },
                  provider: 'email',
                  lastSignInAt: '2024-01-01T00:00:00Z',
                  createdAt: '2024-01-01T00:00:00Z',
                  updatedAt: '2024-01-01T00:00:00Z',
                ),
              ],
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          ),
        ),
      );

      final response = await authenticator.signUp(
        "testemail",
        "testpasswordG",
        "testname",
      );

      expect(response, AuthenticationResponses.noDigit);
    });

    test("Sign up test no special character", () async {
      when(
        () => supabaseAuth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => AuthResponse(
          user: const User(
            id: '11111111-1111-1111-1111-111111111111',
            aud: 'authenticated',
            role: 'authenticated',
            email: 'example@email.com',
            emailConfirmedAt: '2024-01-01T00:00:00Z',
            phone: '',
            lastSignInAt: '2024-01-01T00:00:00Z',
            appMetadata: {
              'provider': 'email',
              'providers': ['email'],
            },
            userMetadata: {},
            identities: [
              UserIdentity(
                identityId: '22222222-2222-2222-2222-222222222222',
                id: '11111111-1111-1111-1111-111111111111',
                userId: '11111111-1111-1111-1111-111111111111',
                identityData: {
                  'email': 'example@email.com',
                  'email_verified': false,
                  'phone_verified': false,
                  'sub': '11111111-1111-1111-1111-111111111111',
                },
                provider: 'email',
                lastSignInAt: '2024-01-01T00:00:00Z',
                createdAt: '2024-01-01T00:00:00Z',
                updatedAt: '2024-01-01T00:00:00Z',
              ),
            ],
            createdAt: '2024-01-01T00:00:00Z',
            updatedAt: '2024-01-01T00:00:00Z',
          ),
          session: Session(
            accessToken: '<ACCESS_TOKEN>',
            tokenType: 'bearer',
            expiresIn: 3600,
            refreshToken: '<REFRESH_TOKEN>',
            user: const User(
              id: '11111111-1111-1111-1111-111111111111',
              aud: 'authenticated',
              role: 'authenticated',
              email: 'example@email.com',
              emailConfirmedAt: '2024-01-01T00:00:00Z',
              phone: '',
              lastSignInAt: '2024-01-01T00:00:00Z',
              appMetadata: {
                'provider': 'email',
                'providers': ['email'],
              },
              userMetadata: {},
              identities: [
                UserIdentity(
                  identityId: '22222222-2222-2222-2222-222222222222',
                  id: '11111111-1111-1111-1111-111111111111',
                  userId: '11111111-1111-1111-1111-111111111111',
                  identityData: {
                    'email': 'example@email.com',
                    'email_verified': false,
                    'phone_verified': false,
                    'sub': '11111111-1111-1111-1111-111111111111',
                  },
                  provider: 'email',
                  lastSignInAt: '2024-01-01T00:00:00Z',
                  createdAt: '2024-01-01T00:00:00Z',
                  updatedAt: '2024-01-01T00:00:00Z',
                ),
              ],
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          ),
        ),
      );

      final response = await authenticator.signUp(
        "testemail",
        "testpassword123G",
        "testname",
      );

      expect(response, AuthenticationResponses.noSpecialCharacter);
    });

    test("Sign up test no upper case", () async {
      when(
        () => supabaseAuth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => AuthResponse(
          user: const User(
            id: '11111111-1111-1111-1111-111111111111',
            aud: 'authenticated',
            role: 'authenticated',
            email: 'example@email.com',
            emailConfirmedAt: '2024-01-01T00:00:00Z',
            phone: '',
            lastSignInAt: '2024-01-01T00:00:00Z',
            appMetadata: {
              'provider': 'email',
              'providers': ['email'],
            },
            userMetadata: {},
            identities: [
              UserIdentity(
                identityId: '22222222-2222-2222-2222-222222222222',
                id: '11111111-1111-1111-1111-111111111111',
                userId: '11111111-1111-1111-1111-111111111111',
                identityData: {
                  'email': 'example@email.com',
                  'email_verified': false,
                  'phone_verified': false,
                  'sub': '11111111-1111-1111-1111-111111111111',
                },
                provider: 'email',
                lastSignInAt: '2024-01-01T00:00:00Z',
                createdAt: '2024-01-01T00:00:00Z',
                updatedAt: '2024-01-01T00:00:00Z',
              ),
            ],
            createdAt: '2024-01-01T00:00:00Z',
            updatedAt: '2024-01-01T00:00:00Z',
          ),
          session: Session(
            accessToken: '<ACCESS_TOKEN>',
            tokenType: 'bearer',
            expiresIn: 3600,
            refreshToken: '<REFRESH_TOKEN>',
            user: const User(
              id: '11111111-1111-1111-1111-111111111111',
              aud: 'authenticated',
              role: 'authenticated',
              email: 'example@email.com',
              emailConfirmedAt: '2024-01-01T00:00:00Z',
              phone: '',
              lastSignInAt: '2024-01-01T00:00:00Z',
              appMetadata: {
                'provider': 'email',
                'providers': ['email'],
              },
              userMetadata: {},
              identities: [
                UserIdentity(
                  identityId: '22222222-2222-2222-2222-222222222222',
                  id: '11111111-1111-1111-1111-111111111111',
                  userId: '11111111-1111-1111-1111-111111111111',
                  identityData: {
                    'email': 'example@email.com',
                    'email_verified': false,
                    'phone_verified': false,
                    'sub': '11111111-1111-1111-1111-111111111111',
                  },
                  provider: 'email',
                  lastSignInAt: '2024-01-01T00:00:00Z',
                  createdAt: '2024-01-01T00:00:00Z',
                  updatedAt: '2024-01-01T00:00:00Z',
                ),
              ],
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          ),
        ),
      );

      final response = await authenticator.signUp(
        "testemail",
        "testpassword123@",
        "testname",
      );

      expect(response, AuthenticationResponses.noUppercase);
    });

    test("Sign up test no digit", () async {
      when(
        () => supabaseAuth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => AuthResponse(
          user: const User(
            id: '11111111-1111-1111-1111-111111111111',
            aud: 'authenticated',
            role: 'authenticated',
            email: 'example@email.com',
            emailConfirmedAt: '2024-01-01T00:00:00Z',
            phone: '',
            lastSignInAt: '2024-01-01T00:00:00Z',
            appMetadata: {
              'provider': 'email',
              'providers': ['email'],
            },
            userMetadata: {},
            identities: [
              UserIdentity(
                identityId: '22222222-2222-2222-2222-222222222222',
                id: '11111111-1111-1111-1111-111111111111',
                userId: '11111111-1111-1111-1111-111111111111',
                identityData: {
                  'email': 'example@email.com',
                  'email_verified': false,
                  'phone_verified': false,
                  'sub': '11111111-1111-1111-1111-111111111111',
                },
                provider: 'email',
                lastSignInAt: '2024-01-01T00:00:00Z',
                createdAt: '2024-01-01T00:00:00Z',
                updatedAt: '2024-01-01T00:00:00Z',
              ),
            ],
            createdAt: '2024-01-01T00:00:00Z',
            updatedAt: '2024-01-01T00:00:00Z',
          ),
          session: Session(
            accessToken: '<ACCESS_TOKEN>',
            tokenType: 'bearer',
            expiresIn: 3600,
            refreshToken: '<REFRESH_TOKEN>',
            user: const User(
              id: '11111111-1111-1111-1111-111111111111',
              aud: 'authenticated',
              role: 'authenticated',
              email: 'example@email.com',
              emailConfirmedAt: '2024-01-01T00:00:00Z',
              phone: '',
              lastSignInAt: '2024-01-01T00:00:00Z',
              appMetadata: {
                'provider': 'email',
                'providers': ['email'],
              },
              userMetadata: {},
              identities: [
                UserIdentity(
                  identityId: '22222222-2222-2222-2222-222222222222',
                  id: '11111111-1111-1111-1111-111111111111',
                  userId: '11111111-1111-1111-1111-111111111111',
                  identityData: {
                    'email': 'example@email.com',
                    'email_verified': false,
                    'phone_verified': false,
                    'sub': '11111111-1111-1111-1111-111111111111',
                  },
                  provider: 'email',
                  lastSignInAt: '2024-01-01T00:00:00Z',
                  createdAt: '2024-01-01T00:00:00Z',
                  updatedAt: '2024-01-01T00:00:00Z',
                ),
              ],
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          ),
        ),
      );

      final response = await authenticator.signUp(
        "testemail",
        "test",
        "testname",
      );

      expect(response, AuthenticationResponses.lessThanMinLength);
    });

    test(
      "Tests if login is unsuccessful because of invalid credentials",
      () async {
        when(
          () => supabaseAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => AuthResponse(user: null, session: null));

        final response = await authenticator.login("testemail", "testpassword");

        expect(response, AuthenticationResponses.failure);
      },
    );

    test(
      "Tests if login is unsuccessful because email is not confirmed",
      () async {
        when(
          () => supabaseAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          AuthApiException(
            "Email Not Confirmed",
            code: 'email_not_confirmed',
            statusCode: "400",
          ),
        );

        final response = await authenticator.login("testemail", "testpassword");

        expect(response, AuthenticationResponses.emailNotVerified);
      },
    );

    test("Resend verification email unsuccessfully", () async {
      when(
        () => supabaseAuth.resend(
          type: OtpType.signup,
          email: any(named: "email"),
        ),
      ).thenThrow(AuthException("Invalid email"));

      final response = await authenticator.resendVerification();
      expect(response, AuthenticationResponses.failure);
    });

    test("Resend verification email succesfully", () async {
      when(
        () => supabaseAuth.resend(
          type: OtpType.signup,
          email: any(named: "email"),
        ),
      ).thenAnswer((_) async => ResendResponse());

      final response = await authenticator.resendVerification();
      expect(response, AuthenticationResponses.success);
    });

    test("User is logged in", () async {
      when(() => supabaseAuth.currentSession).thenReturn(
        Session(
          accessToken: 'test',
          tokenType: 'test',
          user: User(
            id: '',
            appMetadata: {},
            userMetadata: {},
            aud: '',
            createdAt: '',
          ),
        ),
      );

      final response = await authenticator.isLoggedIn();
      expect(response, AuthenticationResponses.success);
    });

    test("User is not logged in", () async {
      when(() => supabaseAuth.currentUser).thenReturn(null);

      final response = await authenticator.isLoggedIn();
      expect(response, AuthenticationResponses.failure);
    });

    test("Verifying that the logged out logic was called", () async {
      await authenticator.logout();
      verify(() => client.auth.signOut());
    });

    test("Should return that an email is not verified", () async {
      when(
        () => supabaseAuth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        AuthApiException('Email not verified', code: 'email_not_confirmed'),
      );

      final result = await authenticator.login("testEmail", "testPassword");
      expect(result, AuthenticationResponses.emailNotVerified);
    });

    test("Test if an exception is thrown with a different code", () async {
      when(
        () => supabaseAuth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        AuthApiException('Email not verified', code: 'random-test-code'),
      );

      final result = await authenticator.login("testEmail", "testPassword");
      expect(result, AuthenticationResponses.failure);
    });

    test("Test if an exception is thrown with an unkown exception", () async {
      when(
        () => supabaseAuth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(Exception("Unknown exception"));

      final result = await authenticator.login("testEmail", "testPassword");
      expect(result, AuthenticationResponses.failure);
    });

    test("Test that correctID is returned", () {
      final result = authenticator.getCurrentUserId;
      expect(result, "11111111-1111-1111-1111-111111111111");
    });

    test("Test that null is returned for no user being able to be found", () {
      when(() => supabaseAuth.currentUser).thenReturn(null);
      final result = authenticator.getCurrentUserId;
      expect(result, null);
    });

    test("Tests if the email is verified", () {
      final testUser = User(
        id: '11111111-1111-1111-1111-111111111111',
        aud: 'authenticated',
        role: 'authenticated',
        email: 'example@email.com',
        emailConfirmedAt: '2024-01-01T00:00:00Z',
        phone: '',
        lastSignInAt: '2024-01-01T00:00:00Z',
        appMetadata: {
          'provider': 'email',
          'providers': ['email'],
        },
        userMetadata: {},
        identities: [
          UserIdentity(
            identityId: '22222222-2222-2222-2222-222222222222',
            id: '11111111-1111-1111-1111-111111111111',
            userId: '11111111-1111-1111-1111-111111111111',
            identityData: {
              'email': 'example@email.com',
              'email_verified': false,
              'phone_verified': false,
              'sub': '11111111-1111-1111-1111-111111111111',
            },
            provider: 'email',
            lastSignInAt: '2024-01-01T00:00:00Z',
            createdAt: '2024-01-01T00:00:00Z',
            updatedAt: '2024-01-01T00:00:00Z',
          ),
        ],
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
      );

      when(() => supabaseAuth.currentUser).thenReturn(testUser);
      var result = authenticator.isEmailVerified();
      expect(result, true);
    });

    test("Tests if the email is not verified", () {
      final testUser = User(
        id: '11111111-1111-1111-1111-111111111111',
        aud: 'authenticated',
        role: 'authenticated',
        email: 'example@email.com',
        emailConfirmedAt: null,
        phone: '',
        lastSignInAt: '2024-01-01T00:00:00Z',
        appMetadata: {
          'provider': 'email',
          'providers': ['email'],
        },
        userMetadata: {},
        identities: [
          UserIdentity(
            identityId: '22222222-2222-2222-2222-222222222222',
            id: '11111111-1111-1111-1111-111111111111',
            userId: '11111111-1111-1111-1111-111111111111',
            identityData: {
              'email': 'example@email.com',
              'email_verified': false,
              'phone_verified': false,
              'sub': '11111111-1111-1111-1111-111111111111',
            },
            provider: 'email',
            lastSignInAt: '2024-01-01T00:00:00Z',
            createdAt: '2024-01-01T00:00:00Z',
            updatedAt: '2024-01-01T00:00:00Z',
          ),
        ],
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
      );

      when(() => supabaseAuth.currentUser).thenReturn(testUser);
      var result = authenticator.isEmailVerified();
      expect(result, false);
    });

    test("onAuthChange emits true when a user exists", () async {
      final auth = GoTrueMock();

      final controller = StreamController<AuthState>();

      when(() => supabaseAuth.onAuthStateChange).thenAnswer(
        (_) => Stream.value(
          AuthState(
            AuthChangeEvent.signedIn,
            Session(
              accessToken: '',
              tokenType: 'bearer',
              expiresIn: 3600,
              refreshToken: '',
              user: supabaseAuth.currentUser!,
            ),
          ),
        ),
      );

      when(() => auth.onAuthStateChange).thenAnswer((_) => controller.stream);

      final fakeUser = User(
        id: "123",
        aud: "",
        role: "",
        email: "",
        phone: "",
        createdAt: "",
        updatedAt: "",
        appMetadata: {},
        userMetadata: {},
        identities: [],
      );

      final fakeSession = Session(
        accessToken: "",
        tokenType: "",
        user: fakeUser,
        expiresIn: 3600,
      );

      expectLater(authenticator.onAuthChange, emits(true));

      controller.add(AuthState(AuthChangeEvent.signedIn, fakeSession));
    });

    test("onAuthChange emits false when a user doesn't exist", () async {
      final controller = StreamController<AuthState>();
      when(
        () => supabaseAuth.onAuthStateChange,
      ).thenAnswer((_) => controller.stream);

      expectLater(authenticator.onAuthChange, emits(false));

      controller.add(AuthState(AuthChangeEvent.signedOut, null));
    });

    test("Tests to see that the redirect was called", () async {
      when(() => supabaseAuth.getSessionFromUrl(any())).thenAnswer(
        (_) async => AuthSessionUrlResponse(
          session: Session(
            accessToken: "test_token",
            tokenType: "bearer",
            user: User(
              id: 'test-user-id',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2024-01-01T00:00:00Z',
            ),
          ),
          redirectType: "sign_up",
        ),
      );

      final testUri = Uri.parse('https://example.com/callback?code=test123');
      await authenticator.getSessionFromURI(testUri);

      verify(() => supabaseAuth.getSessionFromUrl(testUri)).called(1);
    });

    test("Tests that the user was grabbed correctly", () async {
      await authenticator.getCurrentUser();
      verify(() => client.auth.currentUser);
    });

    test("Tests that the correct userID is gotten", () async {
      String? userID = await authenticator.getCurrentUserId;
      expect(userID, '11111111-1111-1111-1111-111111111111');
    });

    test("Tests that as session is returned", () async {
      when(() => supabaseAuth.getSessionFromUrl(any())).thenAnswer(
        (_) async => AuthSessionUrlResponse(
          session: Session(
            accessToken: "test",
            tokenType: "test",
            user: User(
              id: "1234",
              appMetadata: {},
              userMetadata: {},
              aud: "test",
              createdAt: "test",
            ),
          ),
          redirectType: "test",
        ),
      );

      await authenticator.getSessionFromURI(Uri());
      verify(() => client.auth.getSessionFromUrl(any()));
    });

    test("Verifies that a session was refreshed if it's not null", () async {
      when(() => supabaseAuth.currentSession).thenReturn(
        Session(
          accessToken: "test",
          tokenType: "test",
          user: User(
            id: '',
            appMetadata: {},
            userMetadata: {},
            aud: '',
            createdAt: '',
          ),
        ),
      );

      await authenticator.refreshSession();

      verify(() => supabaseAuth.refreshSession());
    });

    test(
      "Verifies that a session was not refreshed if the session is null",
      () async {
        when(() => supabaseAuth.currentSession).thenReturn(null);

        await authenticator.refreshSession();

        verifyNever(() => supabaseAuth.refreshSession());
      },
    );

    test("getCurrentUserEmail returns correct email", () async {
      when(() => supabaseAuth.currentSession).thenReturn(null);

      String? result = await authenticator.getCurrentUserEmail();

      expect(result, 'testemail@test.com');
    });

    test("Tests that code is verified correctly", () async {
      when(
        () => supabaseAuth.verifyOTP(
          email: any(named: 'email'),
          token: any(named: 'token'),
          type: any(named: 'type'),
        ),
      ).thenAnswer(
        (_) async => AuthResponse(
          session: Session(
            accessToken: "test",
            tokenType: "test",
            user: User(
              id: '',
              appMetadata: {},
              userMetadata: {},
              aud: '',
              createdAt: '',
            ),
          ),
        ),
      );

      AuthenticationResponses testResponse = await authenticator.verifyCode(
        email: "test",
        code: "testCode",
      );

      expect(testResponse, AuthenticationResponses.success);
    });

    test("Tests that failure is returned when exception is thrown", () async {
      when(
        () => supabaseAuth.verifyOTP(
          email: any(named: 'email'),
          token: any(named: 'token'),
          type: any(named: 'type'),
        ),
      ).thenThrow(Exception());

      AuthenticationResponses testResponse = await authenticator.verifyCode(
        email: "test",
        code: "testCode",
      );

      expect(testResponse, AuthenticationResponses.failure);
    });

    test("Tests that exchange code for session runs correctly", () async {
      when(() => supabaseAuth.exchangeCodeForSession(any())).thenAnswer(
        (_) async => AuthSessionUrlResponse(
          session: Session(
            accessToken: "",
            tokenType: "",
            user: User(
              id: "",
              appMetadata: {},
              userMetadata: {},
              aud: "",
              createdAt: "",
            ),
          ),
          redirectType: "",
        ),
      );
      AuthenticationResponses response = await authenticator
          .exchangeCodeForSession("testCode");
      expect(response, AuthenticationResponses.success);
    });

    test("Tests that failure is sent with an exception", () async {
      when(
        () => supabaseAuth.exchangeCodeForSession(any()),
      ).thenThrow(Exception());
      AuthenticationResponses response = await authenticator
          .exchangeCodeForSession("testCode");
      expect(response, AuthenticationResponses.failure);
    });

    test("Tests that update password runs correctly", () async {
      when(
        () => supabaseAuth.updateUser(any()),
      ).thenAnswer((_) async => UserResponse.fromJson({}));

      AuthenticationResponses response = await authenticator.updatePassword(
        "password",
      );

      expect(response, AuthenticationResponses.success);
    });

    test("Tests that update password handles errors", () async {
      when(() => supabaseAuth.updateUser(any())).thenThrow(Exception());

      AuthenticationResponses response = await authenticator.updatePassword(
        "password",
      );

      expect(response, AuthenticationResponses.failure);
    });

    test("Reset password runs correctly", () async {
      when(
        () => supabaseAuth.resetPasswordForEmail(any()),
      ).thenAnswer((_) async {});

      AuthenticationResponses response = await authenticator.resetPassword(
        "testEmail",
      );

      expect(response, AuthenticationResponses.success);
    });

    test("Reset password handles errors", () async {
      when(
        () => supabaseAuth.resetPasswordForEmail(any()),
      ).thenThrow(Exception());

      AuthenticationResponses response = await authenticator.resetPassword(
        "testEmail",
      );

      expect(response, AuthenticationResponses.failure);
    });
    test("Tests that the last signedUpUserId is returned correctly", () {
      authenticator.lastSignedUpUserId = "testID";
      expect(authenticator.getLastSignedUpUserId(), "testID");
    });
  });
}
