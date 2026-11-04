import 'dart:async';

import 'package:clean_stream_laundry_app/logic/models/release_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UsageEvent { settingsOpened, updateOpened }

class PushAccount {
  final String userId;
  final String bearer;
  final Object? sessionIdentity;
  const PushAccount(this.userId, this.bearer, {this.sessionIdentity});

  Object get sessionKey => sessionIdentity ?? bearer;
}

abstract interface class FirebaseDriver {
  Future<void> initialize();
  Future<void> analytics(bool enabled);
  Future<void> inAppMessaging(bool enabled);
  Future<void> event(UsageEvent event);
  Future<bool> permission({required bool request});
  Future<String?> token();
  Future<void> deleteToken();
  Future<String> releasePolicy();
  Stream<String> get tokenChanges;
  Stream<Map<String, dynamic>> get openedMessages;
  Stream<Map<String, dynamic>> get foregroundMessages;
  Future<Map<String, dynamic>?> initialMessage();
}

abstract interface class PushTokenStore {
  Future<void> bind(PushAccount account, String token);

  /// Installation capability permits cleanup even after Auth revocation.
  Future<void> revoke();
}

/// Owns optional Firebase effects. Auth/admission remain owned by the app.
class FirebaseService extends ChangeNotifier {
  final FirebaseDriver? driver;
  final PushTokenStore tokens;
  final SharedPreferences preferences;
  final String environment;
  final String platform;
  final String version;
  final String build;
  final Future<void> Function(String) navigate;
  final Future<void> Function(String) showNotification;
  final void Function(String) diagnostic;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _effects = Future.value();
  Future<void> _consentEffects = Future.value();
  bool _consentPending = false;
  int _consentRevision = 0;
  static const _consentProblem =
      'Could not apply privacy consent. Please retry.';
  Future<void>? _refresh;
  PushAccount? _account;
  bool _admitted = false;
  int _generation = 0;
  bool _disposed = false;
  bool available = false;
  bool analyticsEnabled = false;
  bool messagesEnabled = false;
  bool pushEnabled = false;
  String? problem;
  ReleasePolicy policy = ReleasePolicy.safe();

  FirebaseService({
    required this.driver,
    required this.tokens,
    required this.preferences,
    required this.environment,
    required this.platform,
    required this.version,
    required this.build,
    required this.navigate,
    required this.showNotification,
    required this.diagnostic,
  });

