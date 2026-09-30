import 'package:clean_stream_laundry_app/services/supabase/mfa_verification_client.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthService implements AuthService {
  late final SupabaseClient _client;
  final MfaVerificationClient Function(String accessToken)? _mfaClientFactory;
  bool _mfaVerificationPending = false;
  String? lastSignedUpUserId;

  SupabaseAuthService({
    required SupabaseClient client,
    MfaVerificationClient Function(String accessToken)? mfaClientFactory,
  }) : _mfaClientFactory = mfaClientFactory {
    _client = client;
  }

  @override
  String? get getCurrentUserId {
    return _client.auth.currentUser?.id;
  }

  @override
  String getLastSignedUpUserId() {
    return lastSignedUpUserId!;
  }

  @override
  Future<AuthenticationResponses> isLoggedIn() async {
    AuthenticationResponses output = AuthenticationResponses.success;
    final session = _client.auth.currentSession;

    if (session == null) {
      output = AuthenticationResponses.failure;
    }

    return output;
  }

  @override
  Future<AuthenticationResponses> login(String email, String password) async {
    AuthenticationResponses output = AuthenticationResponses.failure;
    try {
      final AuthResponse response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user == null) {
        output = AuthenticationResponses.failure;
      } else {
        output = AuthenticationResponses.success;
      }
    } on AuthApiException catch (e) {
      if (e.code == 'email_not_confirmed') {
        output = AuthenticationResponses.emailNotVerified;
      } else {
        print(e.message);
      }
    } catch (e) {
      print(e);
    }

    return output;
  }

  @override
  Future<void> logout() async {
    await _client.auth.signOut();
  }

  @override
  Future<AuthenticationResponses> signUp(
    String email,
    String password,
    String name,
  ) async {
    AuthenticationResponses output = AuthenticationResponses.failure;
    AuthenticationResponses validatePasswordResponse = _validatePassword(
      password,
    );

    if (validatePasswordResponse == AuthenticationResponses.success) {
      final AuthResponse response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {"full_name": name},
      );

      if (response.user != null) {
        lastSignedUpUserId = response.user!.id;
        try {
          await _client.auth.resend(type: OtpType.signup, email: email);
        } catch (e) {
          print('Error sending verification OTP: $e');
        }
        output = AuthenticationResponses.success;
      }
    } else {
      output = validatePasswordResponse;
    }

    return output;
  }

  AuthenticationResponses _validatePassword(String password) {
    AuthenticationResponses output = AuthenticationResponses.success;

    bool hasDigit = false;
    bool hasUpper = false;
    bool hasSpecialCharacter = false;

    var validSpecialCharacters = [
      '!',
      '@',
      '#',
      r'$',
      '%',
      '^',
      '&',
      '*',
      '(',
      ')',
      '_',
      '+',
      '-',
      '=',
      '[',
      ']',
      '{',
      '}',
      ';',
      ':',
      "'",
      ',',
      '.',
      '?',
      '/',
    ];

    if (password.length >= 8) {
      for (String ch in password.split('')) {
        if (int.tryParse(ch) != null) {
          hasDigit = true;
        } else if (validSpecialCharacters.contains(ch)) {
          hasSpecialCharacter = true;
        } else if (ch == ch.toUpperCase() && ch != ch.toLowerCase()) {
          hasUpper = true;
        }
      }
    } else {
      return AuthenticationResponses.lessThanMinLength;
    }

    if (!hasDigit) {
      output = AuthenticationResponses.noDigit;
    } else if (!hasUpper) {
      output = AuthenticationResponses.noUppercase;
    } else if (!hasSpecialCharacter) {
      output = AuthenticationResponses.noSpecialCharacter;
    }

    return output;
  }

  @override
  Future<AuthenticationResponses> resendVerification({String? email}) async {
    AuthenticationResponses output = AuthenticationResponses.success;

    final userEmail = email ?? _client.auth.currentUser?.email;

    try {
      if (userEmail != null) {
        await _client.auth.resend(type: OtpType.signup, email: userEmail);
      } else {
        output = AuthenticationResponses.failure;
      }
    } catch (e) {
      output = AuthenticationResponses.failure;
    }

    return output;
  }

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Stream<bool> get onAuthChange {
    return _client.auth.onAuthStateChange.map((tuple) {
      final session = tuple.session;
      return session?.user != null;
    });
  }

  @override
  bool isEmailVerified() {
    return _client.auth.currentUser?.emailConfirmedAt != null;
  }

  String get _webOAuthRedirect {
    final document = Uri.base;
    // The app uses Flutter's default hash routing, including embedded basepaths.
    return Uri.parse(document.origin)
        .replace(path: document.path, fragment: '/loading')
        .toString();
  }

  @override
  Future<void> appleSignIn() async {
    if (!kIsWeb) {
      try {
        await _client.auth.signInWithOAuth(
          OAuthProvider.apple,
          redirectTo: "clean-stream://oauth",
        );
      } catch (e) {}
    } else {
      await _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: _webOAuthRedirect,
      );
    }
  }

  @override
  Future<void> googleSignIn() async {
    if (!kIsWeb) {
      try {
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: "clean-stream://oauth",
        );
      } catch (e) {}
    } else {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _webOAuthRedirect,
      );
    }
  }

  @override
  Future<void> getSessionFromURI(Uri uri) async {
    await _client.auth.getSessionFromUrl(uri);
  }

  User? getCurrentUser() {
    return _client.auth.currentUser;
  }

  @override
  Future<void> refreshSession() async {
    final session = _client.auth.currentSession;
    if (session != null) {
      await _client.auth.refreshSession();
    }
  }

  @override
  String? getCurrentUserEmail() {
    return _client.auth.currentUser?.email;
  }

  @override
  Future<void> updateUserAttributes({
    String? email,
    Map<String, dynamic>? data,
  }) async {
    final response = await _client.auth.updateUser(
      UserAttributes(email: email, data: data),
      emailRedirectTo: "clean-stream://change-email",
    );

    if (response.user == null) {
      throw Exception("Failed to update user attributes");
    }
  }

  @override
  Future<AuthenticationResponses> resetPassword(String email) async {
    AuthenticationResponses output = AuthenticationResponses.failure;
    try {
      // Send password reset email and redirect back to the app via deep link.
      await _client.auth.resetPasswordForEmail(email);
      output = AuthenticationResponses.success;
    } catch (e) {
      print('resetPassword error: $e');
      output = AuthenticationResponses.failure;
    }
    return output;
  }

  @override
  Future<AuthenticationResponses> exchangeCodeForSession(String code) async {
    AuthenticationResponses output = AuthenticationResponses.failure;
    try {
      await _client.auth.exchangeCodeForSession(code);
      output = AuthenticationResponses.success;
    } catch (e) {
      output = AuthenticationResponses.failure;
    }
    return output;
  }

  @override
  Future<AuthenticationResponses> updatePassword(String newPassword) async {
    AuthenticationResponses output = AuthenticationResponses.failure;
    try {
      await _client.auth.updateUser(
        UserAttributes(password: newPassword.trim()),
      );
      output = AuthenticationResponses.success;
    } catch (e) {
      output = AuthenticationResponses.failure;
    }
    return output;
  }

  @override
  Future<AuthenticationResponses> verifyCode({
    required String email,
    required String code,
  }) async {
    AuthenticationResponses output = AuthenticationResponses.success;

    try {
      final response = await _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.recovery,
      );

      if (response.session == null) {
        output = AuthenticationResponses.failure;
      }
    } catch (e) {
      output = AuthenticationResponses.failure;
    }

    return output;
  }

  @override
  Future<AuthenticationResponses> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    AuthenticationResponses output = AuthenticationResponses.success;

    try {
      final response = await _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.signup,
      );

      if (response.session == null) {
        output = AuthenticationResponses.failure;
      }
    } catch (e) {
      output = AuthenticationResponses.failure;
    }

    return output;
  }

  @override
  Future<AuthMFAListFactorsResponse> listMfaFactors() =>
      _client.auth.mfa.listFactors();

  @override
  AuthMFAGetAuthenticatorAssuranceLevelResponse getMfaAssurance() =>
      _client.auth.mfa.getAuthenticatorAssuranceLevel();

  @override
  Future<AuthMFAEnrollResponse> enrollTotp({String? friendlyName}) =>
      _client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'Clean Stream Laundry',
        friendlyName: friendlyName,
      );

  @override
  Future<AuthMFAVerifyResponse> verifyTotp({
    required String factorId,
    required String code,
  }) async {
    if (_mfaVerificationPending) {
      throw const AuthException('MFA verification is already in progress.');
    }
    final auth = _client.auth;
    final captured = auth.currentSession;
    void requireCapturedSession() {
      if (captured == null ||
          !identical(auth.currentSession, captured) ||
          captured.expiresAt == null ||
          captured.isExpired) {
        throw const AuthException(
          'MFA verification requires the original active session.',
        );
      }
    }

    requireCapturedSession();
    final accessToken = captured!.accessToken;
    _mfaVerificationPending = true;
    MfaVerificationClient? isolated;
    try {
      isolated = _mfaClientFactory?.call(accessToken);
      if (isolated == null) {
        throw const AuthException('Isolated MFA client is not configured.');
      }
      requireCapturedSession();
      final challenge = await isolated.challenge(factorId: factorId);
      requireCapturedSession();
      final verified = await isolated.verify(
        factorId: factorId,
        challengeId: challenge.id,
        code: code,
      );
      requireCapturedSession();
      final verifiedSession = Session(
        accessToken: verified.accessToken,
        tokenType: verified.tokenType,
        user: verified.user,
        expiresIn: verified.expiresIn.inSeconds,
        refreshToken: verified.refreshToken,
      );
      if (verified.user.id != captured.user.id ||
          verifiedSession.expiresAt == null ||
          verifiedSession.isExpired ||
          decodeJwt(verified.accessToken).payload.claims['aal'] != 'aal2') {
        throw const AuthException(
          'MFA verification did not produce an active AAL2 session.',
        );
      }

      // Requires gotrue 2.27.2's session-version guard. Do not pass accessToken:
      // that takes a different SDK path without the guarded refresh adoption.
      final adoptionEvents = <AuthState>[];
      var adoptionStreamError = false;
      final subscription = auth.onAuthStateChange.listen((state) {
        if (!identical(state.session, captured)) adoptionEvents.add(state);
      }, onError: (Object _) => adoptionStreamError = true);
      final AuthResponse adopted;
      try {
        adopted = await auth.setSession(verified.refreshToken);
        // Drain queued public events: the SDK can return an already-current
        // session on refresh-token reuse without actually committing adoption.
        await Future<void>.delayed(Duration.zero);
      } finally {
        await subscription.cancel();
      }
      final committed = auth.currentSession;
      if (committed == null ||
          identical(committed, captured) ||
          !identical(committed, adopted.session) ||
          committed.user.id != captured.user.id ||
          committed.expiresAt == null ||
          committed.isExpired ||
          adoptionStreamError ||
          adoptionEvents.length != 1 ||
          adoptionEvents.single.event != AuthChangeEvent.tokenRefreshed ||
          !identical(adoptionEvents.single.session, committed) ||
          auth.mfa.getAuthenticatorAssuranceLevel().currentLevel !=
              AuthenticatorAssuranceLevels.aal2) {
        throw const AuthException('MFA session adoption was not committed.');
      }
      return AuthMFAVerifyResponse.fromJson(committed.toJson());
    } finally {
      _mfaVerificationPending = false;
      isolated?.dispose();
    }
  }
}
