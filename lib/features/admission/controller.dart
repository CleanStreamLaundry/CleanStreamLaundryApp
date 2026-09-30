import 'dart:async';

import 'package:clean_stream_laundry_app/logic/models/admission_status.dart';
import 'package:clean_stream_laundry_app/logic/models/loyalty_policy_status.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdmissionController extends ChangeNotifier {
  static const responseWait = Duration(seconds: 10);
  // Match the installed GoTrue session expiry margin without importing internals.
  static const _expiryMargin = Duration(seconds: 30);

  final AuthService _auth;
  final ProfileService _profiles;
  final DateTime Function() _now;
  late final StreamSubscription<AuthState> _subscription;
  Timer? _expiryTimer;
  Session? _session;
  AdmissionStatus? _status;
  Object? _error;
  Future<void>? _request;
  int _generation = 0;
  int? _requestedGeneration;
  bool _retainPresentation = false;
  bool _disposed = false;
  bool _streamClosed = false;
  LoyaltyPolicyStatus? _policy;
  Object? _policyError;
  Future<void>? _policyRequest;
  int? _policyGeneration;
  int _policyAttempt = 0;
  bool _policyConsent = false;
  bool _acceptingPolicy = false;

  AdmissionController({
    required AuthService authService,
    required ProfileService profileService,
    DateTime Function()? now,
  }) : _auth = authService,
       _profiles = profileService,
       _now = now ?? DateTime.now {
    _session = _auth.currentSession;
    _armExpiry();
    _subscription = _auth.authStateChanges.listen(
      _onAuthState,
      onError: (Object error) => _fail(error),
      onDone: () {
        _streamClosed = true;
        invalidate();
      },
    );
  }

  AdmissionStatus? get status => _isCurrent ? _status : null;
  Object? get error => _error;
  int get generation => _generation;
  bool get isChecking => !_disposed && _request != null;
  bool get canEnterHome => !isChecking && status?.nextStep == 'home';
  bool get canUseMaintenance =>
      !isChecking &&
      status?.accountAccess == 'eligible' &&
      const ['home', 'review_terms'].contains(status?.nextStep);

  bool get canUseTopupRefunds => !isChecking && _allowsTopupRefunds(status);

  bool _allowsTopupRefunds(AdmissionStatus? value) =>
      value != null &&
      ((value.accountAccess == 'eligible' &&
              const ['home', 'review_terms'].contains(value.nextStep)) ||
          (value.accountState == 'pending_deletion' &&
              value.accountAccess == 'restricted' &&
              value.nextStep == 'blocked' &&
              const [
                'explicit_restore_required',
                'restore_expired',
              ].contains(value.reason)));

  /// Presentation only; never permission to start a read or mutation.
  bool get retainSafePresentation => _isCurrent && _retainPresentation;

  LoyaltyPolicyDescriptor? get policyDescriptor => _policy?.descriptor;
  Object? get policyError => _policyError;
  bool get isLoadingPolicy => !_disposed && _policyRequest != null;
  bool get isAcceptingPolicy => isLoadingPolicy && _acceptingPolicy;
  bool get canReviewPolicy =>
      !isChecking && !isLoadingPolicy && status?.nextStep == 'review_terms';
  bool get canConsentToPolicy =>
      canReviewPolicy &&
      _policyGeneration == _generation &&
      _policyError == null &&
      _policy?.acceptanceRequired == true;
  bool get policyConsent => canConsentToPolicy && _policyConsent;
  bool get canAcceptPolicy => policyConsent;

  void setPolicyConsent(bool value) {
    if (_disposed) return;
    _policyConsent = canConsentToPolicy && value;
    notifyListeners();
  }

  Future<void> loadPolicy() => _requestPolicy(accept: false);
  Future<void> acceptPolicy() => _requestPolicy(accept: true);

  // Leaving the page invalidates its completion, not an already dispatched write.
  void dismissPolicy() => _clearPolicy();

  void _clearPolicy({bool keepDocument = false}) {
    _policyAttempt++;
    _policyGeneration = null;
    _policyConsent = false;
    _policyError = null;
    if (!keepDocument) _policy = null;
  }

  Future<void> _requestPolicy({required bool accept}) {
    if (_disposed) return Future.value();
    if (_policyRequest != null) return _policyRequest!;
    if (!canReviewPolicy || (accept && !canAcceptPolicy)) return Future.value();
    final session = _session!;
    final generation = _generation;
    final attempt = ++_policyAttempt;
    final displayed = _policy?.descriptor;
    bool isCurrent() =>
        !_disposed &&
        attempt == _policyAttempt &&
        generation == _generation &&
        _isCurrent &&
        _sameSession(session, _session);
    final completion = Completer<void>();
    _policyRequest = completion.future;
    _acceptingPolicy = accept;
    _policyConsent = false;
    _policyError = null;
    notifyListeners();
    unawaited(() async {
      try {
        if (!isCurrent()) return;
        final result =
            await (accept
                    ? _profiles.acceptLoyaltyPolicy(displayed!.requiredVersion)
                    : _profiles.getLoyaltyPolicyStatus())
                .timeout(responseWait);
        await Future<void>.delayed(Duration.zero);
        if (!isCurrent()) return;
        if (accept &&
            (result.requiredVersion != displayed!.requiredVersion ||
                result.policySha256 != displayed.policySha256 ||
                result.policyText != displayed.policyText ||
                result.acceptedVersion != displayed.requiredVersion ||
                result.acceptedAt == null ||
                result.acceptanceRequired)) {
          throw const FormatException(
            'Policy acceptance did not match the displayed policy',
          );
        }
        _policy = result;
        _policyGeneration = generation;
        if (!result.acceptanceRequired) await revalidate();
      } catch (error) {
        await Future<void>.delayed(Duration.zero);
        if (!isCurrent()) return;
        _policyGeneration = null;
        _policyError = error;
        if (_isHardFailure(error)) _fail(error);
      } finally {
        _policyRequest = null;
        _acceptingPolicy = false;
        completion.complete();
        if (!_disposed) notifyListeners();
      }
    }());
    return completion.future;
  }

  bool get _isCurrent =>
      !_disposed &&
      !_streamClosed &&
      _usable(_session) &&
      _sameSession(_session, _auth.currentSession);

  bool _sameSession(Session? a, Session? b) =>
      a?.user.id == b?.user.id && a?.accessToken == b?.accessToken;

  bool _usable(Session? session) =>
      session != null &&
      session.user.id.isNotEmpty &&
      session.accessToken.isNotEmpty &&
      session.expiresAt != null &&
      DateTime.fromMillisecondsSinceEpoch(
        session.expiresAt! * 1000,
      ).isAfter(_now().add(_expiryMargin));

  void _armExpiry() {
    _expiryTimer?.cancel();
    if (!_usable(_session)) return;
    final deadline = DateTime.fromMillisecondsSinceEpoch(
      _session!.expiresAt! * 1000,
    ).subtract(_expiryMargin);
    _expiryTimer = Timer(deadline.difference(_now()), invalidate);
  }

  void _observeSession({bool hard = false, bool force = false}) {
    final current = _auth.currentSession;
    if (!force && !hard && _sameSession(_session, current)) return;
    hard =
        hard ||
        !_usable(_session) ||
        !_usable(current) ||
        _session?.user.id != current?.user.id;
    _session = current;
    _generation++;
    _status = null;
    _error = null;
    _clearPolicy(keepDocument: !hard);
    if (hard) _retainPresentation = false;
    _armExpiry();
    notifyListeners();
  }

  void _onAuthState(AuthState state) {
    if (_disposed) return;
    if (state.event == AuthChangeEvent.initialSession &&
        _sameSession(state.session, _session) &&
        _sameSession(_session, _auth.currentSession)) {
      return;
    }
    _observeSession(
      force: true,
      hard:
          !const [
            AuthChangeEvent.tokenRefreshed,
            AuthChangeEvent.userUpdated,
            AuthChangeEvent.mfaChallengeVerified,
          ].contains(state.event) ||
          state.session?.user.id != _session?.user.id,
    );
  }

  /// Hard invalidation clears presentation even while a request is outstanding.
  void invalidate() {
    if (_disposed) return;
    _generation++;
    _requestedGeneration = null;
    _status = null;
    _error = null;
    _retainPresentation = false;
    _clearPolicy();
    _expiryTimer?.cancel();
    notifyListeners();
  }

  // Auth events invalidate only. The route owner requests checks after callbacks.
  Future<void> revalidate() {
    if (_disposed || _streamClosed) return Future.value();
    _observeSession();
    if (_disposed) return Future.value();
    if (!_usable(_session)) {
      invalidate();
      return _request ?? Future.value();
    }
    if (_request != null) {
      _requestedGeneration = _generation;
      return _request!;
    }
    _armExpiry();
    _generation++;
    _clearPolicy(keepDocument: true);
    _requestedGeneration = _generation;
    _status = null;
    _error = null;
    final completion = Completer<void>();
    _request = completion.future;
    notifyListeners();
    unawaited(_check(completion));
    return completion.future;
  }

  Future<void> _check(Completer<void> completion) async {
    try {
      while (!_disposed && _requestedGeneration != null && _isCurrent) {
        final requestGeneration = _requestedGeneration!;
        final session = _session!;
        _requestedGeneration = null;
        AdmissionStatus? result;
        Object? failure;
        try {
          result = await _profiles.getAdmissionStatus().timeout(responseWait);
        } catch (error) {
          failure = error;
        }
        // Drain queued Auth events before applying either a result or an error.
        await Future<void>.delayed(Duration.zero);
        if (_disposed ||
            requestGeneration != _generation ||
            !_isCurrent ||
            !_sameSession(session, _session)) {
          continue;
        }
        // Duplicate callers share this response, not an extra trailing request.
        _requestedGeneration = null;
        if (failure != null) {
          _fail(failure);
        } else if (result!.subjectId != session.user.id) {
          _fail(StateError('Admission subject does not match the session'));
        } else {
          _status = result;
          _error = null;
          _retainPresentation =
              result.nextStep == 'home' ||
              (result.accountState == 'pending_deletion' &&
                  _allowsTopupRefunds(result));
        }
      }
    } finally {
      _request = null;
      completion.complete();
      if (!_disposed) notifyListeners();
    }
  }

  bool _isHardFailure(Object error) =>
      (error is AuthException && error is! AuthRetryableFetchException) ||
      error is FormatException ||
      error is StateError ||
      (error is PostgrestException &&
          const [
            'PT401',
            'PT403',
            'PGRST301',
            'PGRST303',
          ].contains(error.code));

  void _fail(Object error) {
    if (_disposed) return;
    final hard = _isHardFailure(error);
    _generation++;
    _requestedGeneration = null;
    _status = null;
    _error = error;
    _clearPolicy(keepDocument: !hard && _isCurrent);
    if (hard || !_isCurrent) _retainPresentation = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _status = null;
    _error = null;
    _retainPresentation = false;
    _clearPolicy();
    _requestedGeneration = null;
    _expiryTimer?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
