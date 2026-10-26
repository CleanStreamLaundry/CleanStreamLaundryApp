import 'package:app_links/app_links.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/features/admission/gate.dart';
import 'package:clean_stream_laundry_app/features/admin_wallets/admin_wallets.dart';
import 'package:clean_stream_laundry_app/features/change_email_verification/change_email_verification.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/cortina_payment.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/edit_profile.dart';
import 'package:clean_stream_laundry_app/features/legal/legal_page.dart';
import 'package:clean_stream_laundry_app/features/verify_code/verify_code.dart';
import 'package:clean_stream_laundry_app/features/email_verification/email_verification.dart';
import 'package:clean_stream_laundry_app/features/home/home.dart';
import 'package:clean_stream_laundry_app/features/loading/controller.dart';
import 'package:clean_stream_laundry_app/features/loading/loading.dart';
import 'package:clean_stream_laundry_app/features/loyalty/loyalty.dart';
import 'package:clean_stream_laundry_app/features/scanner/scanner.dart';
import 'package:clean_stream_laundry_app/features/sign_up/sign_up.dart';
import 'package:clean_stream_laundry_app/features/login/login.dart';
import 'package:clean_stream_laundry_app/features/not_found/not_found.dart';
import 'package:clean_stream_laundry_app/features/newsletter/newsletter_page.dart';
import 'package:clean_stream_laundry_app/features/topup_refunds/topup_refunds.dart';
import 'package:clean_stream_laundry_app/features/settings/settings.dart';
import 'package:clean_stream_laundry_app/features/start_machine/start_machine.dart';
import 'package:clean_stream_laundry_app/features/machine_payment/machine_payment.dart';
import 'package:clean_stream_laundry_app/features/monthly_report/monthly_report.dart';
import 'package:clean_stream_laundry_app/features/refund_request/refund_request.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/maintenance_request.dart';
import 'package:clean_stream_laundry_app/features/password_reset/password_reset.dart';
import 'package:clean_stream_laundry_app/features/reset_protected/reset_protected.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'web_callback_stub.dart'
    if (dart.library.js_interop) 'web_callback_web.dart';

