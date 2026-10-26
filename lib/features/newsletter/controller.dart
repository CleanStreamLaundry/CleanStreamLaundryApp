import 'dart:async';

import 'package:clean_stream_laundry_app/logic/models/newsletter_status.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewsletterController extends ChangeNotifier {
  NewsletterController({
    required this.authService,
    required this.profileService,
  }) {
    final initialSession = authService.currentSession;
    var firstEvent = true;
    _authSubscription = authService.authStateChanges.listen(
      (state) {
        final replay = firstEvent && identical(state.session, initialSession);
        firstEvent = false;
        if (!replay) _invalidate();
      },
      onError: (Object _) => _invalidate(unavailable: true),
      onDone: () => _invalidate(unavailable: true),
    );
  }

  final AuthService authService;
  final ProfileService profileService;
  late final StreamSubscription<AuthState> _authSubscription;
  int _generation = 0;
  bool _disposed = false;
  bool _authAvailable = true;
  bool busy = false;
  bool consent = false;
  bool needsStatusCheck = true;
  NewsletterStatus? status;
  String? message;

  bool get canRequest =>
      !busy &&
      !needsStatusCheck &&
      status?.enabled == true &&
      const [
        NewsletterState.notSubscribed,
        NewsletterState.expired,
        NewsletterState.unsubscribed,
      ].contains(status?.state);
  bool get canWithdraw =>
      !busy &&
      !needsStatusCheck &&
      const [
        NewsletterState.pending,
        NewsletterState.subscribed,
      ].contains(status?.state);

  void setConsent(bool value) {
    if (_disposed || !canRequest) return;
    consent = value;
    notifyListeners();
  }

  void _invalidate({bool unavailable = false}) {
    if (_disposed) return;
    _generation++;
    _authAvailable = _authAvailable && !unavailable;
    status = null;
    consent = false;
    busy = false;
    needsStatusCheck = true;
    message = 'Session changed. Refresh newsletter preferences.';
    notifyListeners();
  }

  bool _current(Session? session, int generation) =>
      !_disposed &&
      _authAvailable &&
      generation == _generation &&
      session != null &&
      session.accessToken.isNotEmpty &&
      session.expiresAt != null &&
      !session.isExpired &&
      identical(session, authService.currentSession) &&
      session.user.id == authService.getCurrentUserId;

  Future<void> refresh() => _run();
  Future<void> request() async {
    if (!canRequest || !consent) return;
    await _run(action: 'request');
  }

  Future<void> withdraw() async {
    if (!canWithdraw) return;
    await _run(action: 'withdraw');
  }

  Future<void> _run({String? action}) async {
    if (_disposed || busy) return;
    final session = authService.currentSession;
    final generation = _generation;
    if (!_current(session, generation)) {
      _invalidate();
      return;
    }
    final version = status?.consentVersion;
    busy = true;
    message = null;
    if (action != null) consent = false;
    notifyListeners();
    var dispatched = false;
    try {
      if (action != null) {
        final admission = await profileService.getAdmissionStatus();
        await Future<void>.delayed(Duration.zero);
        if (!_current(session, generation)) return;
        if (admission.subjectId != session!.user.id ||
            admission.accountAccess != 'eligible' ||
            admission.nextStep != 'home') {
          needsStatusCheck = true;
          message =
              'Account access must be verified before changing newsletter preferences.';
          return;
        }
      }
      if (!_current(session, generation)) return;
      needsStatusCheck = true;
      dispatched = action != null;
      final result = switch (action) {
        'request' => await profileService.requestNewsletter(version!),
        'withdraw' => await profileService.withdrawNewsletter(),
        _ => await profileService.getNewsletterStatus(),
      };
      await Future<void>.delayed(Duration.zero);
      if (!_current(session, generation)) return;
      _accept(result, session!);
    } catch (_) {
      await Future<void>.delayed(Duration.zero);
      if (!_current(session, generation)) return;
      needsStatusCheck = true;
      consent = false;
      message = dispatched
          ? 'The change could not be confirmed. Checking current status; no request will be retried.'
          : 'Unable to refresh preferences. Displayed information may be out of date.';
      if (dispatched) {
        // A failed response does not prove the mutation failed. Read only.
        try {
          final result = await profileService.getNewsletterStatus();
          await Future<void>.delayed(Duration.zero);
          if (!_current(session, generation)) return;
          _accept(result, session!);
          message =
              'Current status checked. The earlier change was not retried. Email delivery is unknown.';
        } catch (_) {
          if (!_current(session, generation)) return;
          message =
              'The outcome is unknown. Refresh status before making another change.';
        }
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        if (!_current(session, generation)) {
          _invalidate();
        } else {
          notifyListeners();
        }
      }
    }
  }

  void _accept(NewsletterStatus result, Session session) {
    if (result.subjectId != session.user.id) {
      throw const FormatException('Newsletter subject mismatch');
    }
    if (result.consentVersion != status?.consentVersion ||
        result.consentText != status?.consentText ||
        result.state != status?.state ||
        !result.enabled) {
      consent = false;
    }
    status = result;
    needsStatusCheck = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_authSubscription.cancel());
    super.dispose();
  }
}
