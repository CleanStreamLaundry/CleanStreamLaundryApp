@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../features/start_machine/mocks.dart';
import '../features/loyalty/mocks.dart' show MockLoyaltyController;
import '../features/maintenance_request/maintenance_request_test.dart'
    show MockMaintenanceController;
import 'package:clean_stream_laundry_app/features/loyalty/loyalty.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/maintenance_request.dart';
import 'package:mocktail/mocktail.dart';
import '../features/home/mocks.dart'
    show MockLocationService, MockMachineService, MockWalletService;
import '../features/cortina_payment/cortina_payment_test.dart'
    show MockVendService;
import 'package:clean_stream_laundry_app/features/home/home.dart';
import 'package:clean_stream_laundry_app/features/cortina_payment/cortina_payment.dart';
import 'package:clean_stream_laundry_app/core/storage/cortina_pending_store.dart';
import 'package:clean_stream_laundry_app/logic/models/cortina_vend.dart';
import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';
import 'package:clean_stream_laundry_app/logic/models/wallet_balance.dart';
import 'package:clean_stream_laundry_app/logic/services/location_service.dart';
import 'package:clean_stream_laundry_app/logic/services/machine_service.dart';
import 'package:clean_stream_laundry_app/logic/services/wallet_service.dart';
import 'package:clean_stream_laundry_app/logic/services/cortina_vend_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'real_font_fallback.dart';
import 'secondary_ui_render_test.dart' show loadFonts;

