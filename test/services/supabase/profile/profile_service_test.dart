import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'mocks.dart';
import '../../../fixtures/loyalty_action_context.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(const Stream<List<int>>.empty());
  });
  late SupabaseMock supabaseMock;
  late QueryBuilderMock queryBuilderMock;
  late FakeFilterBuilderList fakeFilterBuilder;
  late SupabaseProfileService profileHandler;
  late GoTrueClient supabaseAuth;

  setUp(() {
    supabaseMock = SupabaseMock();
    queryBuilderMock = QueryBuilderMock();
    fakeFilterBuilder = FakeFilterBuilderList({
      "full_name": "Nolan Meyer",
      "balance": 0,
    });
    profileHandler = SupabaseProfileService(client: supabaseMock);
    supabaseAuth = GoTrueMock();

    when(
      () => supabaseMock.from('profiles'),
    ).thenAnswer((_) => queryBuilderMock);
    when(
      () => queryBuilderMock.select(any()),
    ).thenAnswer((_) => fakeFilterBuilder);
    when(
      () => queryBuilderMock.update(any()),
    ).thenAnswer((_) => fakeFilterBuilder);
    when(() => supabaseMock.auth).thenReturn(supabaseAuth);

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
    when(() => supabaseAuth.currentSession).thenReturn(_profileSession());
  });

  void verifySnapshotRead() {
    verify(() => supabaseMock.auth).called(1);
    verify(() => supabaseAuth.currentSession).called(1);
    verify(() => supabaseAuth.currentUser).called(1);
    verifyNoMoreInteractions(supabaseAuth);
  }

  group('admission status RPC adapter', () {
    late ProfileService service;
    late _PublicPolicyClient publicClient;
    var publicCreations = 0;
    final wire = {
      'subject_id': '11111111-1111-1111-1111-111111111111',
      'account_access': 'eligible',
      'next_step': 'review_terms',
      'reason': null,
      'account_state': 'legacy_active',
      'restore_until': null,
    };

    setUp(() {
      publicCreations = 0;
      publicClient = _PublicPolicyClient();
      service = SupabaseProfileService(
        client: supabaseMock,
        publicPolicyClientFactory: () {
          publicCreations++;
          return publicClient;
        },
      );
    });

    void verifyAdmissionOnly() {
      verify(() => supabaseMock.rpc('get_admission_status')).called(1);
      verifySnapshotRead();
      verifyNoMoreInteractions(supabaseMock);
      verifyZeroInteractions(queryBuilderMock);
      verifyZeroInteractions(publicClient);
      expect(publicCreations, 0);
    }

    test(
      'uses one argument-free authenticated RPC through ProfileService',
      () async {
        when(
          () => supabaseMock.rpc('get_admission_status'),
        ).thenAnswer((_) => _BoundRpc(Future.value(wire)));

        final result = await service.getAdmissionStatus();

        expect(result, isA<AdmissionStatus>());
        expect(result.subjectId, wire['subject_id']);
        expect(result.accountAccess, 'eligible');
        expect(result.nextStep, 'review_terms');
        expect(result.reason, isNull);
        expect(result.accountState, 'legacy_active');
        expect(result.restoreUntil, isNull);
        verifyAdmissionOnly();
      },
    );

    final errors = <String, Object>{
      'invalid session': const PostgrestException(
        message: 'session_invalid',
        code: 'PT401',
      ),
      'unavailable admission': const PostgrestException(
        message: 'admission_unavailable',
        code: 'PT503',
      ),
      'permission': const PostgrestException(
        message: 'synthetic denied',
        code: '42501',
      ),
      'missing RPC': const PostgrestException(
        message: 'synthetic missing',
        code: 'PGRST202',
      ),
      'Auth refresh': const AuthException(
        'synthetic expired',
        statusCode: '401',
      ),
      'transport timeout': TimeoutException('synthetic timeout'),
    };
    for (final entry in errors.entries) {
      for (final synchronous in [false, true]) {
        test(
          'preserves ${entry.key}, synchronous=$synchronous, without retry',
          () async {
            final stub = when(() => supabaseMock.rpc('get_admission_status'));
            if (synchronous) {
              stub.thenThrow(entry.value);
            } else {
              stub.thenAnswer((_) => _BoundRpc(Future.error(entry.value)));
            }
            await expectLater(
              service.getAdmissionStatus(),
              throwsA(same(entry.value)),
            );
            verifyAdmissionOnly();
          },
        );
      }
    }

    for (final response in <Object?>[
      null,
      {...wire, 'next_step': 'home', 'account_access': 'restricted'},
      {...wire, 'account_state': 'pending_deletion'},
    ]) {
      test('rejects malformed or inconsistent response $response', () async {
        when(
          () => supabaseMock.rpc('get_admission_status'),
        ).thenAnswer((_) => _BoundRpc(Future.value(response)));
        await expectLater(service.getAdmissionStatus(), throwsFormatException);
        verifyAdmissionOnly();
      });
    }

    for (final lateFailure in [false, true]) {
      testWidgets(
        'ten-second wait ignores late completion, failure=$lateFailure',
        (tester) async {
          final pending = Completer<dynamic>();
          var completed = false;
          when(
            () => supabaseMock.rpc('get_admission_status'),
          ).thenAnswer((_) => _BoundRpc(pending.future));
          final result = service.getAdmissionStatus().whenComplete(
            () => completed = true,
          );
          final checked = expectLater(result, throwsA(isA<TimeoutException>()));

          await tester.pump(const Duration(milliseconds: 9999));
          expect(completed, isFalse);
          await tester.pump(const Duration(milliseconds: 1));
          await checked;
          expect(completed, isTrue);
          if (lateFailure) {
            pending.completeError(
              const AuthException('synthetic late failure'),
            );
          } else {
            pending.complete(wire);
          }
          await tester.pump();
          verifyAdmissionOnly();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('action consent adapter', () {
    test('returns current caller context and binds the bearer', () async {
      final request = _BoundRpc(Future.value(actionContextWire(subject: _profileId)));
      when(() => supabaseMock.rpc('get_loyalty_action_context',
        params: {'p_action': 'wallet_load'},
      )).thenAnswer((_) => request);
      final context = await profileHandler.getLoyaltyActionContext('wallet_load');
      expect(context.subjectId, _profileSession().user.id);
      expect(context.acknowledgement, purchaseAcknowledgement);
    });

    test('rejects another account or action in a context response', () async {
      for (final wire in [
        actionContextWire(subject: 'other'),
        actionContextWire(action: 'account_deletion'),
      ]) {
        when(() => supabaseMock.rpc('get_loyalty_action_context',
          params: {'p_action': 'wallet_load'},
        )).thenAnswer((_) => _BoundRpc(Future.value(wire)));
        await expectLater(profileHandler.getLoyaltyActionContext('wallet_load'), throwsStateError);
      }
    });

    test('deletion forwards explicit acknowledgement unchanged', () async {
      final consent = actionContext(action: 'account_deletion').acknowledge();
      final params = {'p_context_id': consent['context_id'], 'p_acknowledged': true};
      when(() => supabaseMock.rpc('request_account_deletion_with_consent', params: params))
          .thenAnswer((_) => _BoundRpc(Future.value({
            'subject_id': _profileSession().user.id,
            'account_access': 'restricted', 'next_step': 'blocked',
            'reason': 'explicit_restore_required', 'account_state': 'pending_deletion',
            'restore_until': '2027-01-03T12:00:00Z',
          })));
      final result = await profileHandler.requestAccountDeletion(consent: consent);
      expect(result.accountState, 'pending_deletion');
      verify(() => supabaseMock.rpc('request_account_deletion_with_consent', params: params)).called(1);
    });
  });

  group('caller-bound lifecycle mutations', () {
    for (final rpc in ['request_account_deletion_with_consent', 'restore_account']) {
      final requesting = rpc == 'request_account_deletion_with_consent';
      final consent = actionContext(action: 'account_deletion').acknowledge();
      final params = requesting ? {'p_context_id': consent['context_id'], 'p_acknowledged': true} : null;
      final wire = <String, dynamic>{
        'subject_id': _profileId,
        'account_access': requesting ? 'restricted' : 'eligible',
        'next_step': requesting ? 'blocked' : 'review_terms',
        'reason': requesting ? 'explicit_restore_required' : null,
        'account_state': requesting ? 'pending_deletion' : 'legacy_active',
        'restore_until': requesting ? '2026-10-30T06:39:23Z' : null,
      };
      Future<AdmissionStatus> call() => requesting
          ? profileHandler.requestAccountDeletion(consent: consent)
          : profileHandler.restoreAccount();

      test(
        '$rpc binds one caller request and validates status',
        () async {
          final session = supabaseAuth.currentSession!;
          final request = _BoundRpc(Future.value(wire));
          when(() => supabaseMock.rpc(rpc, params: params)).thenAnswer((_) => request);
          final result = await call();
          expect(result.accountState, wire['account_state']);
          expect(result.subjectId, session.user.id);
          expect(
            request.capturedHeaders['Authorization'],
            'Bearer ${session.accessToken}',
          );
          verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
          verifyNever(() => supabaseMock.from(any()));
          verifyNever(() => supabaseAuth.signOut());
        },
      );

      for (final response in <Object?>[
        null,
        {...wire, 'subject_id': _otherId},
        {...wire, 'restore_until': true},
        {
          'subject_id': _profileId,
          'account_access': requesting ? 'eligible' : 'restricted',
          'next_step': requesting ? 'home' : 'blocked',
          'reason': requesting ? null : 'explicit_restore_required',
          'account_state': requesting ? 'legacy_active' : 'pending_deletion',
          'restore_until': requesting ? null : '2026-10-30T06:39:23Z',
        },
      ]) {
        test('$rpc rejects mismatched acknowledgement $response', () async {
          when(
            () => supabaseMock.rpc(rpc, params: params),
          ).thenAnswer((_) => _BoundRpc(Future.value(response)));
          await expectLater(call(), throwsFormatException);
          verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
        });
      }

      for (final change in ['logout', 'B', 'A-B-A', 'expired']) {
        test('$rpc rejects late success after $change', () async {
          final pending = Completer<dynamic>();
          when(
            () => supabaseMock.rpc(rpc, params: params),
          ).thenAnswer((_) => _BoundRpc(pending.future));
          final checked = expectLater(call(), throwsStateError);
          when(() => supabaseAuth.currentSession).thenReturn(switch (change) {
            'logout' => null,
            'B' => _profileSession(id: _otherId),
            'expired' => _profileSession(seconds: -60),
            _ => _profileSession(),
          });
          pending.complete(wire);
          await checked;
          verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
        });
      }

      for (final error in <Object>[
        const PostgrestException(
          message: 'fresh_session_required',
          code: 'PT403',
        ),
        const PostgrestException(message: 'session_invalid', code: 'PT401'),
        const PostgrestException(
          message: 'lifecycle_unavailable',
          code: 'PT503',
        ),
        TimeoutException('Synthetic unknown outcome'),
      ]) {
        test('$rpc preserves $error without retry or logout', () async {
          when(
            () => supabaseMock.rpc(rpc, params: params),
          ).thenAnswer((_) => _BoundRpc(Future.error(error)));
          await expectLater(call(), throwsA(same(error)));
          verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
          verifyNever(() => supabaseAuth.signOut());
        });
      }
      test('$rpc requires an active caller before dispatch', () async {
        when(() => supabaseAuth.currentSession).thenReturn(null);
        await expectLater(call(), throwsStateError);
        verifyNever(() => supabaseMock.rpc(rpc, params: params));
      });
      testWidgets('$rpc timeout is unknown, with no automatic retry', (
        tester,
      ) async {
        final pending = Completer<dynamic>();
        when(
          () => supabaseMock.rpc(rpc, params: params),
        ).thenAnswer((_) => _BoundRpc(pending.future));
        final checked = expectLater(call(), throwsA(isA<TimeoutException>()));
        await tester.pump(const Duration(seconds: 10));
        await checked;
        pending.complete(wire);
        await tester.pump();
        verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('request-bound admission and terms', () {
    for (final rpc in [
      'get_admission_status',
      'get_loyalty_policy_status',
      'accept_loyalty_policy',
    ]) {
      final params = rpc == 'accept_loyalty_policy'
          ? {'p_version': 'synthetic-v2'}
          : null;
      final wire = rpc == 'get_admission_status'
          ? <String, dynamic>{
              'subject_id': _profileId,
              'account_access': 'eligible',
              'next_step': 'review_terms',
              'reason': null,
              'account_state': 'legacy_active',
              'restore_until': null,
            }
          : <String, dynamic>{
              'required_version': 'synthetic-v2',
              'policy_text': 'abc',
              'policy_sha256':
                  'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
              'accepted_version': null,
              'accepted_at': null,
              'acceptance_required': true,
            };
      Future<Object> call(ProfileService service) => switch (rpc) {
        'get_admission_status' => service.getAdmissionStatus(),
        'get_loyalty_policy_status' => service.getLoyaltyPolicyStatus(),
        _ => service.acceptLoyaltyPolicy('synthetic-v2'),
      };

      for (final entry in <String, Session?>{
        'missing': null,
        'mismatched identity': _profileSession(id: _otherId),
        'expired': _profileSession(seconds: -60),
        'near expiry': _profileSession(seconds: 20),
        'missing expiry': _profileSession(includeExpiry: false),
        'empty bearer': _profileSession(token: ''),
        'malformed bearer': _profileSession(token: 'synthetic-malformed'),
      }.entries) {
        test('$rpc rejects ${entry.key} snapshot before dispatch', () async {
          when(() => supabaseAuth.currentSession).thenReturn(entry.value);
          when(
            () => supabaseMock.rpc(rpc, params: params),
          ).thenAnswer((_) => _BoundRpc(Future.value(wire)));
          await expectLater(call(profileHandler), throwsA(anything));
          verifyNever(() => supabaseMock.rpc(rpc, params: params));
          verifyNever(() => supabaseMock.from(any()));
          verify(() => supabaseMock.auth).called(1);
          verify(() => supabaseAuth.currentSession).called(1);
          verify(() => supabaseAuth.currentUser).called(1);
          verifyNoMoreInteractions(supabaseMock);
          verifyNoMoreInteractions(supabaseAuth);
        });
      }

      for (final id in <String?>[null, '']) {
        test('$rpc rejects missing or empty current identity: $id', () async {
          final snapshot = _profileSession(id: id ?? _profileId);
          when(() => supabaseAuth.currentSession).thenReturn(snapshot);
          when(
            () => supabaseAuth.currentUser,
          ).thenReturn(id == null ? null : snapshot.user);
          await expectLater(call(profileHandler), throwsStateError);
          verifyNever(() => supabaseMock.rpc(rpc, params: params));
          verifyNever(() => supabaseMock.from(any()));
        });
      }

      for (final error in <Object>[
        const AuthException('synthetic Auth failure', statusCode: '401'),
        const PostgrestException(message: 'session_invalid', code: 'PT401'),
        const PostgrestException(message: 'account_restricted', code: 'PT403'),
        const PostgrestException(message: 'unavailable', code: 'PT503'),
      ]) {
        for (final synchronous in [false, true]) {
          test(
            '$rpc preserves ${error.runtimeType} $error sync=$synchronous',
            () async {
              when(
                () => supabaseAuth.currentSession,
              ).thenReturn(_profileSession());
              final stub = when(() => supabaseMock.rpc(rpc, params: params));
              if (synchronous) {
                stub.thenThrow(error);
              } else {
                stub.thenAnswer((_) => _BoundRpc(Future.error(error)));
              }
              await expectLater(call(profileHandler), throwsA(same(error)));
              verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
              verify(() => supabaseMock.auth).called(1);
              verify(() => supabaseAuth.currentSession).called(1);
              verify(() => supabaseAuth.currentUser).called(1);
              verifyNoMoreInteractions(supabaseMock);
              verifyNoMoreInteractions(supabaseAuth);
            },
          );
        }
      }

      for (final lateFailure in [false, true]) {
        testWidgets(
          '$rpc bounds response wait without cancellation: $lateFailure',
          (tester) async {
            when(
              () => supabaseAuth.currentSession,
            ).thenReturn(_profileSession());
            final pending = Completer<dynamic>();
            when(
              () => supabaseMock.rpc(rpc, params: params),
            ).thenAnswer((_) => _BoundRpc(pending.future));
            var finished = false;
            final result = call(
              profileHandler,
            ).whenComplete(() => finished = true);
            final checked = expectLater(
              result,
              throwsA(isA<TimeoutException>()),
            );
            await tester.pump(const Duration(milliseconds: 9999));
            expect(finished, isFalse);
            await tester.pump(const Duration(milliseconds: 1));
            await checked;
            expect(finished, isTrue);
            if (lateFailure) {
              pending.completeError(
                const AuthException('synthetic late failure'),
              );
            } else {
              pending.complete(wire);
            }
            await tester.pump();
            verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
            verify(() => supabaseMock.auth).called(1);
            verify(() => supabaseAuth.currentSession).called(1);
            verify(() => supabaseAuth.currentUser).called(1);
            verifyNoMoreInteractions(supabaseMock);
            verifyNoMoreInteractions(supabaseAuth);
            expect(tester.takeException(), isNull);
          },
        );
      }

      for (final outcome in [
        'switch',
        'malformed',
        'success',
        'revoked',
        'expired',
      ]) {
        test(
          '$rpc pins the dispatch snapshot through SDK account switch: $outcome',
          () async {
            final captured = _profileSession();
            final refreshing = Completer<void>();
            final release = Completer<void>();
            var rpcCalls = 0;
            var refreshCalls = 0;
            var passwordCalls = 0;
            var publicCalls = 0;
            final denial = switch (outcome) {
              'revoked' => 'PT401',
              'expired' => 'PGRST303',
              _ => null,
            };
            final transport = _HttpTransport((request) async {
              if (request.url.path == '/auth/v1/token') {
                if (request.url.queryParameters['grant_type'] == 'password') {
                  passwordCalls++;
                  return (
                    body: jsonEncode(_profileSession(id: _otherId).toJson()),
                    status: 200,
                  );
                }
                expect(
                  request.url.queryParameters['grant_type'],
                  'refresh_token',
                );
                refreshCalls++;
                refreshing.complete();
                await release.future;
                return switch (outcome) {
                  'revoked' => (
                    body:
                        '{"message":"synthetic revoked","error_code":"refresh_token_not_found"}',
                    status: 400,
                  ),
                  'success' || 'expired' => (
                    body: jsonEncode(_profileSession().toJson()),
                    status: 200,
                  ),
                  _ => (body: '{"access_token":7}', status: 200),
                };
              }
              expect(request.url.path, '/rest/v1/rpc/$rpc');
              expect(request.method, 'POST');
              expect(request.url.query, isEmpty);
              expect(jsonDecode(request.body), params);
              expect(
                request.headers['authorization'] ==
                    'Bearer ${captured.accessToken}',
                isTrue,
              );
              rpcCalls++;
              return denial == null
                  ? (body: jsonEncode(wire), status: 200)
                  : (
                      body: jsonEncode({
                        'code': denial,
                        'message': 'synthetic denied',
                      }),
                      status: 401,
                    );
            });
            await HttpOverrides.runZoned(() async {
              final client = _DispatchClient();
              addTearDown(() async {
                await client.dispose();
                transport.close();
              });
              await client.auth.setInitialSession(
                jsonEncode(captured.toJson()),
              );
              final beforeHeaders = Map.of(client.rest.headers);
              client.beforeRpc = () {
                unawaited(
                  client.auth.setInitialSession(
                    jsonEncode(
                      outcome == 'switch'
                          ? _profileSession(id: _otherId).toJson()
                          : _profileSession(seconds: 20).toJson(),
                    ),
                  ),
                );
              };
              final service = SupabaseProfileService(
                client: client,
                publicPolicyClientFactory: () {
                  publicCalls++;
                  throw StateError('Public transport must not be used');
                },
              );
              final result = call(service);
              Object? response;
              final checked = outcome == 'malformed'
                  ? expectLater(result, throwsA(isA<FormatException>()))
                  : denial == null
                  ? result.then((value) => response = value)
                  : expectLater(
                      result,
                      throwsA(
                        isA<PostgrestException>().having(
                          (e) => e.code,
                          'code',
                          denial,
                        ),
                      ),
                    );
              if (outcome != 'switch') {
                await refreshing.future.timeout(const Duration(seconds: 2));
                await client.auth.signInWithPassword(
                  email: 'b@synthetic.invalid',
                  password: 'synthetic-password',
                );
                expect(client.auth.currentUser?.id, _otherId);
                release.complete();
              }
              await checked;
              if (denial == null && outcome != 'malformed') {
                expect(
                  response,
                  rpc == 'get_admission_status'
                      ? isA<AdmissionStatus>()
                      : isA<LoyaltyPolicyStatus>(),
                );
              }
              expect(rpcCalls, outcome == 'malformed' ? 0 : 1);
              expect(refreshCalls, outcome == 'switch' ? 0 : 1);
              expect(passwordCalls, outcome == 'switch' ? 0 : 1);
              expect(publicCalls, 0);
              expect(client.auth.currentUser?.id, _otherId);
              expect(client.getChannels(), isEmpty);
              expect(client.realtime.isConnected, isFalse);
              expect(
                jsonEncode(client.rest.headers) == jsonEncode(beforeHeaders),
                isTrue,
              );
            }, createHttpClient: (_) => transport);
          },
        );
      }
    }
  });

  group('public policy descriptor', () {
    late _PublicPolicyClient publicClient;
    late SupabaseProfileService service;
    var creations = 0;
    final wire = {
      'required_version': 'review-only-synthetic',
      'policy_text': 'abc',
      'policy_sha256':
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    };

    setUp(() {
      creations = 0;
      publicClient = _PublicPolicyClient();
      when(() => publicClient.dispose()).thenAnswer((_) async {});
      service = SupabaseProfileService(
        client: supabaseMock,
        publicPolicyClientFactory: () {
          creations++;
          return publicClient;
        },
      );
    });

    void verifyPublicOnly() {
      expect(creations, 1);
      verify(() => publicClient.rpc('get_loyalty_policy_descriptor')).called(1);
      verify(() => publicClient.dispose()).called(1);
      verifyNoMoreInteractions(publicClient);
      verifyZeroInteractions(supabaseMock);
      verifyZeroInteractions(supabaseAuth);
    }

    test(
      'one public RPC works without consulting the shared Auth client',
      () async {
        when(
          () => supabaseMock.auth,
        ).thenThrow(StateError('Auth must not be read'));
        when(
          () => publicClient.rpc('get_loyalty_policy_descriptor'),
        ).thenAnswer((_) => _PolicyRpcResult(Future.value(wire)));
        final ProfileService api = service;

        final result = await api.getLoyaltyPolicyDescriptor();

        expect(result.policyText, 'abc');
        expect(result.requiredVersion, 'review-only-synthetic');
        verifyPublicOnly();
      },
    );

    for (final synchronous in [false, true]) {
      test(
        'preserves SDK failure and disposes: synchronous=$synchronous',
        () async {
          const error = PostgrestException(
            message: 'synthetic unavailable',
            code: 'PGRST202',
          );
          final stub = when(
            () => publicClient.rpc('get_loyalty_policy_descriptor'),
          );
          if (synchronous) {
            stub.thenThrow(error);
          } else {
            stub.thenAnswer((_) => _PolicyRpcResult(Future.error(error)));
          }
          await expectLater(
            service.getLoyaltyPolicyDescriptor(),
            throwsA(same(error)),
          );
          verifyPublicOnly();
        },
      );
    }

    test('disposes after invalid descriptor/hash', () async {
      when(() => publicClient.rpc('get_loyalty_policy_descriptor')).thenAnswer(
        (_) =>
            _PolicyRpcResult(Future.value({...wire, 'policy_text': 'changed'})),
      );
      await expectLater(
        service.getLoyaltyPolicyDescriptor(),
        throwsFormatException,
      );
      verifyPublicOnly();
    });

    testWidgets('times out after ten seconds and ignores a late response', (
      tester,
    ) async {
      final pending = Completer<dynamic>();
      when(
        () => publicClient.rpc('get_loyalty_policy_descriptor'),
      ).thenAnswer((_) => _PolicyRpcResult(pending.future));
      final result = service.getLoyaltyPolicyDescriptor();
      final checked = expectLater(result, throwsA(isA<TimeoutException>()));
      await tester.pump(const Duration(seconds: 10));
      await checked;
      pending.complete(wire);
      await tester.pump();
      verifyPublicOnly();
      expect(tester.takeException(), isNull);
    });

    test(
      'existing constructor does not fall back to authenticated transport',
      () async {
        await expectLater(
          profileHandler.getLoyaltyPolicyDescriptor(),
          throwsStateError,
        );
        verifyZeroInteractions(supabaseMock);
        verifyZeroInteractions(supabaseAuth);
      },
    );
  });

  group('loyalty policy RPC adapters', () {
    Map<String, dynamic> status({bool accepted = false}) => {
      'required_version': 'synthetic-v2',
      'policy_text': 'Review-only synthetic policy.\n\nSecond paragraph.',
      'policy_sha256':
          '18194ff45fc91b265e82cd1560733c3518c541b4027db4670c74a93f1d055f18',
      'accepted_version': accepted ? 'synthetic-v2' : null,
      'accepted_at': accepted ? '2026-09-29T12:00:00+00:00' : null,
      'acceptance_required': !accepted,
    };

    test('status uses one argument-free RPC through ProfileService', () async {
      when(
        () => supabaseMock.rpc('get_loyalty_policy_status'),
      ).thenAnswer((_) => _BoundRpc(Future.value(status())));
      final ProfileService service = profileHandler;

      final result = await service.getLoyaltyPolicyStatus();

      expect(result, isA<LoyaltyPolicyStatus>());
      expect(result.requiredVersion, 'synthetic-v2');
      expect(result.acceptanceRequired, isTrue);
      verify(() => supabaseMock.rpc('get_loyalty_policy_status')).called(1);
      verifySnapshotRead();
      verifyNoMoreInteractions(supabaseMock);
    });

    test(
      'accept sends only the exact supplied version and returns status',
      () async {
        when(
          () => supabaseMock.rpc(
            'accept_loyalty_policy',
            params: {'p_version': 'synthetic-v2'},
          ),
        ).thenAnswer((_) => _BoundRpc(Future.value(status(accepted: true))));
        final ProfileService service = profileHandler;

        final result = await service.acceptLoyaltyPolicy('synthetic-v2');

        expect(result.acceptedVersion, 'synthetic-v2');
        expect(result.acceptedAt, DateTime.utc(2026, 9, 29, 12));
        expect(result.acceptanceRequired, isFalse);
        verify(
          () => supabaseMock.rpc(
            'accept_loyalty_policy',
            params: {'p_version': 'synthetic-v2'},
          ),
        ).called(1);
        verifySnapshotRead();
        verifyNoMoreInteractions(supabaseMock);
      },
    );

    test(
      'accept does not trim, substitute or pre-fetch a supplied version',
      () async {
        const version = ' synthetic-v1 ';
        const error = PostgrestException(
          message: 'policy_version_mismatch',
          code: '22023',
        );
        when(
          () => supabaseMock.rpc(
            'accept_loyalty_policy',
            params: {'p_version': version},
          ),
        ).thenAnswer((_) => _BoundRpc(Future.error(error)));

        await expectLater(
          profileHandler.acceptLoyaltyPolicy(version),
          throwsA(same(error)),
        );

        verify(
          () => supabaseMock.rpc(
            'accept_loyalty_policy',
            params: {'p_version': version},
          ),
        ).called(1);
        verifySnapshotRead();
        verifyNoMoreInteractions(supabaseMock);
      },
    );

    for (final accept in [false, true]) {
      final rpc = accept
          ? 'accept_loyalty_policy'
          : 'get_loyalty_policy_status';
      final params = accept ? {'p_version': 'synthetic-v2'} : null;
      Future<LoyaltyPolicyStatus> call() => accept
          ? profileHandler.acceptLoyaltyPolicy('synthetic-v2')
          : profileHandler.getLoyaltyPolicyStatus();

      for (final error in [
        const PostgrestException(
          message: 'authentication_required',
          code: '42501',
        ),
        const PostgrestException(
          message: 'account_not_eligible',
          code: '42501',
        ),
        const PostgrestException(message: 'profile_not_found', code: 'P0002'),
        const PostgrestException(
          message: 'policy_version_mismatch',
          code: '22023',
        ),
        const PostgrestException(
          message: 'synthetic database failure',
          code: 'XX000',
        ),
        StateError('synthetic transport failure'),
      ]) {
        test('$rpc preserves asynchronous $error without retry', () async {
          when(
            () => supabaseMock.rpc(rpc, params: params),
          ).thenAnswer((_) => _BoundRpc(Future.error(error)));

          await expectLater(call(), throwsA(same(error)));

          verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
          verifySnapshotRead();
          verifyNoMoreInteractions(supabaseMock);
        });
      }

      test('$rpc preserves a synchronous SDK error', () async {
        const error = PostgrestException(message: 'synthetic SDK failure');
        when(() => supabaseMock.rpc(rpc, params: params)).thenThrow(error);

        await expectLater(call(), throwsA(same(error)));

        verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
        verifySnapshotRead();
        verifyNoMoreInteractions(supabaseMock);
      });

      for (final entry in {
        'null': null,
        'row list': [status()],
        'missing field': status()..remove('accepted_at'),
        'hash mismatch': status()..['policy_text'] = 'different text',
      }.entries) {
        test('$rpc rejects malformed response: ${entry.key}', () async {
          when(
            () => supabaseMock.rpc(rpc, params: params),
          ).thenAnswer((_) => _BoundRpc(Future.value(entry.value)));

          await expectLater(call(), throwsFormatException);

          verify(() => supabaseMock.rpc(rpc, params: params)).called(1);
          verifySnapshotRead();
          verifyNoMoreInteractions(supabaseMock);
        });
      }
    }
  });

  test('getUserBalanceById returns fake user balance', () async {
    final result = await profileHandler.getUserBalanceById("1");
    expect(result?["balance"], 0);
  });

  test('getUserBalanceById throws Postgres exception', () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(PostgrestException(message: "Test exception"));
    final result = await profileHandler.getUserBalanceById("1");
    expect(result, null);
  });

  test('getUserBalanceById throws unknown exception', () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(Exception("Test execption"));
    final result = await profileHandler.getUserBalanceById("1");
    expect(result, null);
  });

  group('request-bound own-profile provisioning', () {
    for (final entry in <String, Session?>{
      'missing': null,
      'wrong identity': _profileSession(id: _otherId),
      'expired': _profileSession(seconds: -60),
      'near expiry': _profileSession(seconds: 20),
      'missing expiry': _profileSession(includeExpiry: false),
      'empty bearer': _profileSession(token: ''),
      'malformed bearer': _profileSession(token: 'synthetic-malformed'),
    }.entries) {
      test('${entry.key} rejects before any request', () async {
        when(() => supabaseAuth.currentSession).thenReturn(entry.value);
        await expectLater(
          profileHandler.createAccount(id: _profileId, name: 'Synthetic A'),
          throwsA(anything),
        );
        verify(() => supabaseMock.auth).called(1);
        verify(() => supabaseAuth.currentSession).called(1);
        verifyNoMoreInteractions(supabaseMock);
        verifyNoMoreInteractions(supabaseAuth);
        verifyZeroInteractions(queryBuilderMock);
      });
    }

    for (final denial in <String?>[
      null,
      'PT401',
      'PGRST303',
      'PT403',
      'PT503',
      'PGRST202',
    ]) {
      test('one name-only authenticated RPC, response=$denial', () async {
        final captured = _profileSession();
        var calls = 0;
        var publicCalls = 0;
        final transport = _HttpTransport((request) async {
          calls++;
          expect(
            request.url.toString(),
            'https://offline.invalid/rest/v1/rpc/ensure_own_profile',
          );
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {'p_full_name': 'Synthetic A'});
          expect(
            request.headers['authorization'] ==
                'Bearer ${captured.accessToken}',
            isTrue,
          );
          return denial == null
              ? (body: '', status: 204)
              : (
                  body: jsonEncode({
                    'code': denial,
                    'message': 'synthetic denied',
                  }),
                  status: denial == 'PT503' ? 503 : 401,
                );
        });
        await HttpOverrides.runZoned(() async {
          final client = SupabaseClient(
            'https://offline.invalid',
            'synthetic-public',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          );
          addTearDown(() async {
            await client.dispose();
            transport.close();
          });
          await client.auth.setInitialSession(jsonEncode(captured.toJson()));
          final before = Map.of(client.rest.headers);
          final service = SupabaseProfileService(
            client: client,
            publicPolicyClientFactory: () {
              publicCalls++;
              throw StateError('Public transport must not be used');
            },
          );
          final result = service.createAccount(
            id: _profileId,
            name: 'Synthetic A',
          );
          if (denial == null) {
            await result;
          } else {
            await expectLater(
              result,
              throwsA(
                isA<PostgrestException>().having((e) => e.code, 'code', denial),
              ),
            );
          }
          expect(calls, 1);
          expect(publicCalls, 0);
          expect(jsonEncode(client.rest.headers) == jsonEncode(before), isTrue);
        }, createHttpClient: (_) => transport);
      });
    }

    for (final refreshOutcome in ['malformed', 'success', 'revoked']) {
      test(
        'captured A bearer survives awaited refresh and B sign-in: $refreshOutcome',
        () async {
          final captured = _profileSession();
          final refreshing = Completer<void>();
          final release = Completer<void>();
          var rpcCalls = 0;
          var refreshCalls = 0;
          var passwordCalls = 0;
          final transport = _HttpTransport((request) async {
            expect(request.url.host, 'offline.invalid');
            if (request.url.path == '/auth/v1/token') {
              if (request.url.queryParameters['grant_type'] == 'password') {
                passwordCalls++;
                return (
                  body: jsonEncode(_profileSession(id: _otherId).toJson()),
                  status: 200,
                );
              }
              expect(
                request.url.queryParameters['grant_type'],
                'refresh_token',
              );
              refreshCalls++;
              refreshing.complete();
              await release.future;
              return switch (refreshOutcome) {
                'malformed' => (body: '{"access_token":7}', status: 200),
                'revoked' => (
                  body:
                      '{"message":"synthetic revoked","error_code":"refresh_token_not_found"}',
                  status: 400,
                ),
                _ => (
                  body: jsonEncode(_profileSession().toJson()),
                  status: 200,
                ),
              };
            }
            expect(request.url.path, '/rest/v1/rpc/ensure_own_profile');
            rpcCalls++;
            expect(
              request.headers['authorization'] ==
                  'Bearer ${captured.accessToken}',
              isTrue,
            );
            expect(jsonDecode(request.body), {'p_full_name': 'Synthetic A'});
            return refreshOutcome == 'revoked'
                ? (
                    body: '{"code":"PT401","message":"session_invalid"}',
                    status: 401,
                  )
                : (body: '', status: 204);
          });
          await HttpOverrides.runZoned(() async {
            final client = _DispatchClient();
            addTearDown(() async {
              await client.dispose();
              transport.close();
            });
            await client.auth.setInitialSession(jsonEncode(captured.toJson()));
            // Force the SDK lookup to need refresh after the adapter's synchronous
            // snapshot. All subsequent refresh and HTTP behavior is the real SDK.
            client.beforeRpc = () {
              unawaited(
                client.auth.setInitialSession(
                  jsonEncode(_profileSession(seconds: 20).toJson()),
                ),
              );
            };
            final result = SupabaseProfileService(
              client: client,
            ).createAccount(id: _profileId, name: 'Synthetic A');
            final checked = refreshOutcome == 'malformed'
                ? expectLater(result, throwsA(isA<FormatException>()))
                : refreshOutcome == 'revoked'
                ? expectLater(
                    result,
                    throwsA(
                      isA<PostgrestException>().having(
                        (e) => e.code,
                        'code',
                        'PT401',
                      ),
                    ),
                  )
                : expectLater(result, completes);
            await refreshing.future.timeout(const Duration(seconds: 2));
            await client.auth.signInWithPassword(
              email: 'b@synthetic.invalid',
              password: 'synthetic-password',
            );
            expect(client.auth.currentUser?.id, _otherId);
            release.complete();
            await checked;
            expect(rpcCalls, refreshOutcome == 'malformed' ? 0 : 1);
            expect(refreshCalls, 1);
            expect(passwordCalls, 1);
            expect(client.auth.currentUser?.id, _otherId);
            expect(client.getChannels(), isEmpty);
            expect(client.realtime.isConnected, isFalse);
          }, createHttpClient: (_) => transport);
        },
      );
    }

    for (final failure in <Object>[
      const AuthException('synthetic Auth failure'),
      const PostgrestException(message: 'synthetic failure', code: 'PT503'),
      TimeoutException('synthetic timeout'),
    ]) {
      test('preserves error identity: ${failure.runtimeType}', () async {
        when(() => supabaseAuth.currentSession).thenReturn(_profileSession());
        when(
          () => supabaseMock.rpc(
            'ensure_own_profile',
            params: {'p_full_name': 'Synthetic A'},
          ),
        ).thenAnswer((_) => _BoundRpc(Future.error(failure)));
        await expectLater(
          profileHandler.createAccount(id: _profileId, name: 'Synthetic A'),
          throwsA(same(failure)),
        );
        verifyNever(() => supabaseMock.from(any()));
      });
    }

    for (final lateFailure in [false, true]) {
      testWidgets(
        'ten-second response wait does not cancel late result: $lateFailure',
        (tester) async {
          final pending = Completer<dynamic>();
          when(() => supabaseAuth.currentSession).thenReturn(_profileSession());
          when(
            () => supabaseMock.rpc(
              'ensure_own_profile',
              params: {'p_full_name': 'Synthetic A'},
            ),
          ).thenAnswer((_) => _BoundRpc(pending.future));
          var finished = false;
          final result = profileHandler
              .createAccount(id: _profileId, name: 'Synthetic A')
              .whenComplete(() => finished = true);
          final checked = expectLater(result, throwsA(isA<TimeoutException>()));
          await tester.pump(const Duration(milliseconds: 9999));
          expect(finished, isFalse);
          await tester.pump(const Duration(milliseconds: 1));
          await checked;
          if (lateFailure) {
            pending.completeError(StateError('synthetic late failure'));
          } else {
            pending.complete(null);
          }
          await tester.pump();
          verify(
            () => supabaseMock.rpc(
              'ensure_own_profile',
              params: {'p_full_name': 'Synthetic A'},
            ),
          ).called(1);
          verifyNever(() => supabaseMock.from(any()));
        },
      );
    }
  });

  test(
    "Tests that the logic was called correctly to update account balance",
    () async {
      await profileHandler.updateBalanceById(
        '11111111-1111-1111-1111-111111111111',
        47.20,
      );
      verify(() => supabaseMock.from("profiles")).called(1);
      verify(() => queryBuilderMock.update({"balance": 47.20})).called(1);
    },
  );

  test("Tests that updateBalanceID catches Postgrest exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(PostgrestException(message: "Test exception"));
    await profileHandler.updateBalanceById(
      '11111111-1111-1111-1111-111111111111',
      47.20,
    );
    //Test will fail if exception was not caught
  });

  test("Tests that updateBalanceID catches unknown exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(Exception("Test exception"));
    await profileHandler.updateBalanceById(
      '11111111-1111-1111-1111-111111111111',
      47.20,
    );
    //Test will fail if exception was not caught
  });

  test("Tests that getUserNameById catches Postgrest exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(PostgrestException(message: "Test exception"));
    await profileHandler.getUserNameById("1234");
    //Test will fail if exception was not caught
  });

  test("Tests that getUserNameById catches unknown exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(Exception("Test exception"));
    await profileHandler.getUserNameById("1234");
    //Test will fail if exception was not caught
  });

  test("Tests that getUserNameById runs successfully", () async {
    var result = await profileHandler.getUserNameById("1234");
    expect(result, "Nolan Meyer");
  });

  test("Tests that getUserRefundAttempts catches unknown exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(Exception("Test exception"));
    await profileHandler.getUserRefundAttempts("1234");
    //Test will fail if exception was not caught
  });

  test(
    "Tests that getUserRefundAttempts catches Postgrest exception",
    () async {
      fakeFilterBuilder = FakeFilterBuilderList({"refund_attempts": 0});
      var result = await profileHandler.getUserRefundAttempts("1234");
      expect(result, "0");
    },
  );

  test(
    "Tests that the logic was called correctly to update account name",
    () async {
      await profileHandler.updateName("testName");
      verify(() => supabaseMock.auth.currentUser).called(1);
      verify(() => supabaseMock.from("profiles")).called(1);
      verify(
        () => queryBuilderMock.update({"full_name": "testName"}),
      ).called(1);
    },
  );

  test("Tests that updateName catches Postgrest exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(PostgrestException(message: "Test exception"));
    expect(
      () async => await profileHandler.updateName("testName"),
      throwsA(isA<Exception>()),
    );
  });

  test("Tests that updateName throws unknown exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(Exception("Test exception"));
    expect(
      () async => await profileHandler.updateName("testName"),
      throwsA(isA<Exception>()),
    );
  });

  test("Tests that updateName throws exception when userID is null ", () async {
    when(() => supabaseAuth.currentUser?.id).thenReturn(null);
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(Exception("Test exception"));
    expect(
      () async => await profileHandler.updateName("testName"),
      throwsA(isA<Exception>()),
    );
  });

  test(
    "Tests that the logic was called correctly to update account rewards",
    () async {
      await profileHandler.updateRewardsById(
        '11111111-1111-1111-1111-111111111111',
        10.50,
      );
      verify(() => supabaseMock.from("profiles")).called(1);
      verify(
        () => queryBuilderMock.update({"reward_tracker": 10.50}),
      ).called(1);
    },
  );

  test("Tests that updateRewardsById catches Postgrest exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(PostgrestException(message: "Test exception"));
    await profileHandler.updateRewardsById(
      '11111111-1111-1111-1111-111111111111',
      10.50,
    );
  });

  test("Tests that updateRewardsById catches unknown exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(Exception("Test exception"));
    await profileHandler.updateRewardsById(
      '11111111-1111-1111-1111-111111111111',
      10.50,
    );
  });

  test("getNotificationLeadTime returns saved value", () async {
    when(
      () => queryBuilderMock.select('notif_lead_time'),
    ).thenAnswer((_) => FakeFilterBuilderList({'notif_lead_time': 12}));

    final result = await profileHandler.getNotificationLeadTime();

    expect(result, 12);
  });

  test(
    "getNotificationLeadTime defaults when profile row is missing",
    () async {
      when(
        () => queryBuilderMock.select('notif_lead_time'),
      ).thenAnswer((_) => FakeFilterBuilderList(null));

      final result = await profileHandler.getNotificationLeadTime();

      expect(result, 5);
    },
  );

  test("getNotificationLeadTime catches Postgrest exception", () async {
    when(
      () => supabaseMock.from('profiles'),
    ).thenThrow(PostgrestException(message: "Test exception"));

    final result = await profileHandler.getNotificationLeadTime();

    expect(result, 5);
  });

  test("setNotificationLeadTime runs correctly", () async {
    await profileHandler.setNotificationLeadTime(5);
    verify(() => supabaseMock.from("profiles")).called(1);
  });

  test("setNotificationLeadTime does not run if user is null", () async {
    when(() => supabaseAuth.currentUser).thenReturn(null);
    await profileHandler.setNotificationLeadTime(5);
    verifyNever(() => supabaseMock.from("profiles"));
  });
}

