import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

// services
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_communication_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/payment_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/services/admin_wallet_service.dart';

// implementations
import 'package:clean_stream_laundry_app/services/supabase/supabase_auth_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/mfa_verification_client.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_cortina_vend_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_edge_function_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_location_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_machine_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_profile_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_transaction_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_wallet_service.dart';
import 'package:clean_stream_laundry_app/services/supabase/supabase_admin_wallet_service.dart';
import 'package:clean_stream_laundry_app/services/stripe/stripe_service.dart';
import 'package:clean_stream_laundry_app/services/nayax/machine_communicator.dart';

// misc
import 'package:clean_stream_laundry_app/core/router/app_router.dart';
import 'package:clean_stream_laundry_app/features/admission/controller.dart';
import 'package:clean_stream_laundry_app/services/notification_service.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_bootstrap.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:clean_stream_laundry_app/logic/payment/process_payment.dart';

final getIt = GetIt.instance;

PostgrestClient createPublicPolicyClient({
  required String supabaseUrl,
  required String publicKey,
}) => PostgrestClient('$supabaseUrl/rest/v1', headers: {'apikey': publicKey});

MfaVerificationClient createMfaVerificationClient({
  required String supabaseUrl,
  required String publicKey,
  required String accessToken,
}) => MfaVerificationClient(
  supabaseUrl: supabaseUrl,
  publicKey: publicKey,
  accessToken: accessToken,
);

Future<void> setupDependencies() async {
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
  );

  final supabase = Supabase.instance.client;

  Stripe.publishableKey = dotenv.env['STRIPE_PUBLISHABLE_KEY']!;
  await Stripe.instance.applySettings();

  getIt.registerLazySingleton<TransactionService>(
    () => SupabaseTransactionService(client: supabase),
  );

  getIt.registerLazySingleton<ProfileService>(
    () => SupabaseProfileService(
      client: supabase,
      publicPolicyClientFactory: () => createPublicPolicyClient(
        supabaseUrl: dotenv.env['SUPABASE_URL']!,
        publicKey: dotenv.env['ANON_KEY']!,
      ),
    ),
  );

  getIt.registerLazySingleton<MachineService>(
    () => SupabaseMachineService(client: supabase),
  );

  getIt.registerLazySingleton<LocationService>(
    () => SupabaseLocationHandler(client: supabase),
  );

  getIt.registerLazySingleton<EdgeFunctionService>(
    () => SupabaseEdgeFunctionService(client: supabase),
  );

  getIt.registerLazySingleton<AuthService>(
    () => SupabaseAuthService(
      client: supabase,
      googleAuthClientFactory: () => GoTrueClient(
        url: '${dotenv.env['SUPABASE_URL']!}/auth/v1',
        headers: {'apikey': dotenv.env['ANON_KEY']!},
        autoRefreshToken: false,
      ),
      mfaClientFactory: (accessToken) => createMfaVerificationClient(
        supabaseUrl: dotenv.env['SUPABASE_URL']!,
        publicKey: dotenv.env['ANON_KEY']!,
        accessToken: accessToken,
      ),
    ),
  );

  getIt.registerLazySingleton<AdmissionController>(
    () => AdmissionController(
      authService: getIt<AuthService>(),
      profileService: getIt<ProfileService>(),
    ),
    dispose: (controller) => controller.dispose(),
  );

  getIt.registerLazySingleton<CortinaVendService>(
    () => SupabaseCortinaVendService(client: supabase),
  );

  getIt.registerLazySingleton<CortinaPendingStore>(
    () => CortinaPendingStore(project: dotenv.env['SUPABASE_URL']!),
  );

  getIt.registerLazySingleton<PaymentService>(() => StripeService());

  getIt.registerLazySingleton<WalletService>(
    () => SupabaseWalletService(
      client: supabase,
      paymentService: getIt<PaymentService>(),
    ),
  );

  getIt.registerLazySingleton<AdminWalletService>(
    () => SupabaseAdminWalletService(client: supabase),
  );

  getIt.registerLazySingleton<Stripe>(() => Stripe.instance);

  getIt.registerLazySingleton<MachineCommunicationService>(
    () =>
        MachineCommunicator(edgeFunctionService: getIt<EdgeFunctionService>()),
  );

  getIt.registerLazySingleton<RouterService>(() => RouterService());

  getIt.registerLazySingleton<NotificationService>(() => NotificationService());

  getIt.registerSingleton<FlutterLocalNotificationsPlugin>(
    FlutterLocalNotificationsPlugin(),
  );

  getIt.registerLazySingleton<PaymentProcessor>(() => PaymentProcessor());

  getIt.registerLazySingleton<GoRouter>(() {
    final authService = getIt<AuthService>();
    final routerService = getIt<RouterService>();

    return routerService.createRouter(
      authService,
      admission: getIt<AdmissionController>(),
      profiles: getIt<ProfileService>(),
    );
  });

  try {
    final firebase = await FirebaseBootstrap.create(
      auth: getIt<AuthService>(), admission: getIt<AdmissionController>(),
      router: getIt<GoRouter>(), supabaseUrl: dotenv.env['SUPABASE_URL']!,
      publicKey: dotenv.env['ANON_KEY']!,
      notifications: () => getIt<NotificationService>(),
    );
    getIt.registerSingleton<FirebaseBootstrap>(firebase, dispose: (value) => value.dispose());
    getIt.registerSingleton<FirebaseService>(firebase.service);
  } catch (_) {
    if (kDebugMode) debugPrint('Optional Firebase bootstrap unavailable; check local package/config setup.');
  }
}
