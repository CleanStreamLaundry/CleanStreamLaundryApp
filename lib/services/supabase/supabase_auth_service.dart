import 'dart:convert';

import 'package:clean_stream_laundry_app/services/supabase/mfa_verification_client.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthService implements AuthService {
  late final SupabaseClient _client;
  final MfaVerificationClient Function(String accessToken)? _mfaClientFactory;
  final GoogleSignIn _googleSignIn;
  final GoTrueClient Function()? _nativeAuthClientFactory;
  int _authAttempt = 0;
  Future<void>? _googleInitialization;
  static const _googleServerClientId =
      '444847125705-mdbtsvhd1ks8n8j061u5gogvi5c1ro54.apps.googleusercontent.com';
  bool _mfaVerificationPending = false;
  String? lastSignedUpUserId;

  SupabaseAuthService({
    required SupabaseClient client,
    MfaVerificationClient Function(String accessToken)? mfaClientFactory,
    GoogleSignIn? googleSignIn,
    // Retain the existing DI argument; this isolated factory serves both providers.
    GoTrueClient Function()? googleAuthClientFactory,
  }) : _mfaClientFactory = mfaClientFactory,
       _nativeAuthClientFactory = googleAuthClientFactory,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance {
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
    cancelGoogleSignIn();
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
    cancelGoogleSignIn();
    await _client.auth.signOut();
  }

  @override
  Future<AuthenticationResponses> signUp(
    String email,
    String password,
    String name,
  ) async {
    cancelGoogleSignIn();
    AuthenticationResponses output = AuthenticationResponses.failure;
    AuthenticationResponses validatePasswordResponse = _validatePassword(
      password,
    );

    if (validatePasswordResponse == AuthenticationResponses.success) {
      final AuthResponse response;
      try {
        response = await _client.auth.signUp(
          email: email,
          password: password,
          data: {"full_name": name},
        );
      } on AuthWeakPasswordException catch (e) {
        return e.reasons.contains('pwned')
            ? AuthenticationResponses.compromisedPassword
            : AuthenticationResponses.weakPassword;
      }

      if (response.user != null) {
        lastSignedUpUserId = response.user!.id;
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
    return Uri.parse(
      document.origin,
    ).replace(path: document.path, fragment: '/loading').toString();
  }

  @override
  Future<bool> appleSignIn() async {
    final attempt = ++_authAttempt;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb ? _webOAuthRedirect : 'clean-stream://oauth',
      );
      if (!launched) {
        throw const AuthException('Unable to open Apple sign-in.');
      }
      return false; // The existing deep-link handler completes browser OAuth.
    }

    final previousSession = _client.auth.currentSession;
    void requireCurrentAttempt() {
      if (attempt != _authAttempt ||
          !identical(_client.auth.currentSession, previousSession)) {
        throw const AuthException('The active account changed during sign-in.');
      }
    }

    final rawNonce = _client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      requireCurrentAttempt();
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('Apple did not return an ID token.');
      }
      final isolated = _nativeAuthClientFactory?.call();
      if (isolated == null) {
        throw const AuthException('Native Apple sign-in is not configured.');
      }
      try {
        final response = await isolated.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        );
        requireCurrentAttempt();
        final fullName = [credential.givenName, credential.familyName]
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .join(' ');
        // Apple supplies names only on first consent, outside the ID token.
        // Bind the metadata write to the isolated Apple session, not a new login.
        if (response.session != null && fullName.isNotEmpty) {
          await isolated.updateUser(
            UserAttributes(data: {'full_name': fullName}),
          );
        }
        requireCurrentAttempt();
        await _adoptNativeSession(
          isolated.currentSession,
          previousSession: previousSession,
          attempt: attempt,
          provider: 'Apple',
        );
      } finally {
        isolated.dispose();
      }
      return true;
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return false;
      rethrow;
    }
  }

  @override
  Future<bool> googleSignIn() async {
    final attempt = ++_authAttempt;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? _webOAuthRedirect : 'clean-stream://oauth',
      );
      if (!launched) {
        throw const AuthException('Unable to open Google sign-in.');
      }
      return false; // The existing deep-link handler completes browser OAuth.
    }

    final previousSession = _client.auth.currentSession;
    void requireCurrentAttempt() {
      if (attempt != _authAttempt ||
          !identical(_client.auth.currentSession, previousSession)) {
        throw const AuthException('The active account changed during sign-in.');
      }
    }

    _googleInitialization ??= _googleSignIn.initialize(
      serverClientId: _googleServerClientId,
    );
    try {
      await _googleInitialization;
    } catch (_) {
      _googleInitialization = null;
      rethrow;
    }
    try {
      const scopes = ['email', 'profile'];
      final account = await _googleSignIn.authenticate(scopeHint: scopes);
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('Google did not return an ID token.');
      }
      final authorization =
          await account.authorizationClient.authorizationForScopes(scopes) ??
          await account.authorizationClient.authorizeScopes(scopes);
      requireCurrentAttempt();
      final isolated = _nativeAuthClientFactory?.call();
      if (isolated == null) {
        throw const AuthException('Native Google sign-in is not configured.');
      }
      try {
        final response = await isolated.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: authorization.accessToken,
        );
        requireCurrentAttempt();
        await _adoptNativeSession(
          response.session,
          previousSession: previousSession,
          attempt: attempt,
          provider: 'Google',
        );
      } finally {
        isolated.dispose();
      }
      return true;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
  }

  Future<void> _adoptNativeSession(
    Session? session, {
    required Session? previousSession,
    required int attempt,
    required String provider,
  }) async {
    if (session == null ||
        session.refreshToken == null ||
        session.refreshToken!.isEmpty ||
        session.expiresAt == null ||
        session.expiresAt! <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60) {
      throw AuthException('$provider sign-in did not create a session.');
    }
    if (previousSession?.user.id == session.user.id) {
      // recoverSession omits events for the same user. The pinned SDK's
      // refresh adoption is session-version guarded and persists the result.
      final adopted = await _client.auth.setSession(session.refreshToken!);
      if (!identical(_client.auth.currentSession, adopted.session) ||
          attempt != _authAttempt) {
        throw const AuthException('The active account changed during sign-in.');
      }
    } else {
      // Native only: no browser broadcast. Fresh recovery commits before
      // any await; the expiry headroom above excludes its refresh branch.
      final adopted = await _client.auth.recoverSession(
        jsonEncode(session.toJson()),
      );
      if (!identical(_client.auth.currentSession, adopted.session) ||
          attempt != _authAttempt) {
        throw const AuthException('The active account changed during sign-in.');
      }
    }
  }

  @override
  void cancelAppleSignIn() => _authAttempt++;

  @override
  void cancelGoogleSignIn() => _authAttempt++;

  @override
  Future<void> getSessionFromURI(Uri uri) async {
    cancelGoogleSignIn();
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
    cancelGoogleSignIn();
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
    } on AuthWeakPasswordException catch (e) {
      output = e.reasons.contains('pwned')
          ? AuthenticationResponses.compromisedPassword
          : AuthenticationResponses.weakPassword;
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
    cancelGoogleSignIn();
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
    cancelGoogleSignIn();
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
