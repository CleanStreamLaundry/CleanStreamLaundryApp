import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

const double _customAppBarHeight = 60;

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final NotificationService? notificationService;
  final Gradient? gradient;

  const CustomAppBar({super.key, this.notificationService, this.gradient});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      toolbarHeight: _customAppBarHeight,
      backgroundColor: colorScheme.primary,
      foregroundColor: Colors.white,
      actionsIconTheme: IconThemeData(color: colorScheme.fontInverted),
      elevation: 0,
      centerTitle: false,
      titleSpacing: 12,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: gradient ?? colorScheme.primaryGradient,
        ),
      ),
      title: InkWell(
        onTap: () => _goTo(context, '/homePage'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset("assets/Icon.png", height: 23),
              const SizedBox(width: 4),
              Flexible(
                child: Image.asset(
                  "assets/Slogan.png",
                  height: 17,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          key: const ValueKey('notifications-button'),
          tooltip: 'Notifications',
          onPressed: () => _showNotificationsSheet(context),
          icon: const Icon(Icons.notifications_none_rounded),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: IconButton(
            key: const ValueKey('settings-button'),
            tooltip: 'Settings',
            onPressed: () => _goTo(context, '/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ),
      ],
    );
  }

  void _goTo(BuildContext context, String route) {
    GoRouter.maybeOf(context)?.go(route);
  }

  void _showNotificationsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: FutureBuilder<List<AppNotification>>(
              future: _loadPendingNotifications(),
              builder: (context, snapshot) {
                final notifications = snapshot.data ?? const [];

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Notifications',
                            style: TextStyle(
                              color: colorScheme.fontInverted,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _goTo(context, '/settings');
                          },
                          child: const Text('Settings'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (notifications.isEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          child: Icon(
                            Icons.notifications_none_rounded,
                            color: colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          'No notifications',
                          style: TextStyle(
                            color: colorScheme.fontInverted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: notifications.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final notification = notifications[index];

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                child: Icon(
                                  Icons.local_laundry_service_outlined,
                                  color: colorScheme.primary,
                                ),
                              ),
                              title: Text(
                                notification.title,
                                style: TextStyle(
                                  color: colorScheme.fontInverted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: notification.body.isEmpty
                                  ? null
                                  : Text(
                                      notification.body,
                                      style: TextStyle(
                                        color: colorScheme.fontSecondary,
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
                    // TODO: Merge Firebase/live notification feed here when
                    // that notification provider is added.
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<List<AppNotification>> _loadPendingNotifications() async {
    final service =
        notificationService ??
        (GetIt.instance.isRegistered<NotificationService>()
            ? GetIt.instance<NotificationService>()
            : null);

    if (service == null) return const [];

    try {
      return service.getPendingNotifications();
    } catch (_) {
      return const [];
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(_customAppBarHeight);
}
