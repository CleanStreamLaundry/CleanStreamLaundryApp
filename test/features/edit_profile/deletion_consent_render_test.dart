@TestOn('vm')
library;

import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/edit_profile.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../fixtures/loyalty_action_context.dart';
import 'lifecycle_fixtures.dart';
import 'mocks.dart';

void main() {
  setUpAll(() async {
    final fonts = File.fromUri(
      Uri.file(
        Platform.resolvedExecutable,
      ).resolve('../../material_fonts/Roboto-Regular.ttf'),
    ).parent;
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              '${fonts.path}/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  for (final theme in [lightMode, darkMode]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('deletion consent ${theme.brightness.name} ${scale}x', (
        tester,
      ) async {
        await GetIt.I.reset();
        addTearDown(() => GetIt.I.reset());
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        addTearDown(tester.view.reset);
        final auth = MockAuthService();
        final profiles = MockProfileService();
        final session = callerSession();
        final authEvents = StreamController<AuthState>.broadcast();
        addTearDown(authEvents.close);
        when(() => auth.currentSession).thenReturn(session);
        when(() => auth.authStateChanges).thenAnswer((_) => authEvents.stream);
        when(() => auth.onAuthChange).thenAnswer((_) => const Stream.empty());
        when(() => auth.getCurrentUserId).thenReturn(callerId);
        when(
          () => auth.getCurrentUserEmail(),
        ).thenReturn('review@example.invalid');
        when(
          () => profiles.getUserNameById(callerId),
        ).thenAnswer((_) async => 'Review Account');
        when(
          () => profiles.getLoyaltyActionContext('account_deletion'),
        ).thenAnswer((_) async => actionContext(action: 'account_deletion'));
        GetIt.I.registerSingleton<AuthService>(auth);
        GetIt.I.registerSingleton<ProfileService>(profiles);
        GetIt.I.registerSingleton<EdgeFunctionService>(
          MockEdgeFunctionService(),
        );
        final boundary = GlobalKey();
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, __) => const EditProfilePage()),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
            ),
            routerConfig: router,
            builder: (context, child) => RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'Delete Account'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Account'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.widgetWithText(ElevatedButton, 'Request Deletion');
        expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
        expect(button.hitTestable(), findsOneWidget);
        expect(find.text('Purchased credit: \$20.50'), findsOneWidget);
        expect(find.textContaining('Existing eligible refunds'), findsNothing);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        const output = String.fromEnvironment('RENDER_DIR');
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
              '$output/deletion-${theme.brightness.name}-$scale.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.pumpAndSettle();
        expect(find.byType(Checkbox).hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
