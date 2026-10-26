import 'dart:async';

import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum MfaMode { enrollment, challenge }

enum MfaStage {
  idle,
  readyToEnroll,
  challenge,
  setup,
  verified,
  blocked,
  expired,
}

enum MfaOperation { loading, enrolling, verifying, revalidating }

/// One controller per visible MFA flow. Recreate after dismissal/session changes.
/// Local state is presentation only; onVerified callers must revalidate access.
class MfaController extends ChangeNotifier {
  static const responseWait = Duration(seconds: 10);
  final AuthService _auth;
  final MfaMode mode;
  late final StreamSubscription<AuthState> _subscription;
  Session? _session;
  Timer? _expiryTimer;
  Timer? _waitTimer;
  Future<void>? _pending;
  MfaOperation? _operation;
  MfaStage _stage = MfaStage.idle;
  List<Factor> _factors = const [];
  String? _factorId;
  TOTPEnrollment? _setup;
  String? _message;
  bool _waiting = false;
  bool _closed = false;
  bool _disposed = false;
  int _generation = 0;

  MfaController({required AuthService authService, required this.mode})
    : _auth = authService {
    _session = _auth.currentSession;
    _subscription = _auth.authStateChanges.listen(
      _onAuthState,
      onError: (Object _) => dismiss(),
      onDone: dismiss,
    );
    _armExpiry();
  }

  bool get _current =>
      !_closed &&
      !_disposed &&
      _session != null &&
      _session!.user.id.isNotEmpty &&
      _session!.accessToken.isNotEmpty &&
      _session!.expiresAt != null &&
      !_session!.isExpired &&
      identical(_session, _auth.currentSession);

  MfaStage get stage => _current ? _stage : MfaStage.expired;
  int get generation => _generation;
  MfaOperation? get operation => _operation;
  bool get isBusy => _pending != null;
  bool get isWaiting => _waiting;
  String? get message => _current ? _message : null;
  List<Factor> get factors => _current ? _factors : const [];
  String? get factorId => _current ? _factorId : null;
  TOTPEnrollment? get setup => _current ? _setup : null;
  bool get canLoad =>
      _current &&
      !isBusy &&
      const [
        MfaStage.idle,
        MfaStage.readyToEnroll,
        MfaStage.challenge,
      ].contains(_stage);
  bool get canEnroll => _current && !isBusy && _stage == MfaStage.readyToEnroll;
  bool get canVerify =>
      _current &&
      !isBusy &&
      _factorId != null &&
      const [MfaStage.setup, MfaStage.challenge].contains(_stage);
  bool get canRevalidate => _current && !isBusy && _stage == MfaStage.verified;

  void _armExpiry() {
    _expiryTimer?.cancel();
    if (!_current) return;
    final deadline = DateTime.fromMillisecondsSinceEpoch(
      _session!.expiresAt! * 1000,
    ).subtract(const Duration(seconds: 30));
    _expiryTimer = Timer(deadline.difference(DateTime.now()), dismiss);
  }

  void _onAuthState(AuthState state) {
    if (_closed || _disposed) return;
    if (state.event == AuthChangeEvent.initialSession &&
        identical(state.session, _session) &&
        _current) {
      return;
    }
    // SDK factor listing refreshes the session; the verify adapter also adopts
    // through tokenRefreshed. Neither event authorizes account access.
    if ((_operation == MfaOperation.loading ||
            _operation == MfaOperation.verifying) &&
        state.event == AuthChangeEvent.tokenRefreshed &&
        state.session != null &&
        state.session!.user.id == _session?.user.id &&
        _session!.expiresAt != null &&
        !_session!.isExpired &&
        state.session!.expiresAt != null &&
        !state.session!.isExpired &&
        identical(state.session, _auth.currentSession)) {
      _session = state.session;
      _armExpiry();
      return;
    }
    dismiss();
  }

  Future<void> load() {
    if (isBusy) return _pending!;
    if (!canLoad) return Future.value();
    _stage = MfaStage.idle;
    _factors = const [];
    _factorId = null;
    return _run(MfaOperation.loading, (current) async {
      final response = await _auth.listMfaFactors();
      await Future<void>.delayed(Duration.zero);
      if (!current()) return;
      final assurance = _auth.getMfaAssurance();
      final all = response.all;
      if (assurance.currentLevel == null ||
          assurance.nextLevel == null ||
          all.any(
            (factor) =>
                factor.id.isEmpty ||
                factor.factorType != FactorType.totp ||
                factor.status == FactorStatus.unknown,
          ) ||
          all.map((factor) => factor.id).toSet().length != all.length) {
        _block(
          'This authentication method is not supported here. Contact support.',
        );
        return;
      }
      _factors = List.unmodifiable(
        all.where((factor) => factor.status == FactorStatus.verified),
      );
      _factorId = _factors.isEmpty ? null : _factors.first.id;
      if (_factors.isNotEmpty) {
        _stage = MfaStage.challenge;
      } else if (all.isNotEmpty) {
        _block(
          'An unfinished authenticator setup exists. Contact support before starting another.',
        );
      } else if (mode == MfaMode.enrollment &&
          assurance.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
          assurance.nextLevel == AuthenticatorAssuranceLevels.aal1) {
        _stage = MfaStage.readyToEnroll;
      } else {
        _block('No verified authenticator is available. Contact support.');
      }
    });
  }