class RouterService {
  GoRouter createRouter(
    AuthService authenticator, {
    AppLinks? appLinks,
    AdmissionController? admission,
    ProfileService? profiles,
  }) {
    assert((admission == null) == (profiles == null));
    late final GoRouter router;
    final homePageKey = GlobalKey<HomePageState>();
    var webCallback = takeWebAuthCallback();
    final hasWebCallback = webCallback != null;
    String? lastCallback = webCallback == null
        ? null
        : LoadingPageController.deepLinkLocation(webCallback);
    Uri? lastCallbackUri = webCallback;
    var initialLinkRead = hasWebCallback;

    String callbackLocation(String location, {Uri? originalUri}) {
      // Native/initial delivery may report the same single-use code twice.
      final isPlainRecovery =
          location == '/auth-callback/reset-protected' ||
          location == '/auth-callback/email-verification';
      if (!isPlainRecovery && lastCallback == location) {
        return router.routerDelegate.currentConfiguration.uri.toString();
      }
      lastCallback = location;
      lastCallbackUri = originalUri;
      return location;
    }

    final routes = <RouteBase>[
      for (final path in ['/admission', '/security/mfa'])
        GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const Login(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: SignUpPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/scanner',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: ScannerPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/pay',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: CortinaPaymentPage(
            machineToken: state.uri.queryParameters['machine'],
            terminalId: state.uri.queryParameters['terminal'],
            uniQr: state.uri.queryParameters['uniqr'],
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/loading',
        pageBuilder: (context, state) {
          final controller = LoadingPageController(
            authService: authenticator,
            appLinks: appLinks,
            initialUri: webCallback ?? (initialLinkRead ? Uri() : null),
            forwardInitialLink: webCallback == null,
          );
          webCallback = null;
          initialLinkRead = true;
          return NoTransitionPage(
            key: state.pageKey,
            child: LoadingPage(controller: controller),
          );
        },
      ),
      for (final callback in [
        'oauth',
        'change-email',
        'reset-protected',
        'email-verification',
      ])
        GoRoute(
          path: '/auth-callback/$callback',
          pageBuilder: (context, state) {
            final originalUri =
                lastCallback == state.uri.toString() && lastCallbackUri != null
                ? lastCallbackUri!
                : state.uri.replace(
                    scheme: 'clean-stream',
                    host: callback,
                    path: '',
                  );
            return NoTransitionPage(
              key: state.pageKey,
              child: LoadingPage(
                key: ValueKey(state.uri),
                controller: LoadingPageController(
                  authService: authenticator,
                  appLinks: appLinks,
                  initialUri: originalUri,
                ),
              ),
            );
          },
        ),
      GoRoute(path: '/newsletter', builder: (_, _) => const NewsletterPage()),
      GoRoute(
        path: '/topup-refunds',
        builder: (context, _) {
          Widget page() => TopupRefundsPage(
            active: admission?.canUseTopupRefunds ?? false,
            onBack: () => context.go(
              admission?.canEnterHome == true ? '/loyalty' : '/admission',
            ),
          );
          return admission == null
              ? page()
              : ListenableBuilder(
                  listenable: admission,
                  builder: (_, _) => page(),
                );
        },
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) =>
            NoTransitionPage(key: state.pageKey, child: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/homePage',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: HomePage(key: homePageKey),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/startPage',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const StartPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/loyalty',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: LoyaltyPage(
                    openLoadCardOnStart:
                        state.uri.queryParameters['loadCard'] == 'true',
                    onWalletActivity: () {
                      homePageKey.currentState?.refreshAfterWalletActivity();
                    },
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const Settings(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/admin/wallets',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const AdminWalletsPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/legal/privacy',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LegalPage(type: LegalPageType.privacy),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/legal/terms',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LegalPage(type: LegalPageType.terms),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/legal/loyalty-card',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LegalPage(type: LegalPageType.loyaltyCard),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/paymentPage',
        pageBuilder: (context, state) {
          final machineId = state.uri.queryParameters['machineId'] ?? '';
          return CustomTransitionPage(
            key: state.pageKey,
            child: MachinePayment(machineId: machineId),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, _, _, child) => child,
          );
        },
      ),
      GoRoute(
        path: '/email-verification',
        pageBuilder: (context, state) {
          final email = state.extra is String ? state.extra as String : null;
          return CustomTransitionPage(
            key: state.pageKey,
            child: EmailVerificationPage(email: email),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, _, _, child) => child,
          );
        },
      ),
      GoRoute(
        path: '/change-email-verification',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ChangeEmailVerificationPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/monthlyTransactionHistory',
        pageBuilder: (context, state) {
          final transactions = state.extra as List<Map<String, dynamic>>? ?? [];
          return CustomTransitionPage(
            key: state.pageKey,
            child: MonthlyReport(transactions: transactions),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, _, _, child) => child,
          );
        },
      ),
      GoRoute(
        path: '/refundPage',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: RefundPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/maintenancePage',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: MaintenancePage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/editProfile',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: EditProfilePage(onDeletionPending: admission?.invalidate),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/password-reset',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const PasswordResetPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/reset-protected',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: ResetProtectedPage(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, _, _, child) => child,
          );
        },
      ),
      GoRoute(
        path: '/verify-code',
        pageBuilder: (context, state) {
          final email = state.extra as String;
          return CustomTransitionPage(
            key: state.pageKey,
            child: CodeVerificationPage(email: email),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, _, _, child) => child,
          );
        },
      ),
    ];
    const publicPaths = {
      '/login',
      '/signup',
      '/loading',
      '/email-verification',
      '/change-email-verification',
      '/password-reset',
      '/reset-protected',
      '/verify-code',
    };
    bool isPublic(RouteBase route) =>
        route is GoRoute &&
        (publicPaths.contains(route.path) ||
            route.path.startsWith('/auth-callback/') ||
            route.path.startsWith('/legal/'));
    router = GoRouter(
      initialLocation: '/loading',
      overridePlatformDefaultLocation: hasWebCallback,
      routes: admission == null
          ? routes
          : [
              ...routes.where(isPublic),
              ShellRoute(
                builder: (_, state, child) => AdmissionGate(
                  controller: admission,
                  auth: authenticator,
                  profiles: profiles!,
                  location: state.uri.toString(),
                  child: child,
                ),
                routes: routes.where((route) => !isPublic(route)).toList(),
              ),
            ],
      errorBuilder: (context, state) => const NotFound(),
      redirect: (context, state) {
        final uri = state.uri;

        if (uri.hasScheme || uri.hasAuthority) {
          final location = LoadingPageController.deepLinkLocation(uri);
          if (location == null) return '/not-found';
          if (uri.scheme == 'clean-stream') {
            final extra = state.extra;
            return callbackLocation(
              location,
              originalUri:
                  extra is Uri &&
                      LoadingPageController.deepLinkLocation(extra) == location
                  ? extra
                  : uri,
            );
          }
          return location;
        }
        if (uri.path == '/') return uri.replace(path: '/loading').toString();
        if (uri.path == '/loading') {
          final payload = {
            ...uri.queryParameters,
            ...Uri.splitQueryString(uri.fragment),
          };
          if (const [
            'code',
            'access_token',
            'refresh_token',
            'error',
            'error_code',
            'error_description',
          ].any(payload.containsKey)) {
            return callbackLocation(
              uri.replace(path: '/auth-callback/oauth').toString(),
            );
          }
        }
        return null;
      },
    );
    return router;
  }
}