class _PolicyRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final Future<dynamic> _result;

  _PolicyRpcResult(this._result);

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) => _result.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<T> then<T>(
    FutureOr<T> Function(dynamic) onValue, {
    Function? onError,
  }) => _result.then(onValue, onError: onError);
}

class _PublicPolicyClient extends Mock implements PostgrestClient {}

const _profileId = '11111111-1111-1111-1111-111111111111';
const _otherId = '22222222-2222-2222-2222-222222222222';

Session _profileSession({
  String id = _profileId,
  int seconds = 3600,
  bool includeExpiry = true,
  String? token,
}) {
  String part(Object data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return Session(
    accessToken:
        token ??
        '${part({'alg': 'HS256'})}.${part({'sub': id, if (includeExpiry) 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds})}.synthetic',
    tokenType: 'bearer',
    refreshToken: 'synthetic-refresh',
    user: User(
      id: id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '',
    ),
  );
}

class _BoundRpc extends _PolicyRpcResult {
  _BoundRpc(super.result);
  final capturedHeaders = <String, String>{};

  @override
  PostgrestFilterBuilder<dynamic> setHeader(String key, String value) {
    expect(key, 'Authorization');
    expect(value.startsWith('Bearer '), isTrue);
    capturedHeaders[key] = value;
    return this;
  }
}

class _DispatchClient extends SupabaseClient {
  _DispatchClient()
    : super(
        'https://offline.invalid',
        'synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
  void Function()? beforeRpc;

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    get = false,
  }) {
    beforeRpc?.call();
    return super.rpc<T>(fn, params: params, get: get);
  }
}

