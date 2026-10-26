import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:get_it/get_it.dart';

class AppNotification {
  final int id;
  final String title;
  final String body;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
  });
}

class NotificationService {
  final flutterLocalNotificationsPlugin =
      GetIt.instance<FlutterLocalNotificationsPlugin>();

  final profileService = GetIt.instance<ProfileService>();
  final List<AppNotification> _pendingNotifications = [];
  void Function(String)? onPushOpened;
  late final Future<void> initialized;

  NotificationService() {
    initialized = _init();
    // Lazy optional bootstrap must not surface an unhandled initialization error.
    // Explicit display callers still observe failure by awaiting initialized.
    initialized.catchError((Object _) {});
  }

  Future<bool> _requestPermission() async {
    // iOS permission
    if (Platform.isIOS) {
      final ios = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final result = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return result ?? false;
    }

    //Android permission
    final status = await Permission.notification.status;
    if (status.isGranted) {
      return true;
    }

    final result = await Permission.notification.request();
    return result.isGranted;
  }

  Future<void> _init() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route == '/homePage' || route == '/settings') onPushOpened?.call(route!);
      },
    );

    const channel = AndroidNotificationChannel(
      'your_channel_id',
      'Your Channel',
      description: 'General notifications',
      importance: Importance.high,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    final launch = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    final route = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true &&
        (route == '/homePage' || route == '/settings')) {
      onPushOpened?.call(route!);
    }
  }

  Future<void> showPushNotification(String route) async {
    if (route != '/homePage' && route != '/settings') return;
    await initialized;
    await flutterLocalNotificationsPlugin.show(
      id: 2147483000, title: 'Clean Stream', body: 'An update is available in the app.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('your_channel_id', 'Your Channel',
          importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ), payload: route,
    );
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required Duration delay,
  }) async {
    final allowed = await _requestPermission();
    if (!allowed) {
      return;
    }

    _rememberPendingNotification(
      AppNotification(id: id, title: title, body: body),
    );

    Future.delayed(delay, () async {
      _removePendingNotification(id);
      await flutterLocalNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'your_channel_id',
            'Your Channel',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    });
  }

  Future<void> scheduleEarlyMachineNotification({
    required int id,
    required Duration machineTime,
    required String machineName,
  }) async {
    final allowed = await _requestPermission();
    if (!allowed) return;

    final userLeadTime = await profileService.getNotificationLeadTime();
    final userLeadMinutes = Duration(minutes: userLeadTime);

    Duration arrivalTime = machineTime - userLeadMinutes;

    String notifTitle;
    String notifBody;

    if (arrivalTime.isNegative) {
      arrivalTime = Duration.zero;
      notifTitle = "Machine Started!";
      final roundedTime = machineTime.inMinutes;
      final unit = roundedTime == 1 ? "minute" : "minutes";
      notifBody = "$machineName will be finished in $roundedTime $unit!";
    } else if (userLeadTime == 0) {
      notifTitle = "Machine Finished!";
      notifBody = "$machineName is finished";
    } else {
      notifTitle = "Machine Almost Ready";

      final unit = userLeadTime == 1 ? "minute" : "minutes";
      notifBody = "$machineName will be finished in $userLeadTime $unit!";
    }

    _rememberPendingNotification(
      AppNotification(id: id, title: notifTitle, body: notifBody),
    );

    Future.delayed(arrivalTime, () async {
      _removePendingNotification(id);
      await flutterLocalNotificationsPlugin.show(
        id: id,
        title: notifTitle,
        body: notifBody,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'your_channel_id',
            'Your Channel',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    });
  }

  Future<List<AppNotification>> getPendingNotifications() async {
    final scheduledRequests = await flutterLocalNotificationsPlugin
        .pendingNotificationRequests();

    final notificationsById = <int, AppNotification>{
      for (final notification in _pendingNotifications)
        notification.id: notification,
    };

    for (final request in scheduledRequests) {
      notificationsById.putIfAbsent(
        request.id,
        () => AppNotification(
          id: request.id,
          title: request.title ?? 'Notification',
          body: request.body ?? '',
        ),
      );
    }

    return notificationsById.values.toList(growable: false);
  }

  void _rememberPendingNotification(AppNotification notification) {
    _pendingNotifications.removeWhere((item) => item.id == notification.id);
    _pendingNotifications.add(notification);
  }

  void _removePendingNotification(int id) {
    _pendingNotifications.removeWhere((item) => item.id == id);
  }
}
