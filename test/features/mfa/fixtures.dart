import 'dart:async';

import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockMfaAuth extends Mock implements AuthService {}

Session session({String user = 'account-a', String token = 'aal1'}) =>
    Session(
        accessToken: token,
        refreshToken: 'fixture-refresh',
        tokenType: 'bearer',
        expiresIn: 3600,
        user: User(
          id: user,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      )
      ..expiresAt =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;

Factor factor({
  String id = 'verified-totp',
  FactorType type = FactorType.totp,
  FactorStatus status = FactorStatus.verified,
}) => Factor(
  id: id,
  friendlyName: 'Fixture authenticator',
  factorType: type,
  status: status,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

const enrollment = AuthMFAEnrollResponse(
  id: 'new-totp',
  type: FactorType.totp,
  totp: TOTPEnrollment(
    qrCode: '',
    secret: 'JBSWY3DPEHPK3PXP',
    uri:
        'otpauth://totp/Clean%20Stream%20Laundry:fixture?secret=JBSWY3DPEHPK3PXP&issuer=Clean%20Stream%20Laundry',
  ),
);

class MfaFixture {
  final auth = MockMfaAuth();
  final events = StreamController<AuthState>.broadcast();
  Session? current = session();
  List<Factor> factors = [];
  AuthenticatorAssuranceLevels? level = AuthenticatorAssuranceLevels.aal1;
  int revalidations = 0;
  int listRefreshes = 0;

  MfaFixture() {
    when(() => auth.currentSession).thenAnswer((_) => current);
    when(() => auth.authStateChanges).thenAnswer((_) => events.stream);
    when(() => auth.listMfaFactors()).thenAnswer((_) async {
      refreshForLoad();
      return factorResponse;
    });
    when(() => auth.getMfaAssurance()).thenAnswer(
      (_) => AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: level,
        nextLevel: factors.any((f) => f.status == FactorStatus.verified)
            ? AuthenticatorAssuranceLevels.aal2
            : level,
        currentAuthenticationMethods: [],
      ),
    );
    when(() => auth.enrollTotp()).thenAnswer((_) async => enrollment);
    when(
      () => auth.verifyTotp(
        factorId: any(named: 'factorId'),
        code: any(named: 'code'),
      ),
    ).thenAnswer((_) async => adopt());
  }

  AuthMFAListFactorsResponse get factorResponse => AuthMFAListFactorsResponse(
    all: factors,
    totp: factors
        .where(
          (f) =>
              f.factorType == FactorType.totp &&
              f.status == FactorStatus.verified,
        )
        .toList(),
    phone: [],
  );

  void emit(AuthChangeEvent event, Session? value) {
    current = value;
    events.add(AuthState(event, value));
  }

  void refreshForLoad() {
    emit(
      AuthChangeEvent.tokenRefreshed,
      session(user: current!.user.id, token: 'listed-${++listRefreshes}'),
    );
  }

  AuthMFAVerifyResponse adopt() {
    level = AuthenticatorAssuranceLevels.aal2;
    final adopted = session(user: current!.user.id, token: 'adopted-aal2');
    emit(AuthChangeEvent.tokenRefreshed, adopted);
    return AuthMFAVerifyResponse(
      accessToken: adopted.accessToken,
      tokenType: 'bearer',
      expiresIn: const Duration(hours: 1),
      refreshToken: 'fixture-refresh',
      user: adopted.user,
    );
  }

  Future<void> revalidate() async {
    revalidations++;
  }

  Future<void> close() => events.close();
}