void main() {
  setUpAll(() async {
    await loadFonts();
    registerFallbackValue((_) {});
    final directory = await Directory.systemTemp.createTemp(
      'store-map-render-',
    );
    final cache = BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: directory.path,
      maxCacheSize: null,
      readOnly: true,
    );
    addTearDown(() => cache.destroy(deleteCache: true));
  });
  const size = Size(360, 780);
  const themeName = 'light';
  final theme = lightMode;
  for (final scene in ['home', 'payment', 'wallet', 'support']) {
    testWidgets('store preview $scene', (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = previousShadows);
      await GetIt.I.reset();
      GetIt.I.registerSingleton<AuthService>(MockAuthService());
      GetIt.I.registerSingleton<ProfileService>(MockProfileService());
      addTearDown(GetIt.I.reset);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      late Widget page;
      if (scene == 'home' || scene == 'payment') {
        final auth = GetIt.I<AuthService>();
        final profile = GetIt.I<ProfileService>();
        final wallet = MockWalletService();
        GetIt.I.registerSingleton<WalletService>(wallet);
        when(() => auth.getCurrentUserId).thenReturn('store-preview-alex');
        when(() => auth.onAuthChange).thenAnswer((_) => const Stream.empty());
        when(
          () => auth.authStateChanges,
        ).thenAnswer((_) => const Stream.empty());
        when(
          () => profile.getUserBalanceById('store-preview-alex'),
        ).thenAnswer((_) async => {'full_name': 'Alex Morgan'});
        when(() => wallet.getBalance()).thenAnswer(
          (_) async => const WalletBalance(
            walletAccountId: 'preview-wallet',
            status: 'active',
            paidBalanceCents: 2400,
            promoBalanceCents: 0,
            totalBalanceCents: 2400,
          ),
        );
        if (scene == 'home') {
          // Only public OSM tile reads are real; identity, balances and machine
          // counts are fictional fixtures. No app backend or payment request.
          final previousHttp = HttpOverrides.current;
          HttpOverrides.global = _StoreMapHttpOverrides();
          addTearDown(() => HttpOverrides.global = previousHttp);
          SharedPreferences.setMockInitialValues({
            'lastSelectedLocationId': '1',
            'lastSelectedLocation': 'Columbus Ave.',
            'locationSelectionMode': 'manual',
          });
          final locations = MockLocationService();
          final machines = MockMachineService();
          GetIt.I.registerSingleton<LocationService>(locations);
          GetIt.I.registerSingleton<MachineService>(machines);
          when(() => locations.getLocations()).thenAnswer(
            (_) async => [
              {
                'id': 1,
                'Name': 'Columbus Ave.',
                'Address': '5107 South Columbus Ave., Anderson, IN',
                'Latitude': 40.06415,
                'Longitude': -85.66733,
              },
            ],
          );
          when(() => machines.getAvailability(1)).thenAnswer(
            (_) async => MachineAvailability(
              washers: const MachineAvailabilityCount(
                total: 8,
                available: 5,
                busy: 3,
                unknown: 0,
              ),
              dryers: const MachineAvailabilityCount(
                total: 8,
                available: 6,
                busy: 2,
                unknown: 0,
              ),
              checkedAt: DateTime.now(),
              configured: true,
            ),
          );
          page = const HomePage();
        } else {
          FlutterSecureStorage.setMockInitialValues({});
          GetIt.I.registerSingleton<CortinaPendingStore>(
            CortinaPendingStore(project: 'https://store-preview.invalid'),
          );
          final vend = MockVendService();
          GetIt.I.registerSingleton<CortinaVendService>(vend);
          when(
            () => vend.quote(
              machineToken: 'store-preview',
              terminalId: null,
              uniQr: null,
            ),
          ).thenAnswer(
            (_) async => const CortinaQuote(
              machineId: 2,
              machineName: 'Washer 2',
              machineType: 'washer',
              washerSizeLabel: '12 kg',
              amountCents: 800,
              dryerDefaultCents: 150,
              dryerOptions: [],
            ),
          );
          page = const CortinaPaymentPage(
            machineToken: 'store-preview',
            terminalId: null,
            uniQr: null,
          );
        }
      } else if (scene == 'wallet') {
        final c = MockLoyaltyController();
        when(() => c.isLoading).thenReturn(false);
        when(() => c.isCurrentAccount).thenReturn(true);
        when(() => c.accountEpoch).thenReturn(1);
        when(() => c.isRefreshing).thenReturn(false);
        when(() => c.isPaying).thenReturn(false);
        when(() => c.isLoadingMore).thenReturn(false);
        when(() => c.isLoadingRewards).thenReturn(false);
        when(() => c.hasMoreTransactions).thenReturn(false);
        when(() => c.hasMoreRewards).thenReturn(false);
        when(() => c.errorMessage).thenReturn(null);
        when(() => c.userName).thenReturn('Alex Morgan');
        when(() => c.userBalance).thenReturn(24.00);
        when(() => c.paidBalance).thenReturn(24.00);
        when(() => c.promoBalance).thenReturn(0.00);
        when(() => c.userReward).thenReturn(0.0);
        when(() => c.recentTransactions).thenReturn([
          'Washer #2 - \$8.00 - Oct 26, 2026',
          'Wallet load - \$32.00 - Oct 26, 2026',
        ]);
        when(() => c.rewardTransactions).thenReturn([]);
        when(() => c.showPastTransactions).thenReturn(false);
        when(() => c.initialize()).thenAnswer((_) async {});
        when(() => c.refresh(ifStale: true)).thenAnswer((_) async {});
        page = LoyaltyPage(controller: c);
      } else {
        final c = MockMaintenanceController();
        final description = TextEditingController();
        addTearDown(description.dispose);
        when(() => c.attemptedSubmit).thenReturn(false);
        when(
          () => c.categories,
        ).thenReturn(['Washer/Dryer Maintenance', 'App Maintenance', 'Other']);
        when(() => c.selectedCategory).thenReturn(null);
        when(() => c.isLoading).thenReturn(false);
        when(() => c.generation).thenReturn(0);
        when(() => c.draftKey).thenReturn('store-preview');
        when(() => c.isCurrent(any())).thenReturn(true);
        when(() => c.isFormValid).thenReturn(false);
        when(() => c.selectedImage).thenReturn(null);
        when(() => c.descriptionController).thenReturn(description);
        when(
          () => c.locations,
        ).thenReturn([(id: '1', address: 'Madison Ave.')]);
        when(() => c.selectedLocation).thenReturn(null);
        when(() => c.init()).thenAnswer((_) async {});
        page = MaintenancePage(controller: c);
      }
      final route = {
        'home': '/homePage',
        'payment': '/paymentPage',
        'wallet': '/loyalty',
        'support': '/maintenancePage',
      }[scene]!;
      final boundary = GlobalKey();
      final router = GoRouter(
        initialLocation: route,
        routes: [GoRoute(path: route, builder: (_, _) => page)],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
            ),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await tester.runAsync(() => precacheImage(image.image, element));
      }
      await tester.pumpAndSettle();
      if (scene == 'home') {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (PaintingBinding.instance.imageCache.pendingImageCount > 0 &&
            DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }
      if (scene == 'payment') {
        await tester.tap(find.text('Loyalty wallet'));
        await tester.pumpAndSettle();
        expect(find.text(r'Pay $8.00'), findsOneWidget);
      }
      await applyRealFontFallback(tester);
      expect(tester.takeException(), isNull);
      const output = String.fromEnvironment('RENDER_DIR');
      if (output.isNotEmpty) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/$scene-$themeName.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
      debugDisableShadows = previousShadows;
    });
  }
}

// Uses normal TLS verification and environment proxy handling; rejects every
// network destination except the same public map tile host used by HomePage.
class _StoreMapHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 10);
    client.findProxy = (uri) {
      if (uri.scheme != 'https' || uri.host != 'tile.openstreetmap.org') {
        throw StateError('Only public map tiles are allowed in this render');
      }
      return HttpClient.findProxyFromEnvironment(uri);
    };
    return client;
  }
}
