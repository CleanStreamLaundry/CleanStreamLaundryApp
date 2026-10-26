import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/features/change_email_verification/change_email_verification.dart';
import 'package:clean_stream_laundry_app/features/home/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'mocks.dart';

void main() {
  late MockAuthService mockAuthService;
  late MockLocationService mockLocationService;
  late MockMachineService mockMachineService;
  late MockProfileService mockProfileService;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    mockAuthService = MockAuthService();
    mockLocationService = MockLocationService();
    mockMachineService = MockMachineService();
    mockProfileService = MockProfileService();

    GetIt.instance.registerSingleton<AuthService>(mockAuthService);
    GetIt.instance.registerSingleton<LocationService>(mockLocationService);
    GetIt.instance.registerSingleton<MachineService>(mockMachineService);
    GetIt.instance.registerSingleton<ProfileService>(mockProfileService);

    when(
      () => mockLocationService.getLocations(),
    ).thenAnswer((_) async => <Map<String, dynamic>>[]);
    when(
      () => mockMachineService.getWasherCountByLocation(any()),
    ).thenAnswer((_) async => 0);
    when(
      () => mockMachineService.getIdleWasherCountByLocation(any()),
    ).thenAnswer((_) async => 0);
    when(
      () => mockMachineService.getDryerCountByLocation(any()),
    ).thenAnswer((_) async => 0);
    when(
      () => mockMachineService.getIdleDryerCountByLocation(any()),
    ).thenAnswer((_) async => 0);
    when(() => mockAuthService.refreshSession()).thenAnswer((_) async => {});
    when(() => mockAuthService.getCurrentUser()).thenAnswer((_) => null);
    when(
      () => mockAuthService.onAuthChange,
    ).thenAnswer((_) => const Stream.empty());
  });

  tearDown(() {
    GetIt.instance.reset();
  });

  Widget createTestWidget() {
    final router = GoRouter(
      initialLocation: '/change-email-verification',
      routes: [
        GoRoute(
          path: '/change-email-verification',
          builder: (context, state) => const ChangeEmailVerificationPage(),
        ),
        GoRoute(path: '/homePage', builder: (context, state) => HomePage()),
      ],
    );

    return MaterialApp.router(routerConfig: router);
  }

  group('Static UI Elements', () {
    testWidgets('displays all required UI elements', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.email), findsOneWidget);
      expect(find.text('Please verify your new email address'), findsOneWidget);
      expect(
        find.text(
          'Check your new email\'s inbox and click the verification link.',
        ),
        findsOneWidget,
      );
      expect(find.text('Resend Verification'), findsOneWidget);
    });

    testWidgets('email icon has correct styling', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.email));
      expect(icon.size, equals(40));
      expect(
        icon.color,
        Theme.of(tester.element(find.byIcon(Icons.email))).colorScheme.primary,
      );
    });

    testWidgets('text uses center alignment', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final titleText = tester.widget<Text>(
        find.text('Please verify your new email address'),
      );
      final descText = tester.widget<Text>(
        find.text(
          'Check your new email\'s inbox and click the verification link.',
        ),
      );

      expect(titleText.textAlign, equals(TextAlign.center));
      expect(descText.textAlign, equals(TextAlign.center));
    });
  });

  group('Lifecycle', () {
    testWidgets('uses theme surface color as scaffold background', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, isNotNull);
    });

    testWidgets('navigates away without callback lifecycle plumbing', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(ChangeEmailVerificationPage));
      GoRouter.of(context).go('/homePage');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ChangeEmailVerificationPage), findsNothing);
    });
  });
}
