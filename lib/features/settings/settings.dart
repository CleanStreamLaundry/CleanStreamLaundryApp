import 'controller.dart';
import 'package:clean_stream_laundry_app/core/di/di.dart';
import 'package:clean_stream_laundry_app/features/release_controls/firebase_settings.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'widgets/notification_lead.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'widgets/settings_card.dart';
import 'package:clean_stream_laundry_app/features/widgets/base_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class Settings extends StatefulWidget {
  static const int maxNotificationLeadTime =
      SettingsController.maxNotificationLeadTime;

  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late final SettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SettingsController();
    if (getIt.isRegistered<FirebaseService>()) {
      getIt<FirebaseService>().log(UsageEvent.settingsOpened);
    }
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _controller.loadNotificationLeadTime();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showSignOutConfirmation() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Sign Out',
          style: TextStyle(color: Theme.of(ctx).colorScheme.fontInverted),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Theme.of(ctx).colorScheme.fontInverted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: Theme.of(ctx).brightness == Brightness.dark
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.fontSecondary,
                  )
                : null,
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true && mounted) {
      final router = GoRouter.of(context);
      final auth = _controller.authService;
      await _controller.signOut();
      // Admission can dispose Settings before logout completes. A newer
      // signed-in session must keep its route.
      if (auth.currentSession == null) router.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return BasePage(
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SettingsHeader(),
                    if (getIt.isRegistered<FirebaseService>())
                      FirebaseSettings(service: getIt<FirebaseService>()),
                    const SizedBox(height: 18),
                    _SettingsSection(
                      title: 'Preferences',
                      children: [
                        SettingsCard(
                          icon: Icons.lightbulb_outline,
                          title: Theme.of(context).colorScheme.modeChangerText,
                          onTap: themeManager.toggleTheme,
                          showDivider: true,
                        ),
                        SettingsCard(
                          icon: Icons.timer_outlined,
                          title: 'Notify Before Finish',
                          subtitle:
                              "Minutes you're notified before machine finish",
                          trailingWidth: 118,
                          trailing: _NotificationLeadTrailing(
                            isLoading: _controller.isLoadingDelay,
                            value: _controller.notificationLeadTime,
                            onIncrement: _controller.increment,
                            onDecrement: _controller.decrement,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SettingsSection(
                      title: 'Account',
                      children: [
                        SettingsCard(
                          icon: Icons.mail_outline,
                          title: 'Newsletter',
                          onTap: () => context.go('/newsletter'),
                          showChevron: true,
                          showDivider: true,
                        ),
                        SettingsCard(
                          icon: Icons.receipt_long_outlined,
                          title: 'Top-up refunds',
                          onTap: () => context.go('/topup-refunds'),
                          showChevron: true,
                          showDivider: true,
                        ),
                        SettingsCard(
                          icon: Icons.security_outlined,
                          title: 'Two-factor Authentication',
                          onTap: () => context.go('/security/mfa'),
                          showChevron: true,
                          showDivider: true,
                        ),
                        SettingsCard(
                          icon: Icons.person_outline,
                          title: 'Edit Profile',
                          onTap: () => context.go('/editProfile'),
                          showChevron: true,
                          showDivider: true,
                        ),
                        SettingsCard(
                          icon: Icons.receipt_long_outlined,
                          title: 'Monthly Report',
                          onTap: () async {
                            final transactions = await _controller
                                .getTransactions();
                            if (!context.mounted) {
                              return;
                            }
                            context.push(
                              '/monthlyTransactionHistory',
                              extra: transactions,
                            );
                          },
                          showChevron: true,
                          showDivider: kIsWeb && _controller.canUseAdminWallets,
                        ),
                        if (kIsWeb && _controller.canUseAdminWallets)
                          SettingsCard(
                            icon: Icons.admin_panel_settings_outlined,
                            title: 'Admin Wallets',
                            onTap: () => context.go('/admin/wallets'),
                            showChevron: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SettingsSection(
                      title: 'Support',
                      children: [
                        SettingsCard(
                          icon: Icons.request_page_outlined,
                          title: 'Request Refund',
                          onTap: () => context.push('/refundPage'),
                          showChevron: true,
                          showDivider: true,
                        ),
                        SettingsCard(
                          icon: Icons.handyman_outlined,
                          title: 'Facility Maintenance',
                          onTap: () => context.push('/maintenancePage'),
                          showChevron: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SettingsSection(
                      title: 'Legal',
                      children: [
                        SettingsCard(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Privacy Policy',
                          onTap: () => context.push('/legal/privacy'),
                          showChevron: true,
                          showDivider: true,
                        ),
                        SettingsCard(
                          icon: Icons.description_outlined,
                          title: 'Terms of Service',
                          onTap: () => context.push('/legal/terms'),
                          showChevron: true,
                          showDivider: true,
                        ),
                        SettingsCard(
                          icon: Icons.card_membership_outlined,
                          title: 'Loyalty Card Terms',
                          onTap: () => context.push('/legal/loyalty-card'),
                          showChevron: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SettingsSection(
                      title: 'Session',
                      children: [
                        SettingsCard(
                          icon: Icons.logout,
                          title: 'Sign Out',
                          onTap: _showSignOutConfirmation,
                          isDestructive: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Settings',
        textAlign: TextAlign.left,
        style: TextStyle(
          color: Theme.of(context).colorScheme.fontSecondary,
          fontSize: 28,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: isDark
                  ? colorScheme.fontSecondary
                  : colorScheme.fontSecondary.withValues(alpha: 0.68),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.20 : 0.14,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.12),
                blurRadius: 24,
                spreadRadius: -6,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.04),
                blurRadius: 6,
                spreadRadius: -2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _NotificationLeadTrailing extends StatelessWidget {
  final bool isLoading;
  final int value;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _NotificationLeadTrailing({
    required this.isLoading,
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: NotificationLead(
        value: value,
        onIncrement: onIncrement,
        onDecrement: onDecrement,
      ),
    );
  }
}
