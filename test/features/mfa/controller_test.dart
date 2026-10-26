import 'dart:async';

import 'package:clean_stream_laundry_app/features/mfa/controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures.dart';

void main() {
  late MfaFixture fixture;
  late MfaController controller;

  setUp(() {
    fixture = MfaFixture();
    controller = MfaController(
      authService: fixture.auth,
      mode: MfaMode.enrollment,
    );
  });
  tearDown(() async {
    controller.dispose();
    await fixture.close();
  });

  Future<void> challenge() async {
    fixture.factors = [factor()];
    await controller.load();
  }

  group('factor-list session refresh', () {
    for (final scenario in [
      (MfaMode.enrollment, false, MfaStage.readyToEnroll),
      (MfaMode.enrollment, true, MfaStage.challenge),
      (MfaMode.challenge, true, MfaStage.challenge),
    ]) {
      test(
        '${scenario.$1} with enrolled=${scenario.$2} accepts expected refresh',
        () async {
          controller.dispose();
          controller = MfaController(
            authService: fixture.auth,
            mode: scenario.$1,
          );
          if (scenario.$2) fixture.factors = [factor()];
          final original = fixture.current;
          final generation = controller.generation;
          await controller.load();
          expect(fixture.current, isNot(same(original)));
          expect(fixture.current!.user.id, original!.user.id);
          expect(fixture.listRefreshes, 1);
          expect(controller.generation, generation);
          expect(controller.stage, scenario.$3);
          expect(fixture.revalidations, 0);
          verifyNever(() => fixture.auth.enrollTotp());
        },
      );
    }

    for (final refreshFirst in [true, false]) {
      for (final change in ['B', 'A-B-A']) {
        test(
          'delayed load rejects $change with refresh first=$refreshFirst',
          () async {
            fixture.factors = [factor()];
            final pending = Completer<AuthMFAListFactorsResponse>();
            when(() => fixture.auth.listMfaFactors()).thenAnswer((_) {
              if (refreshFirst) fixture.refreshForLoad();
              return pending.future;
            });
            final request = controller.load();
            await Future<void>.delayed(Duration.zero);
            final original = fixture.current;
            fixture.emit(AuthChangeEvent.signedIn, session(user: 'b'));
            if (change == 'A-B-A') {
              fixture.emit(AuthChangeEvent.signedIn, original);
            }
            if (!refreshFirst) fixture.refreshForLoad();
            pending.complete(fixture.factorResponse);
            await request;
            expect(controller.stage, MfaStage.expired);
            expect(controller.factorId, null);
            expect(controller.canEnroll, false);
            expect(controller.canVerify, false);
            expect(fixture.revalidations, 0);
          },
        );
      }
    }

    for (final event in [
      AuthChangeEvent.signedIn,
      AuthChangeEvent.signedOut,
      AuthChangeEvent.userUpdated,
    ]) {
      test('load refresh does not allow unrelated $event', () async {
        final pending = Completer<AuthMFAListFactorsResponse>();
        when(() => fixture.auth.listMfaFactors()).thenAnswer((_) {
          fixture.refreshForLoad();
          return pending.future;
        });
        final request = controller.load();
        await Future<void>.delayed(Duration.zero);
        fixture.emit(
          event,
          event == AuthChangeEvent.signedOut ? null : session(),
        );
        pending.complete(fixture.factorResponse);
        await request;
        expect(controller.stage, MfaStage.expired);
        expect(controller.canEnroll, false);
      });
    }

    for (final wrongUser in [true, false]) {
      test(
        'load rejects ${wrongUser ? 'other-user' : 'noncurrent'} refresh event',
        () async {
          final pending = Completer<AuthMFAListFactorsResponse>();
          when(
            () => fixture.auth.listMfaFactors(),
          ).thenAnswer((_) => pending.future);
          final request = controller.load();
          final incoming = session(user: wrongUser ? 'b' : 'account-a');
          if (wrongUser) fixture.current = incoming;
          fixture.events.add(
            AuthState(AuthChangeEvent.tokenRefreshed, incoming),
          );
          pending.complete(fixture.factorResponse);
          await request;
          expect(controller.stage, MfaStage.expired);
          expect(controller.canEnroll, false);
        },
      );
    }
  });

  test(
    'construction never reads factors or enrolls; explicit load only refreshes Auth',
    () async {
      verifyNever(() => fixture.auth.listMfaFactors());
      verifyNever(() => fixture.auth.enrollTotp());
      await controller.load();
      expect(controller.stage, MfaStage.readyToEnroll);
      verifyNever(() => fixture.auth.enrollTotp());
    },
  );

  test(
    'unauthenticated, expired and missing-expiry sessions cannot dispatch',
    () async {
      for (final value in [
        null,
        session()..expiresAt = 1,
        session()..expiresAt = null,
      ]) {
        final localFixture = MfaFixture()..current = value;
        final local = MfaController(
          authService: localFixture.auth,
          mode: MfaMode.enrollment,
        );
        await local.load();
        await local.enroll();
        await local.verify('123456', onVerified: localFixture.revalidate);
        expect(local.stage, MfaStage.expired);
        verifyNever(() => localFixture.auth.listMfaFactors());
        verifyNever(() => localFixture.auth.enrollTotp());
        expect(localFixture.revalidations, 0);
        local.dispose();
        await localFixture.close();
      }
    },
  );

  test('challenge mode cannot enroll even with no factors', () async {
    controller.dispose();
    controller = MfaController(
      authService: fixture.auth,
      mode: MfaMode.challenge,
    );
    await controller.load();
    await controller.enroll();
    expect(controller.stage, MfaStage.blocked);
    verifyNever(() => fixture.auth.enrollTotp());
  });

  test(
    'only verified TOTP factors are selectable; invalid selection ignored',
    () async {
      fixture.factors = [
        factor(id: 'pending', status: FactorStatus.unverified),
        factor(id: 'first'),
        factor(id: 'second'),
      ];
      await controller.load();
      expect(controller.factors.map((f) => f.id), ['first', 'second']);
      expect(controller.factorId, 'first');
      controller.selectFactor('pending');
      expect(controller.factorId, 'first');
      controller.selectFactor('second');
      await controller.verify('123456', onVerified: fixture.revalidate);
      verify(
        () => fixture.auth.verifyTotp(factorId: 'second', code: '123456'),
      ).called(1);
      expect(fixture.revalidations, 1);
    },
  );

  for (final type in [
    FactorType.unknown,
    FactorType.phone,
    FactorType.webauthn,
  ]) {
    test(
      'unsupported $type fails closed even alongside verified TOTP',
      () async {
        fixture.factors = [factor(), factor(id: 'unsupported', type: type)];
        await controller.load();
        expect(controller.stage, MfaStage.blocked);
        expect(controller.canVerify, false);
        expect(controller.canEnroll, false);
      },
    );
  }

  for (final invalid in [
    [factor(status: FactorStatus.unknown)],
    [factor(id: '')],
    [factor(), factor()],
    [factor(status: FactorStatus.unverified)],
  ]) {
    test(
      'invalid/unfinished factor list ${invalid.first.status}/${invalid.length}/${invalid.first.id} blocks',
      () async {
        fixture.factors = invalid;
        await controller.load();
        expect(controller.stage, MfaStage.blocked);
        await controller.enroll();
        verifyNever(() => fixture.auth.enrollTotp());
      },
    );
  }

  test(
    'null assurance fails closed; AAL2 is never evidence of Home access',
    () async {
      fixture.level = null;
      await controller.load();
      expect(controller.stage, MfaStage.blocked);
      expect(fixture.revalidations, 0);
    },
  );

  test(
    'AAL2 without a verified factor cannot start enrollment or bypass challenge',
    () async {
      fixture.level = AuthenticatorAssuranceLevels.aal2;
      await controller.load();
      expect(controller.stage, MfaStage.blocked);
      expect(fixture.revalidations, 0);
    },
  );

  test('AAL2 with verified factor still requires explicit challenge', () async {
    fixture.level = AuthenticatorAssuranceLevels.aal2;
    await challenge();
    expect(controller.stage, MfaStage.challenge);
    expect(fixture.revalidations, 0);
  });

  test(
    'duplicate loads coalesce; reload failure clears stale selection',
    () async {
      await challenge();
      final pending = Completer<AuthMFAListFactorsResponse>();
      when(() => fixture.auth.listMfaFactors()).thenAnswer((_) {
        fixture.refreshForLoad();
        return pending.future;
      });
      final first = controller.load();
      expect(controller.load(), same(first));
      expect(controller.canVerify, false);
      pending.completeError(StateError('private-provider-detail'));
      await first;
      expect(controller.factorId, null);
      expect(controller.canLoad, true);
      expect(controller.message, isNot(contains('private-provider-detail')));
    },
  );

  test(
    'explicit enrollment coalesces and never repeats after dispatch',
    () async {
      await controller.load();
      final pending = Completer<AuthMFAEnrollResponse>();
      when(() => fixture.auth.enrollTotp()).thenAnswer((_) => pending.future);
      final first = controller.enroll();
      expect(controller.enroll(), same(first));
      expect(controller.load(), same(first));
      pending.complete(enrollment);
      await first;
      expect(controller.setup, enrollment.totp);
      expect(controller.stage, MfaStage.setup);
      await controller.enroll();
      await controller.load();
      verify(() => fixture.auth.enrollTotp()).called(1);
    },
  );

  test('unknown enroll failure has no retry or raw error/secret', () async {
    await controller.load();
    when(
      () => fixture.auth.enrollTotp(),
    ).thenThrow(StateError(enrollment.totp!.secret));
    await controller.enroll();
    await controller.load();
    await controller.enroll();
    expect(controller.stage, MfaStage.blocked);
    expect(controller.setup, null);
    expect(controller.message, isNot(contains(enrollment.totp!.secret)));
    verify(() => fixture.auth.enrollTotp()).called(1);
  });

  for (final response in [
    const AuthMFAEnrollResponse(id: 'unknown', type: FactorType.unknown),
    const AuthMFAEnrollResponse(id: 'missing', type: FactorType.totp),
    AuthMFAEnrollResponse(id: '', type: FactorType.totp, totp: enrollment.totp),
    const AuthMFAEnrollResponse(
      id: 'bad-uri',
      type: FactorType.totp,
      totp: TOTPEnrollment(
        qrCode: '',
        secret: 'fixture',
        uri: 'https://example.invalid',
      ),
    ),
  ]) {
    test(
      'malformed enrollment ${response.id} is not presented or retried',
      () async {
        await controller.load();
        when(() => fixture.auth.enrollTotp()).thenAnswer((_) async => response);
        await controller.enroll();
        expect(controller.stage, MfaStage.blocked);
        expect(controller.setup, null);
        expect(controller.canVerify, false);
      },
    );
  }

  test('validation requires exactly six ASCII digits', () async {
    await challenge();
    for (final code in [
      '',
      '12345',
      '1234567',
      ' 123456',
      'abcdef',
      '１２３４５６',
    ]) {
      await controller.verify(code, onVerified: fixture.revalidate);
    }
    verifyNever(
      () => fixture.auth.verifyTotp(
        factorId: any(named: 'factorId'),
        code: any(named: 'code'),
      ),
    );
    expect(fixture.revalidations, 0);
  });

  test('verify failure permits explicit retry without enrollment', () async {
    await challenge();
    when(
      () => fixture.auth.verifyTotp(
        factorId: any(named: 'factorId'),
        code: any(named: 'code'),
      ),
    ).thenThrow(const AuthException('private-code-detail'));
    await controller.verify('123456', onVerified: fixture.revalidate);
    expect(controller.canVerify, true);
    expect(controller.message, isNot(contains('private-code-detail')));
    expect(fixture.revalidations, 0);
  });

  test(
    'verify coalesces, accepts guarded adoption, awaits revalidation and clears setup',
    () async {
      await controller.load();
      await controller.enroll();
      final pending = Completer<AuthMFAVerifyResponse>();
      final check = Completer<void>();
      final callbackStarted = Completer<void>();
      when(
        () => fixture.auth.verifyTotp(
          factorId: any(named: 'factorId'),
          code: any(named: 'code'),
        ),
      ).thenAnswer((_) => pending.future);
      final first = controller.verify(
        '123456',
        onVerified: () {
          fixture.revalidations++;
          callbackStarted.complete();
          return check.future;
        },
      );
      expect(
        controller.verify('654321', onVerified: fixture.revalidate),
        same(first),
      );
      pending.complete(fixture.adopt());
      await callbackStarted.future;
      expect(fixture.revalidations, 1);
      expect(controller.setup, null);
      expect(controller.isBusy, true);
      expect(controller.stage, MfaStage.verified);
      check.complete();
      await first;
      expect(controller.canVerify, false);
      verify(
        () => fixture.auth.verifyTotp(factorId: 'new-totp', code: '123456'),
      ).called(1);
    },
  );

  test('callback failure retries only revalidation, not verify', () async {
    await challenge();
    await controller.verify(
      '123456',
      onVerified: () async {
        throw StateError('private');
      },
    );
    expect(controller.stage, MfaStage.verified);
    expect(controller.canRevalidate, true);
    expect(controller.message, contains('account access could not be checked'));
    await controller.revalidate(onVerified: fixture.revalidate);
    expect(fixture.revalidations, 1);
    verify(
      () => fixture.auth.verifyTotp(factorId: 'verified-totp', code: '123456'),
    ).called(1);
  });

  test(
    'unadopted or mismatched verify response never calls revalidation',
    () async {
      await challenge();
      when(
        () => fixture.auth.verifyTotp(
          factorId: any(named: 'factorId'),
          code: any(named: 'code'),
        ),
      ).thenAnswer(
        (_) async => AuthMFAVerifyResponse(
          accessToken: 'other',
          tokenType: 'bearer',
          expiresIn: const Duration(hours: 1),
          refreshToken: 'unused',
          user: session(user: 'other').user,
        ),
      );
      await controller.verify('123456', onVerified: fixture.revalidate);
      expect(controller.stage, MfaStage.blocked);
      expect(fixture.revalidations, 0);
    },
  );

  for (final action in ['load', 'enroll', 'verify']) {
    for (final invalidation in [
      'switch',
      'aba',
      'dispose',
      'dismiss',
      'refresh',
      'silent',
    ]) {
      test('$action rejects late completion after $invalidation', () async {
        final pending = Completer<dynamic>();
        if (action == 'enroll') await controller.load();
        if (action == 'verify') await challenge();
        when(() => fixture.auth.listMfaFactors()).thenAnswer((_) async {
          fixture.refreshForLoad();
          return await pending.future as AuthMFAListFactorsResponse;
        });
        when(() => fixture.auth.enrollTotp()).thenAnswer(
          (_) async => await pending.future as AuthMFAEnrollResponse,
        );
        when(
          () => fixture.auth.verifyTotp(
            factorId: any(named: 'factorId'),
            code: any(named: 'code'),
          ),
        ).thenAnswer(
          (_) async => await pending.future as AuthMFAVerifyResponse,
        );
        final request = switch (action) {
          'load' => controller.load(),
          'enroll' => controller.enroll(),
          _ => controller.verify('123456', onVerified: fixture.revalidate),
        };
        final original = fixture.current;
        switch (invalidation) {
          case 'dispose':
            controller.dispose();
          case 'dismiss':
            controller.dismiss();
          case 'silent':
            fixture.current = session(user: 'account-b');
          case 'refresh':
            fixture.emit(AuthChangeEvent.signedIn, session(token: 'new-login'));
          default:
            fixture.emit(AuthChangeEvent.signedIn, session(user: 'account-b'));
            if (invalidation == 'aba') {
              fixture.emit(AuthChangeEvent.signedIn, original);
            }
        }
        final result = switch (action) {
          'load' => fixture.factorResponse,
          'enroll' => enrollment,
          _ => AuthMFAVerifyResponse(
            accessToken: original!.accessToken,
            tokenType: 'bearer',
            expiresIn: const Duration(hours: 1),
            refreshToken: 'unused',
            user: original.user,
          ),
        };
        pending.complete(result);
        await request;
        expect(controller.stage, MfaStage.expired);
        expect(controller.setup, null);
        expect(controller.factorId, null);
        expect(fixture.revalidations, 0);
      });
    }
  }

  test(
    'late failure after A-B-A does not resurrect error or secrets',
    () async {
      await controller.load();
      final pending = Completer<AuthMFAEnrollResponse>();
      when(() => fixture.auth.enrollTotp()).thenAnswer((_) => pending.future);
      final request = controller.enroll();
      final original = fixture.current;
      fixture.emit(AuthChangeEvent.signedIn, session(user: 'b'));
      fixture.emit(AuthChangeEvent.signedIn, original);
      pending.completeError(StateError('private'));
      await request;
      expect(controller.message, null);
      expect(controller.setup, null);
      expect(controller.stage, MfaStage.expired);
    },
  );

  test('stream error and closure fail closed', () async {
    await controller.load();
    await controller.enroll();
    fixture.events.addError(StateError('private'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.setup, null);
    expect(controller.stage, MfaStage.expired);
    await fixture.events.close();
  });

  test(
    'ordinary token refresh invalidates setup instead of retaining its secret',
    () async {
      await controller.load();
      await controller.enroll();
      fixture.emit(AuthChangeEvent.tokenRefreshed, session(token: 'refreshed'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.setup, null);
      expect(controller.stage, MfaStage.expired);
    },
  );
}
