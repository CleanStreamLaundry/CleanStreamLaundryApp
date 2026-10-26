import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';

class MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

class MockAndroidPlugin extends Mock
    implements AndroidFlutterLocalNotificationsPlugin {}

class MockIOSPlugin extends Mock
    implements IOSFlutterLocalNotificationsPlugin {}

class MockProfileService extends Mock implements ProfileService {}

class FakeInit extends Fake implements InitializationSettings {}

class FakeAndroidInit extends Fake implements AndroidInitializationSettings {}

class FakeIOSInit extends Fake implements DarwinInitializationSettings {}

class FakeNotifDetails extends Fake implements NotificationDetails {}

class FakeAndroidNotifDetails extends Fake
    implements AndroidNotificationDetails {}

class FakeIOSNotifDetails extends Fake implements DarwinNotificationDetails {}

class FakeChannel extends Fake implements AndroidNotificationChannel {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  setUpAll(() {
    registerFallbackValue(FakeInit());
    registerFallbackValue(FakeAndroidInit());
    registerFallbackValue(FakeIOSInit());
    registerFallbackValue(FakeNotifDetails());
    registerFallbackValue(FakeAndroidNotifDetails());
    registerFallbackValue(FakeIOSNotifDetails());
    registerFallbackValue(FakeChannel());
  });

  late MockPlugin mockPlugin;
  late MockAndroidPlugin mockAndroid;
  late MockIOSPlugin mockIOS;
  late MockProfileService mockProfile;

