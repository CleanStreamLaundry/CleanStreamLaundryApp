import 'dart:async';

import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_configuration.dart';
import 'firebase_service.dart';
import 'flutterfire_driver.dart';
import 'push_token_store.dart';

/// GetIt owns this lifetime. No router definitions or second admission engine.
class FirebaseBootstrap {
  final FirebaseService service;
  final AdmissionController admission;
  final AuthService auth;
  StreamSubscription<AuthState>? _authSubscription;
  Object _pushSession = Object();
  bool _hadHomeAdmission = false;
  Session? _observedSession;
  FirebaseBootstrap._(this.service, this.admission, this.auth)
    : _observedSession = auth.currentSession;

  static Future<FirebaseBootstrap> create({
    required AuthService auth,
    required AdmissionController admission,
    required GoRouter router,
    required String supabaseUrl,
    required String publicKey,
    required NotificationService Function() notifications,
  }) async {
    final config = FirebaseConfiguration.fromBuild();
    final preferences = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
    const environment = String.fromEnvironment('FIREBASE_ENV');
    var authEpoch = 0;
    final tokens = SupabasePushTokenStore(
      // No Auth client and no implicit refresh or browser session broadcast.
      client: PostgrestClient(
        '$supabaseUrl/rest/v1',
        headers: {'apikey': publicKey},
      ),
      preferences: preferences,
      environment: environment,
      platform: platform,
    );
    final service = FirebaseService(
      driver: config == null ? null : FlutterFireDriver(config),
      tokens: tokens,
      preferences: preferences,
      environment: environment,
      platform: platform,
      version: info.version,
      build: info.buildNumber,
      diagnostic: (message) {
        if (kDebugMode) debugPrint(message);
      },
      navigate: (route) async {
        final epoch = authEpoch;
        final user = auth.currentSession?.user.id;
        await admission.revalidate();
        if (authEpoch != epoch || auth.currentSession?.user.id != user) return;
        if (admission.canEnterHome) {
          router.go(
            route,
          ); // Destination also passes through normal router gates.
        } else {
          router.go('/loading');
        }
      },
      showNotification: (route) => notifications().showPushNotification(route),
    );
    final bootstrap = FirebaseBootstrap._(service, admission, auth);
    if (config != null) {
      notifications().onPushOpened = (route) => unawaited(
        service.openNotification({
          'destination': route == '/settings' ? 'settings' : 'home',
        }),
      );
    }
    admission.addListener(bootstrap._syncAccount);
    bootstrap._authSubscription = auth.authStateChanges.listen(
      (state) {
        authEpoch++;
        final duplicateInitial =
            state.event == AuthChangeEvent.initialSession &&
            state.session?.user.id == bootstrap._observedSession?.user.id &&
            state.session?.accessToken ==
                bootstrap._observedSession?.accessToken;
        if (!duplicateInitial &&
            !const [
              AuthChangeEvent.tokenRefreshed,
              AuthChangeEvent.userUpdated,
              AuthChangeEvent.mfaChallengeVerified,
            ].contains(state.event)) {
          bootstrap._pushSession = Object();
          bootstrap._hadHomeAdmission = false;
          unawaited(service.accountChanged(null));
        }
        bootstrap._observedSession = state.session;
        bootstrap._syncAccount();
      },
      onError: (Object _) {
        authEpoch++;
        bootstrap._hadHomeAdmission = false;
        unawaited(service.accountChanged(null));
      },
    );
    bootstrap._syncAccount();
    return bootstrap;
  }

  void _syncAccount() {
    final session = auth.currentSession;
    final status = admission.status;
    unawaited(
      service.deletionChanged(
        session != null &&
                status?.subjectId == session.user.id &&
                status?.accountState == 'pending_deletion'
            ? '${status!.subjectId}:${status.restoreUntil!.toIso8601String()}'
            : null,
      ),
    );
    final eligibleHome =
        admission.canEnterHome && admission.status?.accountAccess == 'eligible';
    if (eligibleHome) _hadHomeAdmission = true;
    // Presentation retention (including refund-only access) is not permission.
    final retainBinding =
        eligibleHome ||
        (_hadHomeAdmission &&
            admission.status == null &&
            admission.retainSafePresentation);
    if (!retainBinding) _hadHomeAdmission = false;
    final account = session != null && !session.isExpired && retainBinding
        ? PushAccount(
            session.user.id,
            'Bearer ${session.accessToken}',
            sessionIdentity: _pushSession,
          )
        : null;
    unawaited(service.accountChanged(account, admitted: eligibleHome));
  }

  void dispose() {
    admission.removeListener(_syncAccount);
    unawaited(_authSubscription?.cancel());
    service.dispose();
  }
}
