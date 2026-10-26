import 'dart:async';

import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class Profile extends Mock implements ProfileService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const permission = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final permissionCalls = <MethodCall>[];
  String? fail;
  String? coldPayload;
  var granted = false;
  late TargetPlatform? previousPlatform;

  setUp(() {
    previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    permissionCalls.clear();
    fail = null;
    coldPayload = null;
    granted = false;
    GetIt.I.registerSingleton<ProfileService>(Profile());
    GetIt.I.registerSingleton<FlutterLocalNotificationsPlugin>(FlutterLocalNotificationsPlugin());
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == fail) throw PlatformException(code: 'qa-native-error');
      switch (call.method) {
        case 'initialize': return true;
        case 'createNotificationChannel': return null;
        case 'getNotificationAppLaunchDetails':
          return {
            'notificationLaunchedApp': coldPayload != null,
            if (coldPayload != null) 'notificationResponse': {
              'notificationId': 42, 'notificationResponseType': 0,
              'payload': coldPayload,
            },
          };
        case 'show': return null;
        case 'pendingNotificationRequests': return <Map<String, Object>>[];
        default: throw StateError('Unexpected native call: ${call.method}');
      }
    });
    messenger.setMockMethodCallHandler(permission, (call) async {
      permissionCalls.add(call);
      if (call.method == fail) throw PlatformException(code: 'qa-permission-error');
      switch (call.method) {
        case 'checkPermissionStatus':
          expect(call.arguments, 17);
          return 0;
        case 'requestPermissions':
          expect(call.arguments, [17]);
          return {17: granted ? 1 : 0};
        default: throw StateError('Unexpected permission call: ${call.method}');
      }
    });
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = previousPlatform;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(permission, null);
    await GetIt.I.reset();
  });

  Future<void> tap(String? payload) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(
        'didReceiveNotificationResponse', {
          'notificationId': 42, 'notificationResponseType': 0, 'payload': payload,
        },
      )), (_) => done.complete());
    await done.future;
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('real $platform plugin marshals init/show and filters cold/warm payloads', () async {
      debugDefaultTargetPlatformOverride = platform;
      if (platform == TargetPlatform.iOS) IOSFlutterLocalNotificationsPlugin.registerWith();
      coldPayload = '/settings';
      final opened = <String>[];
      final service = NotificationService()..onPushOpened = opened.add;
      await service.initialized;
      expect(opened, ['/settings']);
      final init = calls.first;
      expect(init.method, 'initialize');
      if (platform == TargetPlatform.android) {
        expect(init.arguments['defaultIcon'], '@mipmap/ic_launcher');
        final create = calls.singleWhere((c) => c.method == 'createNotificationChannel');
        expect(create.arguments['id'], 'your_channel_id');
        expect(create.arguments['importance'], 4);
      } else {
        for (final key in ['requestAlertPermission', 'requestBadgePermission', 'requestSoundPermission']) {
          expect(init.arguments[key], false, reason: key);
        }
        expect(calls.any((c) => c.method == 'createNotificationChannel'), false);
      }
      expect(permissionCalls, isEmpty);
      await service.showPushNotification('/homePage');
      await service.showPushNotification('/settings');
      await service.showPushNotification('/untrusted');
      final shows = calls.where((c) => c.method == 'show').toList();
      expect(shows, hasLength(2));
      expect(shows.map((c) => c.arguments['payload']), ['/homePage', '/settings']);
      for (final show in shows) {
        expect(show.arguments['id'], 2147483000);
        expect(show.arguments['title'], 'Clean Stream');
        expect(show.arguments['body'], 'An update is available in the app.');
        final details = show.arguments['platformSpecifics'];
        if (platform == TargetPlatform.android) {
          expect(details['channelId'], 'your_channel_id');
          expect(details['importance'], 4);
          expect(details['priority'], 1);
        } else {
          expect(details['presentAlert'], true);
          expect(details['presentSound'], true);
        }
      }
      for (final payload in ['/homePage', '/settings', '/untrusted', null]) {
        await tap(payload);
      }
      expect(opened, ['/settings', '/homePage', '/settings']);
      coldPayload = '/untrusted';
      final second = NotificationService()..onPushOpened = opened.add;
      await second.initialized;
      expect(opened, ['/settings', '/homePage', '/settings']);
    });
  }

  for (final allow in [false, true]) {
    testWidgets('real plugin reminder permission grant=$allow', (tester) async {
      try {
      granted = allow;
      final service = NotificationService();
      await service.initialized;
      await service.scheduleNotification(id: 9, title: 'Ready', body: 'Washer ready', delay: const Duration(seconds: 1));
      expect(permissionCalls.map((c) => c.method), ['checkPermissionStatus', 'requestPermissions']);
      expect(await service.getPendingNotifications(), hasLength(allow ? 1 : 0));
      await tester.pump(const Duration(seconds: 1));
      final shows = calls.where((c) => c.method == 'show').toList();
      expect(shows, hasLength(allow ? 1 : 0));
      if (allow) {
        expect(shows.single.arguments['id'], 9);
        expect(shows.single.arguments['title'], 'Ready');
        expect(shows.single.arguments['body'], 'Washer ready');
        expect(shows.single.arguments['payload'], '');
      }
      expect(await service.getPendingNotifications(), isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });
  }

  test('native initialization error reaches explicit display without display calls', () async {
    fail = 'initialize';
    final service = NotificationService();
    await expectLater(service.initialized, throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'qa-native-error')));
    await expectLater(service.showPushNotification('/homePage'), throwsA(isA<PlatformException>()));
    expect(calls.map((c) => c.method), ['initialize']);
  });

  test('native show error propagates to caller', () async {
    fail = 'show';
    final service = NotificationService();
    await service.initialized;
    await expectLater(service.showPushNotification('/settings'), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'qa-native-error')));
    expect(calls.where((c) => c.method == 'show'), hasLength(1));
  });

  test('permission channel error propagates without pending or display', () async {
    fail = 'requestPermissions';
    final service = NotificationService();
    await service.initialized;
    await expectLater(service.scheduleNotification(id: 8, title: 'Ready', body: 'Ready', delay: Duration.zero),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'qa-permission-error')));
    expect(await service.getPendingNotifications(), isEmpty);
    expect(calls.where((c) => c.method == 'show'), isEmpty);
  });
}