  void selectFactor(String id) {
    if (!canVerify || _stage != MfaStage.challenge) return;
    if (!_factors.any((factor) => factor.id == id)) return;
    _factorId = id;
    _message = null;
    notifyListeners();
  }

  Future<void> enroll() {
    if (isBusy) return _pending!;
    if (!canEnroll) return Future.value();
    // No retry after dispatch, even on failure: the remote outcome can be unknown.
    _stage = MfaStage.blocked;
    return _run(MfaOperation.enrolling, (current) async {
      final response = await _auth.enrollTotp();
      await Future<void>.delayed(Duration.zero);
      if (!current()) return;
      final totp = response.totp;
      final uri = totp == null ? null : Uri.tryParse(totp.uri);
      if (response.type != FactorType.totp ||
          response.id.isEmpty ||
          totp == null ||
          totp.secret.isEmpty ||
          uri?.scheme != 'otpauth' ||
          uri?.host != 'totp' ||
          uri?.queryParameters['secret'] != totp.secret) {
        _block(
          'Setup could not be confirmed. Contact support before starting another.',
        );
        return;
      }
      _factorId = response.id;
      _setup = totp;
      _stage = MfaStage.setup;
    });
  }

  Future<void> verify(
    String code, {
    required Future<void> Function() onVerified,
  }) {
    if (isBusy) return _pending!;
    if (!canVerify) return Future.value();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _message = 'Enter the six-digit authenticator code.';
      notifyListeners();
      return Future.value();
    }
    return _run(MfaOperation.verifying, (current) async {
      final result = await _auth.verifyTotp(factorId: _factorId!, code: code);
      await Future<void>.delayed(Duration.zero);
      if (!current()) return;
      if (result.user.id != _session!.user.id ||
          result.accessToken != _session!.accessToken ||
          _auth.getMfaAssurance().currentLevel !=
              AuthenticatorAssuranceLevels.aal2) {
        _block('Verification could not be confirmed. Reopen authentication.');
        return;
      }
      _setup = null;
      _factorId = null;
      _factors = const [];
      _stage = MfaStage.verified;
      _operation = MfaOperation.revalidating;
      notifyListeners();
      if (current()) await onVerified();
    });
  }

  /// Retry only the caller's access check, never repeat a successful verification.
  Future<void> revalidate({required Future<void> Function() onVerified}) {
    if (isBusy) return _pending!;
    if (!canRevalidate) return Future.value();
    return _run(MfaOperation.revalidating, (current) async {
      if (current()) await onVerified();
    });
  }

  Future<void> _run(
    MfaOperation operation,
    Future<void> Function(bool Function() current) action,
  ) {
    final generation = _generation;
    bool current() => generation == _generation && _current;
    final completion = Completer<void>();
    _pending = completion.future;
    _operation = operation;
    _message = null;
    _waitTimer = Timer(responseWait, () {
      if (!current()) return;
      _waiting = true;
      notifyListeners();
    });
    notifyListeners();
    unawaited(() async {
      try {
        if (current()) await action(current);
      } catch (_) {
        await Future<void>.delayed(Duration.zero);
        if (current()) {
          if (operation == MfaOperation.enrolling) {
            _block(
              'Setup could not be confirmed. Contact support before starting another.',
            );
          } else {
            _message = _stage == MfaStage.verified
                ? 'Code verified, but account access could not be checked. Try checking again.'
                : operation == MfaOperation.loading
                ? 'Unable to load authenticators. Try again.'
                : 'Unable to verify the code. Check the latest code and try again.';
          }
        }
      } finally {
        _waitTimer?.cancel();
        _waiting = false;
        _pending = null;
        _operation = null;
        completion.complete();
        if (!_disposed) notifyListeners();
      }
    }());
    return completion.future;
  }

  void _block(String message) {
    _stage = MfaStage.blocked;
    _message = message;
    _setup = null;
    _factors = const [];
    _factorId = null;
  }

  /// Clears presentation only; cannot cancel dispatched SDK/server effects.
  void dismiss() {
    if (_closed || _disposed) return;
    _closed = true;
    _generation++;
    _setup = null;
    _factors = const [];
    _factorId = null;
    _message = null;
    _expiryTimer?.cancel();
    _waitTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    dismiss();
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