  String get _cacheKey => 'firebase.$environment.$platform.release.v1';
  String get _consentKey => 'firebase.$environment.consent.';
  ReleaseDecision get decision {
    try {
      return policy.evaluate(version, build);
    } catch (_) {
      return policy.maintenance
          ? ReleaseDecision.maintenance
          : ReleaseDecision.allowed;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _serial(Future<void> Function() action) {
    final result = _effects.then((_) => action());
    _effects = result.catchError((Object _) {});
    return result;
  }

  void _failure(String message) {
    problem = message;
    diagnostic(
      message,
    ); // Never log SDK errors, tokens, payloads or account IDs.
    _notify();
  }

  Future<void> start() async {
    final cache = preferences.getString(_cacheKey);
    if (cache != null) {
      try {
        policy = ReleasePolicy.parse(cache, platform);
      } catch (_) {
        diagnostic('Invalid cached release policy; using safe defaults.');
      }
    }
    _notify();
    if (driver == null) {
      diagnostic(
        'Firebase disabled. Supply FIREBASE_ENV=dev|prod and the '
        'matching FIREBASE_ANDROID_API_KEY/FIREBASE_IOS_API_KEY via '
        '--dart-define-from-file. Only registered Android/iOS apps are supported.',
      );
      return;
    }
    try {
      final consentRevision = _consentRevision;
      final analyticsConsent =
          preferences.getBool('${_consentKey}analytics') ?? false;
      final messagesConsent =
          preferences.getBool('${_consentKey}messages') ?? false;
      await driver!.initialize();
      await _saveConsent();
      available = true;
      // Clear any previous process/session binding before a new explicit opt-in.
      await _serial(_cleanupPush);
      if (!_disposed && consentRevision == _consentRevision) {
        analyticsEnabled = analyticsConsent;
        messagesEnabled = analyticsConsent && messagesConsent;
        await _saveConsent();
      }
      _subscriptions.add(
        driver!.tokenChanges.listen((_) {
          if (pushEnabled) unawaited(_serial(_registerPush));
        }, onError: (Object _) => _failure('Push token refresh unavailable.')),
      );
      _subscriptions.add(
        driver!.openedMessages.listen((data) {
          unawaited(openNotification(data));
        }),
      );
      _subscriptions.add(
        driver!.foregroundMessages.listen((data) {
          final route = notificationRoute(data);
          if (pushEnabled && _admitted && _account != null && route != null) {
            unawaited(
              showNotification(route).catchError((Object _) {
                _failure('Could not display notification.');
              }),
            );
          }
        }),
      );
      final initial = await driver!.initialMessage();
      if (initial != null) await openNotification(initial);
      unawaited(refreshReleasePolicy());
    } catch (_) {
      available = false;
      _failure(
        'Optional Firebase unavailable. Verify matching native config '
        'and compile-time environment; browsing remains available.',
      );
    }
    _notify();
  }

  Future<void> setAnalytics(bool enabled) {
    _consentRevision++;
    analyticsEnabled = enabled && available;
    if (!analyticsEnabled) messagesEnabled = false;
    _notify();
    return _saveConsent();
  }

  Future<void> setMessages(bool enabled) {
    _consentRevision++;
    messagesEnabled = enabled && available && analyticsEnabled;
    _notify();
    return _saveConsent();
  }

  Future<void> _saveConsent() {
    // Privacy revocation must not wait for a pending push permission/token call.
    return _consentEffects = _consentEffects.then((_) async {
      var failed = false;
      Future<void> attempt(Future<void> Function() effect) async {
        try {
          await effect();
        } catch (_) {
          failed = true;
        }
      }

      for (final setting in ['analytics', 'messages']) {
        await attempt(() async {
          final enabled = setting == 'analytics'
              ? analyticsEnabled
              : messagesEnabled;
          if (!await preferences.setBool('$_consentKey$setting', enabled)) {
            throw StateError('Consent persistence failed');
          }
        });
      }
      // Attempt both even if persistence or either SDK operation fails.
      await attempt(() async => driver?.analytics(analyticsEnabled));
      await attempt(() async => driver?.inAppMessaging(messagesEnabled));
      _consentPending = failed;
      if (failed) {
        _failure(_consentProblem);
      } else if (problem == _consentProblem) {
        problem = null;
        _notify();
      }
    });
  }

  Future<void> log(UsageEvent event) async {
    if (!available || !analyticsEnabled) return;
    try {
      await driver!.event(event);
    } catch (_) {
      /* Optional telemetry. */
    }
  }

  /// Admission must be confirmed by the existing controller before binding.
  Future<void> accountChanged(PushAccount? account, {bool admitted = true}) {
    final changed =
        _account?.userId != account?.userId ||
        _account?.sessionKey != account?.sessionKey;
    _account = account;
    _admitted = account != null && admitted;
    if (!changed) return Future.value();
    _generation++;
    pushEnabled = false;
    _notify();
    // Invalidate immediately; a held token future must not block Auth observers.
    // Subsequent opt-in still queues behind cleanup.
    unawaited(_serial(_cleanupPush));
    return Future.value();
  }

  Future<void> _cleanupPush() async {
    var failed = false;
    try {
      await tokens.revoke();
    } catch (_) {
      failed = true;
    }
    if (available) {
      try {
        await driver?.deleteToken();
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      _failure(
        'Push cleanup pending. Reconnect and retry before enabling push.',
      );
    }
  }

  Future<void> disablePush() {
    _generation++;
    pushEnabled = false;
    _notify();
    return _serial(_cleanupPush);
  }

  Future<void> setPush(bool enabled) {
    if (!enabled) return disablePush();
    final account = _account;
    final generation = _generation;
    if (!available || account == null || !_admitted) return Future.value();
    return _serial(() async {
      try {
        // A failed server cleanup must not transfer an old token to another user.
        await tokens.revoke();
        if (!_current(account, generation)) return;
        final permitted = await driver!.permission(request: true);
        if (!_current(account, generation)) return;
        pushEnabled = permitted;
        if (permitted) {
          await _registerPush();
        } else {
          await _cleanupPush();
          _failure(
            'Notifications are not allowed. Review device notification settings.',
          );
        }
      } catch (_) {
        pushEnabled = false;
        await _cleanupPush();
        _failure(
          'Push registration unavailable. Check permission, APNs and backend setup.',
        );
      }
      _notify();
    });
  }

  bool _current(PushAccount account, int generation) =>
      !_disposed &&
      _admitted &&
      generation == _generation &&
      _account?.userId == account.userId &&
      _account?.sessionKey == account.sessionKey &&
      _account?.bearer == account.bearer;

  Future<void> _registerPush() async {
    final account = _account;
    final generation = _generation;
    if (account == null || !pushEnabled || !_admitted) return;
    try {
      if (!await driver!.permission(request: false)) {
        pushEnabled = false;
        await _cleanupPush();
        _notify();
        return;
      }
      if (!_current(account, generation) || !pushEnabled) return;
      final token = await driver!.token();
      if (!_current(account, generation) || !pushEnabled) return;
      if (token == null) throw StateError('Token not ready');
      await tokens.bind(account, token);
      if (!_current(account, generation) || !pushEnabled) await _cleanupPush();
    } catch (_) {
      pushEnabled = false;
      await _cleanupPush();
      _failure('Push registration unavailable. Retry after connecting.');
    }
    _notify();
  }

  Future<void> resume() async {
    if (_consentPending) await _saveConsent();
    await _serial(() async {
      if (pushEnabled) {
        await _registerPush();
      } else {
        await _cleanupPush();
      }
    });
    await refreshReleasePolicy();
  }

  Future<void> refreshReleasePolicy() {
    if (!available) return Future.value();
    if (_refresh != null) return _refresh!;
    return _refresh = (() async {
      try {
        final raw = await driver!.releasePolicy();
        final next = ReleasePolicy.parse(raw, platform);
        var persisted = false;
        try {
          persisted = await preferences.setString(_cacheKey, raw);
        } catch (_) {
          // Treat thrown writes and rejected writes identically below.
        }
        if (!persisted) {
          diagnostic(
            'Release policy cache write failed; restart may use older policy.',
          );
          final nextDecision = next.evaluate(version, build);
          // Enforce emergency restrictions even without disk, but never clear
          // a current restriction with a replacement that could not be saved.
          if (nextDecision != ReleaseDecision.blocked &&
              nextDecision != ReleaseDecision.maintenance) {
            return;
          }
        }
        policy = next;
        _notify();
      } catch (_) {
        diagnostic('Release policy unavailable; retaining last valid policy.');
      } finally {
        _refresh = null;
      }
    })();
  }

  static String? notificationRoute(Map<String, dynamic> data) =>
      switch (data['destination']) {
        'home' => '/homePage',
        'settings' => '/settings',
        _ => null,
      };

  Future<void> openNotification(Map<String, dynamic> data) async {
    final route = notificationRoute(data);
    if (route == null || _disposed) return;
    try {
      await navigate(route);
    } catch (_) {
      diagnostic('Notification destination unavailable.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
