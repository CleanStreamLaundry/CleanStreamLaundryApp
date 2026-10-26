@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/home/controller.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/header.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/location_selector.dart';
import 'package:clean_stream_laundry_app/features/home/widgets/availability_card.dart';
import 'package:clean_stream_laundry_app/features/monthly_report/monthly_report.dart';
import 'package:clean_stream_laundry_app/features/newsletter/newsletter_page.dart';
import 'package:clean_stream_laundry_app/features/not_found/not_found.dart';
import 'package:clean_stream_laundry_app/features/scanner/widgets/scanner_overlay.dart';
import 'package:clean_stream_laundry_app/features/widgets/status_dialog_box.dart';
import 'package:clean_stream_laundry_app/logic/models/machine_availability.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import '../features/newsletter/fixtures.dart';
import 'real_font_fallback.dart';

class _Home extends Mock implements HomePageController {}

void main() {
  setUpAll(() async {
    final config = File('.dart_tool/package_config.json');
    final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
    final flutter = Directory.fromUri(
      config.absolute.uri.resolve(
        packages.singleWhere((p) => p['name'] == 'flutter')['rootUri']
            as String,
      ),
    ).uri;
    for (final family in {
      'Roboto': ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'],
      'MaterialIcons': ['MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final name in family.value) {
        loader.addFont(
          File.fromUri(
            flutter.resolve('../../bin/cache/artifacts/material_fonts/$name'),
          ).readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
    }
  });

  for (final theme in [lightMode, darkMode]) {
    for (final name in [
      'home-cards',
      'monthly-history',
      'newsletter',
      'not-found',
      'status-success',
      'status-error',
      'scanner-overlay',
    ]) {
      testWidgets('$name ${theme.brightness.name} real-font render', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
        addTearDown(tester.view.reset);
        await GetIt.I.reset();
        final newsletter = NewsletterFixture();
        GetIt.I.registerSingleton<AuthService>(newsletter.auth);
        final home = _Home();
        when(() => home.username).thenReturn('Alex');
        when(() => home.balance).thenReturn({'balance': 52.0});
        when(() => home.locationSelected).thenReturn(true);
        when(
          () => home.selectedName,
        ).thenReturn('123 Main Street, Columbus, IN');
        when(() => home.locationIDSelected).thenReturn(1);
        when(() => home.isNearestSelection).thenReturn(true);
        when(() => home.accountId).thenReturn('fixture-account');
        when(() => home.accountEpoch).thenReturn(1);
        when(() => home.locations).thenReturn([
          {
            'id': 1,
            'Address': '123 Main Street, Columbus, IN',
            'Name': 'Clean Stream Columbus',
            'Hours': '6 AM - 10 PM',
            'IsOpen': true,
            'DistanceMiles': 1.2,
          },
        ]);
        when(() => home.getAvailability()).thenAnswer(
          (_) async => MachineAvailability(
            washers: const MachineAvailabilityCount(
              total: 16,
              available: 12,
              busy: 4,
              unknown: 0,
            ),
            dryers: const MachineAvailabilityCount(
              total: 16,
              available: 10,
              busy: 6,
              unknown: 0,
            ),
            checkedAt: DateTime(2026, 10, 3, 9, 30),
            configured: true,
          ),
        );
        final page = switch (name) {
          'home-cards' => Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ColoredBox(
                      color: theme.colorScheme.primary,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Header(controller: home, onAddFunds: () {}),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LocationSelector(controller: home, onGetDirections: () {}),
                    const SizedBox(height: 16),
                    AvailabilityCard(controller: home),
                  ],
                ),
              ),
            ),
          ),
          'monthly-history' => MonthlyReport(
            transactions: [
              for (final row in [
                ('Washer #5', 7.5),
                ('Dryer #3', 4.25),
                ('loyalty card', 50.0),
                ('loyalty washer', 6.0),
              ])
                {
                  'created_at': '2026-09-02T12:00:00',
                  'description': row.$1,
                  'amount': row.$2,
                },
            ],
          ),
          'newsletter' => NewsletterPage(
            authService: newsletter.auth,
            profileService: newsletter.profile,
          ),
          'not-found' => const NotFound(),
          'scanner-overlay' => Scaffold(
            backgroundColor: const Color(0xFF454545),
            body: SafeArea(child: ScannerOverlay(onCancel: () {})),
          ),
          _ => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => statusDialog(
                    context,
                    title: name == 'status-success'
                        ? 'Request submitted'
                        : 'Unable to submit',
                    message: name == 'status-success'
                        ? 'Your request has been received. We will review it and follow up with you.'
                        : 'Please check your connection and try again. Your information has not been changed.',
                    isSuccess: name == 'status-success',
                  ),
                  child: const Text('Open status'),
                ),
              ),
            ),
          ),
        };
        final boundary = GlobalKey();
        final router = GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => page)],
        );
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(boldText: true, textScaler: TextScaler.noScaling),
              child: RepaintBoundary(key: boundary, child: child!),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (name.startsWith('status-')) {
          await tester.tap(find.text('Open status'));
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          for (final element in find.byType(Image).evaluate()) {
            await precacheImage((element.widget as Image).image, element);
          }
        });
        await tester.pumpAndSettle();
        final output = const String.fromEnvironment('RENDER_DIR');
        if (name == 'monthly-history') {
          final appBar = tester.widget<AppBar>(find.byType(AppBar));
          final size = tester.getSize(find.byWidget(appBar.flexibleSpace!));
          expect(size.width, 360);
          expect(size.height, greaterThanOrEqualTo(appBar.toolbarHeight!));
        }
        await applyRealFontFallback(tester);
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            await Directory(output).create(recursive: true);
            await File(
              '$output/$name-${theme.brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await tester.runAsync(() => newsletter.events.close());
        await GetIt.I.reset();
      });
    }
  }
}