  setUp(() {
    GetIt.I.reset();

    mockPlugin = MockPlugin();
    mockAndroid = MockAndroidPlugin();
    mockIOS = MockIOSPlugin();
    mockProfile = MockProfileService();

    GetIt.I.registerSingleton<FlutterLocalNotificationsPlugin>(mockPlugin);
    GetIt.I.registerSingleton<ProfileService>(mockProfile);

    when(
      () => mockPlugin.initialize(
        settings: any(named: 'settings'),
        onDidReceiveNotificationResponse: any(
          named: 'onDidReceiveNotificationResponse',
        ),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockPlugin.getNotificationAppLaunchDetails(),
    ).thenAnswer((_) async => null);

    when(
      () => mockPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >(),
    ).thenReturn(mockAndroid);

    when(
      () => mockPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >(),
    ).thenReturn(mockIOS);

    when(
      () => mockAndroid.createNotificationChannel(any()),
    ).thenAnswer((_) async {});

    when(
      () => mockIOS.requestPermissions(
        alert: any(named: 'alert'),
        badge: any(named: 'badge'),
        sound: any(named: 'sound'),
      ),
    ).thenAnswer((_) async => true);

    when(
      () => mockPlugin.show(
        id: any(named: 'id'), title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockPlugin.pendingNotificationRequests(),
    ).thenAnswer((_) async => const []);

    when(
      () => mockProfile.getNotificationLeadTime(),
    ).thenAnswer((_) async => 5);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
          if (call.method == 'checkPermissionStatus') return 1;
          if (call.method == 'requestPermissions') return {17: 1};
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
  });

  test('initialization preserves opt-in permissions and timezone data', () async {
    final service = NotificationService();
    await service.initialized;
    final settings = verify(() => mockPlugin.initialize(
      settings: captureAny(named: 'settings'),
      onDidReceiveNotificationResponse: any(named: 'onDidReceiveNotificationResponse'),
    )).captured.single as InitializationSettings;
    expect(settings.iOS!.requestAlertPermission, isFalse);
    expect(settings.iOS!.requestBadgePermission, isFalse);
    expect(settings.iOS!.requestSoundPermission, isFalse);
    expect(settings.android!.defaultIcon, '@mipmap/ic_launcher');
    final location = tz.getLocation('America/Indiana/Indianapolis');
    expect(tz.TZDateTime(location, 2026, 1, 1).timeZoneOffset,
        const Duration(hours: -5));
    expect(tz.TZDateTime(location, 2026, 7, 1).timeZoneOffset,
        const Duration(hours: -4));
  });

  test('push display preserves generic content and route allowlist', () async {
    final service = NotificationService();
    await service.showPushNotification('/homePage');
    await service.showPushNotification('/settings');
    await service.showPushNotification('/untrusted');
    final routes = verify(() => mockPlugin.show(
      id: 2147483000, title: 'Clean Stream',
      body: 'An update is available in the app.',
      notificationDetails: any(named: 'notificationDetails'),
      payload: captureAny(named: 'payload'),
    )).captured;
    expect(routes, ['/homePage', '/settings']);
  });

  for (final granted in [false, true]) {
    testWidgets('notification request result granted=$granted controls reminders',
        (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, (call) async {
        calls.add(call);
        if (call.method == 'checkPermissionStatus') return 0;
        if (call.method == 'requestPermissions') return {17: granted ? 1 : 0};
        throw StateError('Unexpected permission call: ${call.method}');
      });
      final service = NotificationService();
      await service.initialized;
      await service.scheduleNotification(id: 9, title: 'Title', body: 'Body',
          delay: const Duration(minutes: 1));
      expect(calls.map((call) => call.method),
          ['checkPermissionStatus', 'requestPermissions']);
      expect(calls.last.arguments, [17]);
      expect(await service.getPendingNotifications(), hasLength(granted ? 1 : 0));
      await tester.pump(const Duration(minutes: 1));
      Future<void> show() => mockPlugin.show(id: 9, title: 'Title', body: 'Body',
          notificationDetails: any(named: 'notificationDetails'));
      if (granted) {
        verify(show).called(1);
      } else {
        verifyNever(show);
      }
      expect(await service.getPendingNotifications(), isEmpty);
    });
  }

  testWidgets("scheduleNotification triggers .show() after delay", (
    tester,
  ) async {
    final service = NotificationService();

    await service.scheduleNotification(
      id: 1,
      title: "Test Title",
      body: "Test Body",
      delay: const Duration(minutes: 5),
    );

    await tester.pump(const Duration(minutes: 5));

    verify(
      () => mockPlugin.show(id: 1, title: "Test Title", body: "Test Body",
        notificationDetails: any(named: 'notificationDetails')),
    ).called(1);
  });

  testWidgets("equal machineTime and leadTime → Machine Almost Ready", (
    tester,
  ) async {
    final service = NotificationService();

    when(
      () => mockProfile.getNotificationLeadTime(),
    ).thenAnswer((_) async => 5);

    String name = "TestDryer123";

    await service.scheduleEarlyMachineNotification(
      id: 1,
      machineTime: const Duration(minutes: 5),
      machineName: name,
    );

    await tester.pump(const Duration(milliseconds: 1));

    verify(
      () => mockPlugin.show(
        id: 1,
        title: "Machine Almost Ready",
        body: "$name will be finished in 5 minutes!",
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).called(1);
  });

  testWidgets("machineTime > leadTime → delayed Machine Almost Ready", (
    tester,
  ) async {
    final service = NotificationService();

    when(
      () => mockProfile.getNotificationLeadTime(),
    ).thenAnswer((_) async => 5);

    String name = "TestDryer123";

    await service.scheduleEarlyMachineNotification(
      id: 2,
      machineTime: const Duration(minutes: 20),
      machineName: name,
    );

    await tester.pump(const Duration(minutes: 15));

    verify(
      () => mockPlugin.show(
        id: 2,
        title: "Machine Almost Ready",
        body: "$name will be finished in 5 minutes!",
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).called(1);
  });

  testWidgets("leadTime > machineTime → Machine Started!", (tester) async {
    final service = NotificationService();

    when(
      () => mockProfile.getNotificationLeadTime(),
    ).thenAnswer((_) async => 5);

    String name = "TestDryer123";

    await service.scheduleEarlyMachineNotification(
      id: 3,
      machineTime: const Duration(minutes: 3),
      machineName: name,
    );

    await tester.pump(const Duration(milliseconds: 1));

    verify(
      () => mockPlugin.show(
        id: 3,
        title: "Machine Started!",
        body: "$name will be finished in 3 minutes!",
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).called(1);
  });

  testWidgets("getPendingNotifications returns plugin pending requests", (
    tester,
  ) async {
    when(() => mockPlugin.pendingNotificationRequests()).thenAnswer(
      (_) async => const [
        PendingNotificationRequest(
          7,
          "Machine Almost Ready",
          "Washer 4 will be finished in 5 minutes!",
          null,
        ),
      ],
    );

    final service = NotificationService();
    final pendingNotifications = await service.getPendingNotifications();

    expect(pendingNotifications, hasLength(1));
    expect(pendingNotifications.first.id, 7);
    expect(pendingNotifications.first.title, "Machine Almost Ready");
    expect(
      pendingNotifications.first.body,
      "Washer 4 will be finished in 5 minutes!",
    );
  });
}
