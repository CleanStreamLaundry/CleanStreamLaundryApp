import 'dart:async';
import 'dart:convert';

import 'package:clean_stream_laundry_app/logic/models/release_policy.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_configuration.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String policyJson({
  String minimum = '1.0.0',
  String recommended = '2.0.0',
  List<Object> blocked = const [],
  bool maintenance = false,
  String url = '',
}) => jsonEncode({
  'schema': 1,
  'android': {
    'minimum': minimum,
    'recommended': recommended,
    'blocked_builds': blocked,
    'maintenance': maintenance,
    'update_url': url,
  },
});

class Driver implements FirebaseDriver {
  final calls = <String>[];
  bool granted = true;
  bool failInitialize = false;
  bool offline = false;
  String raw = policyJson();
  Completer<String?>? delayedToken;
  Completer<bool>? delayedPermission;
  final refreshes = StreamController<String>.broadcast();
  final opens = StreamController<Map<String, dynamic>>.broadcast();
  final foreground = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Future<void> initialize() async {
    if (failInitialize) throw StateError('unavailable');
  }

  @override
  Future<void> analytics(bool enabled) async => calls.add('analytics:$enabled');
  @override
  Future<void> inAppMessaging(bool enabled) async =>
      calls.add('messages:$enabled');
  @override
  Future<void> event(UsageEvent event) async =>
      calls.add('event:${event.name}');
  @override
  Future<bool> permission({required bool request}) async {
    calls.add('permission:$request');
    return delayedPermission?.future ?? granted;
  }

  @override
  Future<String?> token() async => delayedToken?.future ?? 'test-token';
  @override
  Future<void> deleteToken() async => calls.add('delete');
  @override
  Future<void> deleteInstallation() async => calls.add('delete-installation');
  @override
  Future<String> releasePolicy() async {
    if (offline) throw StateError('offline');
    return raw;
  }

  @override
  Stream<String> get tokenChanges => refreshes.stream;
  @override
  Stream<Map<String, dynamic>> get openedMessages => opens.stream;
  @override
  Stream<Map<String, dynamic>> get foregroundMessages => foreground.stream;
  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;
}

class Tokens implements PushTokenStore {
  final owners = <String>[];
  int revocations = 0;
  bool failRevoke = false;
  Completer<void>? delayedBind;
  @override
  Future<void> bind(PushAccount account, String token) async {
    owners.add('${account.userId}:${account.bearer}');
    await delayedBind?.future;
  }

