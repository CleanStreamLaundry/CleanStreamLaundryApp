import 'package:app_links/app_links.dart';
import 'package:clean_stream_laundry_app/features/admin_wallets/admin_wallets.dart';
import 'package:clean_stream_laundry_app/features/change_email_verification/change_email_verification.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/cortina_payment.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/edit_profile.dart';
import 'package:clean_stream_laundry_app/features/legal/legal_page.dart';
import 'package:clean_stream_laundry_app/features/verify_code/verify_code.dart';
import 'package:clean_stream_laundry_app/features/email_verification/email_verification.dart';
import 'package:clean_stream_laundry_app/features/home/home.dart';
import 'package:clean_stream_laundry_app/features/loading/loading.dart';
import 'package:clean_stream_laundry_app/features/loyalty/loyalty.dart';
import 'package:clean_stream_laundry_app/features/scanner/scanner.dart';
import 'package:clean_stream_laundry_app/features/sign_up/sign_up.dart';
import 'package:clean_stream_laundry_app/features/login/login.dart';
import 'package:clean_stream_laundry_app/features/not_found/not_found.dart';
import 'package:clean_stream_laundry_app/features/settings/settings.dart';
import 'package:clean_stream_laundry_app/features/start_machine/start_machine.dart';
import 'package:clean_stream_laundry_app/features/machine_payment/machine_payment.dart';
import 'package:clean_stream_laundry_app/features/monthly_report/monthly_report.dart';
import 'package:clean_stream_laundry_app/features/refund_request/refund_request.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/maintenance_request.dart';
import 'package:clean_stream_laundry_app/features/password_reset/password_reset.dart';
import 'package:clean_stream_laundry_app/features/reset_protected/reset_protected.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:go_router/go_router.dart';

class RouterService {
  GoRouter createRouter(AuthService authenticator) => GoRouter(
    initialLocation: '/loading',
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: Login(appLinks: AppLinks()),
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
      GoRoute(path: '/loading', builder: (context, state) => LoadingPage()),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: Settings(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/loyalty',
        pageBuilder: (context, state) {
          final openLoadCard = state.uri.queryParameters['loadCard'] == 'true';

          return CustomTransitionPage(
            key: state.pageKey,
            child: LoyaltyPage(openLoadCardOnStart: openLoadCard),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, _, _, child) => child,
          );
        },
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
        path: '/homePage',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: HomePage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/startPage',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: StartPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, _, _, child) => child,
        ),
      ),
      GoRoute(
        path: '/change-email-verification',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: ChangeEmailVerificationPage(appLinks: AppLinks()),
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
          child: EditProfilePage(),
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
    ],
    errorBuilder: (context, state) {
      final uri = state.uri;
      if (uri.scheme == 'clean-stream' && uri.host == 'reset-protected') {
        return ResetProtectedPage();
      }
      return const NotFound();
    },
    redirect: (context, state) {
      final uri = state.uri;

      // Handle clean-stream://reset-protected deep links
      if (uri.scheme == 'clean-stream' && uri.host == 'reset-protected') {
        final query = uri.query;
        return query.isEmpty ? '/reset-protected' : '/reset-protected?$query';
      }

      // Handle clean-stream://email-verification deep links
      if (uri.scheme == 'clean-stream' && uri.host == 'email-verification') {
        return '/email-verification';
      }

      // Handle clean-stream://change-email deep links
      if (uri.scheme == 'clean-stream' && uri.host == 'change-email') {
        // Optional: check type query param
        final type = uri.queryParameters['type'];
        if (type == 'email_change' || type == null) {
          return '/editProfile';
        }
      }

      // Otherwise, no redirect
      return null;
    },
  );
}