typedef _Request = ({
  String method,
  Uri url,
  Map<String, String> headers,
  String body,
});
typedef _Reply = ({String body, int status});

class _HttpRequest extends Mock implements HttpClientRequest {}

class _HttpHeaders extends Mock implements HttpHeaders {}

class _HttpTransport extends Mock implements HttpClient {
  _HttpTransport(Future<_Reply> Function(_Request) respond) {
    when(() => openUrl(any(), any())).thenAnswer((call) async {
      final request = _HttpRequest();
      final headers = _HttpHeaders();
      final values = <String, String>{};
      final bytes = <int>[];
      when(() => request.headers).thenReturn(headers);
      when(() => headers.set(any(), any())).thenAnswer((call) {
        values[(call.positionalArguments[0] as String).toLowerCase()] = call
            .positionalArguments[1]
            .toString();
      });
      when(() => request.addStream(any())).thenAnswer((call) async {
        await for (final chunk
            in call.positionalArguments.single as Stream<List<int>>) {
          bytes.addAll(chunk);
        }
      });
      when(() => request.close()).thenAnswer((_) async {
        final url = call.positionalArguments[1] as Uri;
        expect(url.origin, 'https://offline.invalid');
        return _HttpResponse(
          await respond((
            method: call.positionalArguments[0] as String,
            url: url,
            headers: values,
            body: utf8.decode(bytes),
          )),
        );
      });
      return request;
    });
  }
}

class _HttpResponse extends Mock implements HttpClientResponse {
  _HttpResponse(_Reply reply) : bytes = utf8.encode(reply.body) {
    when(() => statusCode).thenReturn(reply.status);
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