  @override
  Future<void> revoke() async {
    revocations++;
    if (failRevoke) throw StateError('offline');
  }
}

Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late Driver driver;
  late Tokens tokens;
  late FirebaseService service;
  final routes = <String>[];
  final notifications = <String>[];
  final diagnostics = <String>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    driver = Driver();
    tokens = Tokens();
    routes.clear();
    notifications.clear();
    diagnostics.clear();
    service = FirebaseService(
      driver: driver,
      tokens: tokens,
      preferences: prefs,
      environment: 'dev',
      platform: 'android',
      version: '1.0.0',
      build: '10',
      navigate: (route) async => routes.add(route),
      showNotification: (route) async => notifications.add(route),
      diagnostic: diagnostics.add,
    );
  });
  tearDown(() => service.dispose());

  test(
    'no environment, missing key, unsupported platform never select production',
    () {
      final key = 'AIza${'x' * 35}';
      for (final env in ['', 'debug', 'production']) {
        expect(
          FirebaseConfiguration.resolve(
            environment: env,
            platform: 'android',
            androidKey: key,
            iosKey: key,
          ),
          isNull,
        );
      }
      expect(
        FirebaseConfiguration.resolve(
          environment: 'dev',
          platform: 'android',
          androidKey: '',
          iosKey: key,
        ),
        isNull,
      );
      expect(
        FirebaseConfiguration.resolve(
          environment: 'prod',
          platform: 'web',
          androidKey: key,
          iosKey: key,
        ),
        isNull,
      );
    },
  );
  test('all four registrations match explicit environment and platform', () {
    final key = 'AIza${'x' * 35}';
    for (final env in ['dev', 'prod']) {
      for (final platform in ['android', 'ios']) {
        final config = FirebaseConfiguration.resolve(
          environment: env,
          platform: platform,
          androidKey: key,
          iosKey: key,
        )!;
        expect(
          config.options.projectId,
          env == 'dev' ? 'clean-stream-dev' : 'clean-stream-production',
        );
        expect(config.options.appId, contains(':$platform:'));
        expect(
          config.options.messagingSenderId,
          env == 'dev' ? '83380736317' : '863183154828',
        );
      }
    }
  });
  test(
    'startup enables operational analytics without messaging or push opt-in',
    () async {
      await service.start();
      await service.log(UsageEvent.settingsOpened);
      expect(service.available, isTrue);
      expect(driver.calls, isNot(contains('permission:true')));
      expect(service.analyticsEnabled, isTrue);
      expect(
        driver.calls,
        containsAll(['analytics:true', 'event:settingsOpened']),
      );
      expect(driver.calls, isNot(contains('messages:true')));
      expect(service.pushEnabled, isFalse);
      expect(prefs.getBool('firebase.dev.consent.analytics'), isNull);
    },
  );
  test(
    'initialization failure is optional and diagnostics contain no SDK secrets',
    () async {
      driver.failInitialize = true;
      await service.start();
      expect(service.available, isFalse);
      expect(service.decision, ReleaseDecision.allowed);
      expect(diagnostics.join(), isNot(contains('unavailable\n')));
    },
  );
  test(
    'message consent is independent of application-policy analytics',
    () async {
      await service.start();
      await service.setMessages(true);
      expect(service.messagesEnabled, isTrue);
      await service.log(UsageEvent.settingsOpened);
      expect(driver.calls, contains('event:settingsOpened'));
      await service.setMessages(false);
      expect(service.messagesEnabled, isFalse);
      expect(service.analyticsEnabled, isTrue);
      await service.log(UsageEvent.updateOpened);
      expect(driver.calls, contains('event:updateOpened'));
      expect(prefs.getBool('firebase.dev.consent.messages'), isFalse);
    },
  );
  test('deletion outranks queued message consent and analytics policy', () async {
    await service.start();
    driver.calls.clear();
    final first = service.setMessages(true);
    final last = service.deletionChanged('subject:request');
    await Future.wait([first, last]);
    expect(driver.calls, isNot(contains('analytics:true')));
    expect(driver.calls, isNot(contains('messages:true')));
    await service.log(UsageEvent.settingsOpened);
    expect(driver.calls, isNot(contains('event:settingsOpened')));
  });
  for (final legacyConsent in [false, true]) {
    test('legacy Analytics preference $legacyConsent is retired', () async {
      await prefs.setBool('firebase.dev.consent.analytics', legacyConsent);
      await service.start();
      expect(service.analyticsEnabled, isTrue);
      expect(driver.calls, contains('analytics:true'));
      expect(prefs.containsKey('firebase.dev.consent.analytics'), isFalse);
      expect(service.messagesEnabled, isFalse);
      expect(service.pushEnabled, isFalse);
    });
  }
  test('permission denial never binds or enables push', () async {
    await service.start();
    await service.accountChanged(const PushAccount('A', 'bearerA'));
    driver.granted = false;
    await service.setPush(true);
    expect(service.pushEnabled, isFalse);
    expect(tokens.owners, isEmpty);
  });
  test('signed out cannot request permission or bind', () async {
    await service.start();
    await service.setPush(true);
    expect(driver.calls, isNot(contains('permission:true')));
    expect(tokens.owners, isEmpty);
  });
  test(
    'soft admission recheck pauses registration without discarding consent',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'bearerA'));
      await service.setPush(true);
      final before = tokens.revocations;
      await service.accountChanged(
        const PushAccount('A', 'bearerA'),
        admitted: false,
      );
      await service.resume();
      expect(service.pushEnabled, isTrue);
      expect(tokens.owners, hasLength(1));
      expect(tokens.revocations, before);
      await service.accountChanged(null);
      expect(service.pushEnabled, isFalse);
    },
  );
  test(
    'explicit opt-in binds captured bearer; revoke cleans server and native token',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'bearerA'));
      await service.setPush(true);
      expect(tokens.owners, ['A:bearerA']);
      final before = tokens.revocations;
      await service.disablePush();
      expect(tokens.revocations, greaterThan(before));
      expect(driver.calls.last, 'delete');
      expect(service.pushEnabled, isFalse);
    },
  );
  test(
    'account A-B-A while permission is pending cannot resurrect opt-in',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'bearerA'));
      driver.delayedPermission = Completer<bool>();
      final enable = service.setPush(true);
      await drain();
      final b = service.accountChanged(const PushAccount('B', 'bearerB'));
      final a = service.accountChanged(const PushAccount('A', 'bearerA'));
      driver.delayedPermission!.complete(true);
      await Future.wait([enable, b, a]);
      expect(tokens.owners, isEmpty);
      expect(service.pushEnabled, isFalse);
    },
  );
  test(
    'account switch during token acquisition cannot bind new account',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'bearerA'));
      driver.delayedToken = Completer<String?>();
      final enable = service.setPush(true);
      await drain();
      final switchAccount = service.accountChanged(
        const PushAccount('B', 'bearerB'),
      );
      driver.delayedToken!.complete('old-token');
      await Future.wait([enable, switchAccount]);
      expect(tokens.owners, isEmpty);
    },
  );
  test(
    'late bind is revoked after logout before another account can enable',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'bearerA'));
      tokens.delayedBind = Completer<void>();
      final enable = service.setPush(true);
      await drain();
      final before = tokens.revocations;
      final logout = service.accountChanged(null);
      tokens.delayedBind!.complete();
      await Future.wait([enable, logout]);
      expect(tokens.owners, ['A:bearerA']);
      expect(tokens.revocations, greaterThan(before));
      expect(service.pushEnabled, isFalse);
    },
  );
  test(
    'failed cleanup prevents new account binding and preserves actionable state',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'bearerA'));
      tokens.failRevoke = true;
      await service.setPush(true);
      expect(tokens.owners, isEmpty);
      expect(service.problem, isNotNull);
    },
  );
  test(
    'OS permission revoked while backgrounded removes binding on resume',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'bearerA'));
      await service.setPush(true);
      driver.granted = false;
      final before = tokens.revocations;
      await service.resume();
      expect(service.pushEnabled, isFalse);
      expect(tokens.revocations, greaterThan(before));
    },
  );
  test(
    'arbitrary notification payload cannot navigate or display sensitive content',
    () async {
      await service.start();
      for (final data in [
        {'route': '/admin/wallets'},
        {'destination': 'https://evil.test'},
        {'destination': '/settings'},
        {'destination': 'settings?admin=true'},
      ]) {
        await service.openNotification(data);
      }
      expect(routes, isEmpty);
      await service.openNotification({
        'destination': 'settings',
        'url': 'https://evil.test',
        'email': 'private',
      });
      expect(routes, ['/settings']);
      expect(diagnostics.join(), isNot(contains('private')));
    },
  );
  test(
    'foreground push only displays fixed allowlisted route when opted in',
    () async {
      await service.start();
      await service.accountChanged(const PushAccount('A', 'bearerA'));
      driver.foreground.add({'destination': 'home'});
      await drain();
      expect(notifications, isEmpty);
      await service.setPush(true);
      driver.foreground.add({'destination': 'home', 'body': 'sensitive'});
      await drain();
      expect(notifications, ['/homePage']);
    },
  );
  test('known block is retained offline and across startup', () async {
    await prefs.setString(
      'firebase.dev.android.release.v1',
      policyJson(blocked: [10]),
    );
    driver.offline = true;
    await service.start();
    await service.refreshReleasePolicy();
    expect(service.decision, ReleaseDecision.blocked);
  });
  test('invalid policy does not clear known block; valid clear does', () async {
    await service.start();
    await service.refreshReleasePolicy();
    driver.raw = policyJson(blocked: [10]);
    await service.refreshReleasePolicy();
    expect(service.decision, ReleaseDecision.blocked);
    driver.raw = '{}';
    await service.refreshReleasePolicy();
    expect(service.decision, ReleaseDecision.blocked);
    driver.raw = policyJson();
    await service.refreshReleasePolicy();
    expect(service.decision, ReleaseDecision.recommended);
  });
  test(
    'empty/missing config defaults safe; production cache cannot block development',
    () async {
      await prefs.setString(
        'firebase.prod.android.release.v1',
        policyJson(blocked: [10]),
      );
      driver.offline = true;
      await service.start();
      await service.refreshReleasePolicy();
      expect(service.decision, ReleaseDecision.allowed);
    },
  );
  test('corrupt cache falls back safely with diagnostic', () async {
    await prefs.setString('firebase.dev.android.release.v1', 'corrupt');
    driver.offline = true;
    await service.start();
    expect(service.decision, ReleaseDecision.allowed);
    expect(diagnostics.first, contains('Invalid cached'));
  });
  test(
    'semantic version boundaries and build blocks are numeric, not lexical',
    () {
      final policy = ReleasePolicy.parse(
        policyJson(minimum: '1.2.0', recommended: '1.10.0', blocked: [42]),
        'android',
      );
      expect(policy.evaluate('1.1.99', '1'), ReleaseDecision.blocked);
      expect(policy.evaluate('1.2.0', '1'), ReleaseDecision.recommended);
      expect(policy.evaluate('1.2.0-beta.1', '1'), ReleaseDecision.blocked);
      expect(policy.evaluate('1.10.0', '1'), ReleaseDecision.allowed);
      expect(policy.evaluate('2.0.0', '42'), ReleaseDecision.blocked);
      expect(policy.evaluate('2.0.0', '43'), ReleaseDecision.allowed);
    },
  );
  test(
    'maintenance takes precedence; malformed policy and dangerous store URLs rejected',
    () {
      expect(
        ReleasePolicy.parse(
          policyJson(maintenance: true),
          'android',
        ).evaluate('2.0.0', '1'),
        ReleaseDecision.maintenance,
      );
      for (final raw in [
        policyJson(blocked: ['42']),
        policyJson(minimum: '9.0.0'),
        policyJson(url: 'javascript:alert(1)'),
        policyJson(url: 'https://play.google.com.evil.test/store/apps/details'),
        policyJson(
          url: 'https://play.google.com/store/apps/details?id=another.app',
        ),
      ]) {
        expect(
          () => ReleasePolicy.parse(raw, 'android'),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
}
