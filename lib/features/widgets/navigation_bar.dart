import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NavBar extends StatelessWidget {
  static const TextStyle _labelStyle = TextStyle(fontSize: 12, height: 1);

  static const List<_NavDestination> _destinations = [
    _NavDestination(
      route: '/homePage',
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      routePrefixes: ['/homePage'],
    ),
    _NavDestination(
      route: '/startPage',
      label: 'Start',
      icon: Icons.local_laundry_service_outlined,
      activeIcon: Icons.local_laundry_service_rounded,
      routePrefixes: ['/start', '/startPage', '/scanner', '/paymentPage'],
    ),
    _NavDestination(
      route: '/loyalty',
      label: 'Wallet',
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      routePrefixes: ['/loyalty'],
    ),
    _NavDestination(
      route: '/settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      routePrefixes: ['/settings', '/monthlyTransactionHistory', '/refundPage'],
    ),
  ];

  const NavBar({super.key});

  int _getIndex(String location) {
    for (var i = 0; i < _destinations.length; i++) {
      final destination = _destinations[i];
      if (destination.routePrefixes.any(location.startsWith)) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    final location = router.routeInformationProvider.value.uri.toString();
    final currentIndex = _getIndex(location);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Material(
      color: colorScheme.surface,
      elevation: 12,
      // BottomNavigationBar reserves the system navigation inset itself.
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        backgroundColor: colorScheme.surface,
        selectedItemColor: isDark
            ? colorScheme.fontInverted
            : colorScheme.primary,
        unselectedItemColor: isDark
            ? colorScheme.fontSecondary
            : Colors.grey.shade600,
        selectedIconTheme: isDark
            ? IconThemeData(color: colorScheme.primary)
            : null,
        unselectedIconTheme: isDark
            ? IconThemeData(color: Colors.grey.shade600)
            : null,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        selectedLabelStyle: _labelStyle.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: _labelStyle,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        onTap: (index) {
          final route = _destinations[index].route;
          if (!location.startsWith(route)) {
            context.go(route);
          }
        },
        items: _destinations
            .map(
              (destination) => BottomNavigationBarItem(
                icon: Icon(destination.icon),
                activeIcon: Icon(destination.activeIcon),
                label: destination.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _NavDestination {
  final String route;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final List<String> routePrefixes;

  const _NavDestination({
    required this.route,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.routePrefixes,
  });
}
