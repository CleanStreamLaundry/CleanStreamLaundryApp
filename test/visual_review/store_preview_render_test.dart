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
import '../features/maintenance_request/maintenance_request_test.dart' show MockMaintenanceController;
import 'package:clean_stream_laundry_app/features/loyalty/loyalty.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/maintenance_request.dart';
import 'package:mocktail/mocktail.dart';
import 'real_font_fallback.dart';
import 'secondary_ui_render_test.dart' show loadFonts;

void main() {
  setUpAll(() async { await loadFonts(); registerFallbackValue((_) {}); });
  const size = Size(360, 780);
  const themeName = 'light';
  final theme = lightMode;
  for (final scene in ['wallet', 'support']) {
      testWidgets('store preview $scene', (
        tester,
      ) async {
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
        if (scene == 'wallet') {
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
          when(() => c.recentTransactions).thenReturn(['Washer #2 - \$8.00 - Oct 26, 2026', 'Wallet load - \$32.00 - Oct 26, 2026']);
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
          when(() => c.categories).thenReturn(['Washer/Dryer Maintenance', 'App Maintenance', 'Other']);
          when(() => c.selectedCategory).thenReturn(null);
          when(() => c.isLoading).thenReturn(false);
          when(() => c.generation).thenReturn(0);
          when(() => c.draftKey).thenReturn('store-preview');
          when(() => c.isCurrent(any())).thenReturn(true);
          when(() => c.isFormValid).thenReturn(false);
          when(() => c.selectedImage).thenReturn(null);
          when(() => c.descriptionController).thenReturn(description);
          when(() => c.locations).thenReturn([(id: '1', address: 'Madison Ave.')]);
          when(() => c.selectedLocation).thenReturn(null);
          when(() => c.init()).thenAnswer((_) async {});
          page = MaintenancePage(controller: c);
        }
        final boundary = GlobalKey();
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(path: '/', builder: (_, _) => page),
          ],
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
        await applyRealFontFallback(tester);
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('RENDER_DIR');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 3);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(
              '$output/$scene-$themeName.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
  }
}
