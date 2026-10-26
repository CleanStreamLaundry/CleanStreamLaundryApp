import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthService {
  Future<AuthenticationResponses> login(String email, String password);
  Future<AuthenticationResponses> signUp(
    String email,
    String password,
    String name,
  );
  Future<void> logout();
  Future<AuthenticationResponses> isLoggedIn();
  String? get getCurrentUserId;
  String getLastSignedUpUserId();
  Future<AuthenticationResponses> resendVerification({String? email});
  Stream<bool> get onAuthChange;
  Session? get currentSession;
  Stream<AuthState> get authStateChanges;
  bool isEmailVerified();
  Future<AuthenticationResponses> resetPassword(String email);
  /// True only after native sign-in establishes a Supabase session.
  Future<bool> appleSignIn();
  void cancelAppleSignIn();

  /// True only after native sign-in establishes a Supabase session.
  Future<bool> googleSignIn();
  void cancelGoogleSignIn();
  Future<void> getSessionFromURI(Uri uri);
  Future<void> refreshSession();
  User? getCurrentUser();
  String? getCurrentUserEmail();
  Future<void> updateUserAttributes({
    String? email,
    Map<String, dynamic>? data,
  });
  Future<AuthenticationResponses> exchangeCodeForSession(String code);
  Future<AuthenticationResponses> updatePassword(String newPassword);
  Future<AuthenticationResponses> verifyCode({
    required String email,
    required String code,
  });
  Future<AuthenticationResponses> verifyEmailCode({
    required String email,
    required String code,
  });
  Future<AuthMFAListFactorsResponse> listMfaFactors();
  AuthMFAGetAuthenticatorAssuranceLevelResponse getMfaAssurance();
  Future<AuthMFAEnrollResponse> enrollTotp({String? friendlyName});
  Future<AuthMFAVerifyResponse> verifyTotp({
    required String factorId,
    required String code,
  });
}
