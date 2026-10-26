import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import 'firebase_configuration.dart';
import 'firebase_service.dart';

class FlutterFireDriver implements FirebaseDriver {
  final FirebaseConfiguration configuration;
  FlutterFireDriver(this.configuration);

  @override
  Future<void> initialize() async {
    final app = await Firebase.initializeApp(
      options: configuration.options,
    ).timeout(const Duration(seconds: 8));
    if (app.options.appId != configuration.options.appId ||
        app.options.projectId != configuration.options.projectId) {
      throw StateError('Native Firebase environment mismatch');
    }
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
    await FirebaseRemoteConfig.instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        minimumFetchInterval: const Duration(hours: 12),
      ),
    );
    await FirebaseRemoteConfig.instance.setDefaults({'release_policy_v1': ''});
  }

  @override
  Future<void> analytics(bool enabled) async {
    final analytics = FirebaseAnalytics.instance;
    Future<void> consent() => analytics.setConsent(
      analyticsStorageConsentGranted: enabled,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    if (enabled) {
      await consent();
      await analytics.setAnalyticsCollectionEnabled(true);
    } else {
      try {
        await analytics.setAnalyticsCollectionEnabled(false);
      } finally {
        try {
          await consent();
        } finally {
          await analytics.resetAnalyticsData();
        }
      }
    }
  }

  @override
  Future<void> inAppMessaging(bool enabled) async {
    final messaging = FirebaseInAppMessaging.instance;
    try {
      await messaging.setMessagesSuppressed(!enabled);
    } finally {
      if (!enabled) await messaging.setAutomaticDataCollectionEnabled(false);
    }
    if (enabled) await messaging.setAutomaticDataCollectionEnabled(true);
  }

  @override
  Future<void> event(UsageEvent event) => FirebaseAnalytics.instance.logEvent(
    name: switch (event) {
      UsageEvent.settingsOpened => 'settings_opened',
      UsageEvent.updateOpened => 'update_opened',
    },
  ); // No free-text parameters, user properties, user IDs or screen observer.

  @override
  Future<bool> permission({required bool request}) async {
    final result = request
        ? await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          )
        : await FirebaseMessaging.instance.getNotificationSettings();
    return result.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<String?> token() async {
    final messaging = FirebaseMessaging.instance;
    if (configuration.platform != 'ios' ||
        await messaging.getAPNSToken() != null) {
      return messaging.getToken();
    }

    // On fresh iOS installs, only auto-init starts APNs registration in the SDK.
    // Subscribe first: registration can emit a token before enabling returns.
    final refreshed = Completer<String>();
    final subscription = messaging.onTokenRefresh.listen(
      (token) {
        if (!refreshed.isCompleted) refreshed.complete(token);
      },
      onError: (Object error, StackTrace stack) {
        if (!refreshed.isCompleted) refreshed.completeError(error, stack);
      },
    );
    try {
      final results = await Future.wait<String?>([
        messaging.setAutoInitEnabled(true).then((_) => null),
        refreshed.future,
      ], eagerError: true).timeout(const Duration(seconds: 8));
      return results[1];
    } finally {
      try {
        await subscription.cancel();
      } finally {
        await messaging.setAutoInitEnabled(false);
      }
    }
  }

  @override
  Future<void> deleteToken() async {
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await FirebaseMessaging.instance.deleteToken();
  }

  @override
  Future<void> deleteInstallation() => FirebaseInstallations.instance.delete();

  @override
  Future<String> releasePolicy() async {
    final config = FirebaseRemoteConfig.instance;
    await config.fetchAndActivate();
    return config.getString('release_policy_v1');
  }

  @override
  Stream<String> get tokenChanges => FirebaseMessaging.instance.onTokenRefresh;
  @override
  Stream<Map<String, dynamic>> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.map((message) => message.data);
  @override
  Stream<Map<String, dynamic>> get foregroundMessages =>
      FirebaseMessaging.onMessage.map((message) => message.data);
  @override
  Future<Map<String, dynamic>?> initialMessage() async =>
      (await FirebaseMessaging.instance.getInitialMessage())?.data;
}
