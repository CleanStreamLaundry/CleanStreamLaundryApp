@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/features/change_email_verification/change_email_verification.dart';
import 'package:clean_stream_laundry_app/features/edit_profile/edit_profile.dart';
import 'package:clean_stream_laundry_app/features/email_verification/email_verification.dart';
import 'package:clean_stream_laundry_app/features/maintenance_request/maintenance_request.dart';
import 'package:clean_stream_laundry_app/features/password_reset/password_reset.dart';
import 'package:clean_stream_laundry_app/features/refund_request/refund_request.dart';
import 'package:clean_stream_laundry_app/features/reset_protected/reset_protected.dart';
import 'package:clean_stream_laundry_app/features/sign_up/sign_up.dart';
import 'package:clean_stream_laundry_app/features/topup_refunds/topup_refunds.dart';
import 'package:clean_stream_laundry_app/features/verify_code/verify_code.dart';
import 'package:clean_stream_laundry_app/logic/models/topup_refund.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/edge_function_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:clean_stream_laundry_app/logic/services/transaction_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/edit_profile/lifecycle_fixtures.dart' as profile;
import '../features/maintenance_request/maintenance_request_test.dart'
    show MockMaintenanceController;
import '../features/refund_request/mocks.dart' as mocks;
import '../features/topup_refunds/fixtures.dart' as refunds;
import 'real_font_fallback.dart';

const output = String.fromEnvironment('RENDER_DIR');
const renderWidth = int.fromEnvironment('RENDER_WIDTH', defaultValue: 360);
const renderHeight = int.fromEnvironment('RENDER_HEIGHT', defaultValue: 780);
const bottomInset = int.fromEnvironment(
  'RENDER_BOTTOM_INSET',
  defaultValue: 24,
);
const keyboardInset = int.fromEnvironment('RENDER_KEYBOARD_INSET');
final textScale = double.parse(
  const String.fromEnvironment('RENDER_TEXT_SCALE', defaultValue: '1'),
);
final manifest = <Map<String, Object?>>[];

Future<void> loadFonts() async {
  final config = File('.dart_tool/package_config.json');
  final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
  final flutter = Directory.fromUri(
    config.absolute.uri.resolve(
      packages.singleWhere((entry) => entry['name'] == 'flutter')['rootUri']
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
}

void main() {
  setUpAll(loadFonts);
  tearDownAll(() async {
    if (output.isEmpty) return;
    await Directory(output).create(recursive: true);
    final existing = File('$output/forms-manifest.json');
    final captures = <String, Object?>{};
    if (existing.existsSync()) {
      for (final entry
          in jsonDecode(existing.readAsStringSync())['captures'] as List) {
        captures[entry['file'] as String] = entry;
      }
    }
    for (final entry in manifest) {
      captures[entry['file'] as String] = entry;
    }
    await File('$output/forms-manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'viewport': {
          'width': renderWidth,
          'height': renderHeight,
          'scale': textScale,
          'boldText': true,
          'topInset': 28,
          'bottomInset': bottomInset,
          'keyboardInset': keyboardInset,
          'pixelRatio': 1,
        },
        'fonts':
            'Flutter SDK Roboto Regular/Medium/Bold and MaterialIcons via package_config',
        'captures': captures.values.toList(),
      }),
    );
  });

  for (final theme in [lightMode, darkMode]) {
    for (final scene in [
      'topup-refunds',
      'topup-confirmation',
      'topup-requests',
      'edit-profile',
      'profile-save-dialog',
      'profile-delete-dialog',
      'machine-refund-request',
      'maintenance-request',
      'signup',
      'password-reset',
      'reset-protected',
      'verify-code',
      'email-verification',
      'change-email-verification',
    ]) {
      testWidgets('${theme.brightness.name} $scene', (tester) async {
        await GetIt.I.reset();
        final errors = <String>[];
        final originalError = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details.toString());
        };
        addTearDown(() {
          FlutterError.onError = originalError;
        });
        tester.view.physicalSize = Size(
          renderWidth.toDouble(),
          renderHeight.toDouble(),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(
          top: 28,
          bottom: keyboardInset > 0 ? 0 : bottomInset.toDouble(),
        );
        tester.view.viewPadding = FakeViewPadding(
          top: 28,
          bottom: bottomInset.toDouble(),
        );
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboardInset.toDouble(),
        );
        addTearDown(tester.view.reset);
        final auth = mocks.MockAuthService();
        final userProfile = mocks.MockProfileService();
        final edge = mocks.MockEdgeFunctionService();
        final transactions = mocks.MockTransactionService();
        final session = profile.callerSession();
        final authEvents = StreamController<AuthState>.broadcast(sync: true);
        when(() => auth.currentSession).thenReturn(session);
        when(() => auth.getCurrentUserId).thenReturn(profile.callerId);
        when(() => auth.getCurrentUserEmail()).thenReturn('alex@example.com');
        when(() => auth.authStateChanges).thenAnswer((_) => authEvents.stream);
        when(() => auth.onAuthChange).thenAnswer((_) => const Stream.empty());
        when(
          () => userProfile.getUserNameById(any()),
        ).thenAnswer((_) async => 'Alex Morgan');
        when(
          () => userProfile.getAdmissionStatus(),
        ).thenAnswer((_) async => profile.lifecycleStatus(pending: false));
        when(() => transactions.getRefundableTransactionsForUser()).thenAnswer(
          (_) async =>
              (transactions: ['Washer #5 - \$4.00 - Sep 29, 2026'], ids: [105]),
        );
        refunds.RefundHarness? refundFixture;
        TextEditingController? description;
        if (scene.startsWith('topup-')) {
          refundFixture = refunds.RefundHarness()..register();
          if (scene == 'topup-requests') {
            refundFixture.topups = [];
            refundFixture.refunds = [
              TopupRefund.fromJson(refunds.refundJson()),
            ];
          }
        } else {
          GetIt.I.registerSingleton<AuthService>(auth);
          GetIt.I.registerSingleton<ProfileService>(userProfile);
          GetIt.I.registerSingleton<EdgeFunctionService>(edge);
          GetIt.I.registerSingleton<TransactionService>(transactions);
        }

        late Widget page;
        switch (scene) {
          case 'topup-refunds':
          case 'topup-confirmation':
          case 'topup-requests':
            page = const TopupRefundsPage();
          case 'edit-profile':
          case 'profile-save-dialog':
          case 'profile-delete-dialog':
            page = const EditProfilePage();
          case 'machine-refund-request':
            page = const RefundPage();
          case 'maintenance-request':
            final controller = MockMaintenanceController();
            description = TextEditingController();
            when(() => controller.attemptedSubmit).thenReturn(false);
            when(() => controller.categories).thenReturn([
              'Washer/Dryer Maintenance',
              'App Maintenance',
              'Other',
            ]);
            when(() => controller.selectedCategory).thenReturn(null);
            when(() => controller.isLoading).thenReturn(false);
            when(() => controller.generation).thenReturn(0);
            when(() => controller.draftKey).thenReturn('visual-fixture');
            when(() => controller.isCurrent(any())).thenReturn(true);
            when(() => controller.isFormValid).thenReturn(false);
            when(() => controller.selectedImage).thenReturn(null);
            when(
              () => controller.descriptionController,
            ).thenReturn(description);
            when(
              () => controller.locations,
            ).thenReturn([(id: '1', address: '100 Main Street')]);
            when(() => controller.selectedLocation).thenReturn(null);
            when(() => controller.init()).thenAnswer((_) async {});
            page = MaintenancePage(controller: controller);
          case 'signup':
            page = const SignUpPage();
          case 'password-reset':
            page = const PasswordResetPage();
          case 'reset-protected':
            page = const ResetProtectedPage();
          case 'verify-code':
            page = const CodeVerificationPage(email: 'alex@example.com');
          case 'email-verification':
            page = const EmailVerificationPage(email: 'alex@example.com');
          case 'change-email-verification':
            page = const ChangeEmailVerificationPage();
          default:
            throw StateError(scene);
        }
        final boundary = GlobalKey();
        final router = GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => page)],
        );
        try {
          await tester.pumpWidget(
            MaterialApp.router(
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
              ),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  boldText: true,
                ),
                child: RepaintBoundary(key: boundary, child: child!),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final appBar in tester.widgetList<AppBar>(find.byType(AppBar))) {
            if (appBar.flexibleSpace == null) continue;
            final size = tester.getSize(find.byWidget(appBar.flexibleSpace!));
            expect(size.width, renderWidth.toDouble());
            expect(
              size.height,
              greaterThanOrEqualTo(appBar.toolbarHeight ?? kToolbarHeight),
            );
          }
          if (scene == 'topup-confirmation') {
            await reveal(tester, find.text('Request full refund'));
            await tester.tap(find.text('Request full refund'));
          } else if (scene == 'profile-save-dialog') {
            await tester.enterText(
              find.widgetWithText(TextFormField, 'New Full Name'),
              'Alex Taylor',
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await reveal(tester, find.text('Save Changes'));
            await tester.tap(find.text('Save Changes'));
          } else if (scene == 'profile-delete-dialog') {
            await reveal(tester, find.text('Delete Account'));
            await tester.tap(find.text('Delete Account'));
          }
          await tester.pumpAndSettle();
          if (scene == 'topup-confirmation' || scene.endsWith('-dialog')) {
            expect(find.byType(AlertDialog), findsOneWidget);
          }
          for (final element in find.byType(Image).evaluate()) {
            final widget = element.widget as Image;
            await tester.runAsync(() => precacheImage(widget.image, element));
          }
          await tester.pumpAndSettle();
          await capture(
            tester,
            boundary,
            '${theme.brightness.name}-$scene',
            scene,
            errors,
          );
          if (scene == 'topup-confirmation' ||
              scene == 'profile-delete-dialog') {
            final scroll = find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Scrollable),
                )
                .first;
            final state = tester.state<ScrollableState>(scroll);
            state.position.jumpTo(state.position.maxScrollExtent);
            await tester.pumpAndSettle();
            await capture(
              tester,
              boundary,
              '${theme.brightness.name}-$scene-bottom',
              '$scene (bottom scroll)',
              errors,
            );
            if (!output.endsWith('/before')) {
              final finalText = find.textContaining(
                scene == 'topup-confirmation'
                    ? 'A request is not a paid refund'
                    : 'I understand that my account',
              );
              final paragraph = tester.renderObject<RenderParagraph>(finalText);
              final length = paragraph.text.toPlainText().length;
              final box = paragraph
                  .getBoxesForSelection(
                    TextSelection(baseOffset: length - 1, extentOffset: length),
                  )
                  .last;
              final bottom = paragraph
                  .localToGlobal(Offset(box.left, box.bottom))
                  .dy;
              final viewport = tester.getRect(scroll);
              expect(bottom, lessThanOrEqualTo(viewport.bottom + .5));
              expect(bottom, greaterThan(viewport.top));
              expect(find.text('Cancel').hitTestable(), findsOneWidget);
              expect(
                find
                    .text(
                      scene == 'topup-confirmation'
                          ? 'Confirm request'
                          : 'Request Deletion',
                    )
                    .hitTestable(),
                findsOneWidget,
              );
            }
          }
          if ([
            'edit-profile',
            'machine-refund-request',
            'maintenance-request',
            'signup',
            'password-reset',
            'reset-protected',
            'topup-refunds',
          ].contains(scene)) {
            final scroll = find.byType(Scrollable).first;
            final state = tester.state<ScrollableState>(scroll);
            state.position.jumpTo(state.position.maxScrollExtent);
            await tester.pumpAndSettle();
            await capture(
              tester,
              boundary,
              '${theme.brightness.name}-$scene-bottom',
              '$scene (bottom scroll)',
              errors,
            );
          }
          if (scene == 'machine-refund-request' ||
              scene == 'maintenance-request') {
            final action = find.widgetWithText(
              ElevatedButton,
              scene == 'machine-refund-request'
                  ? 'Submit Refund Request'
                  : 'Submit Maintenance Request',
            );
            expect(action.hitTestable(), findsOneWidget);
            final bottom = tester.getRect(action).bottom;
            final safeBottom =
                renderHeight -
                (keyboardInset > 0 ? keyboardInset : bottomInset);
            expect(bottom, lessThanOrEqualTo(safeBottom - 19));
            expect(bottom, greaterThanOrEqualTo(safeBottom - 21));
          }
          if (['signup', 'password-reset', 'reset-protected'].contains(scene)) {
            final label = switch (scene) {
              'signup' => 'Create Account',
              'password-reset' => 'Send Reset Code',
              _ => 'Reset Password',
            };
            expect(
              find.widgetWithText(ElevatedButton, label).hitTestable(),
              findsOneWidget,
            );
          }
          if (refundFixture != null) expect(refundFixture.writes, 0);
          expect(
            output.endsWith('/before')
                ? errors.where((error) => !error.contains('overflowed'))
                : errors,
            isEmpty,
            reason:
                'Non-layout errors are harness failures; all errors are retained in manifest.',
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          router.dispose();
          description?.dispose();
          if (refundFixture != null) await refundFixture.dispose();
          await GetIt.I.reset();
          await authEvents.close();
          FlutterError.onError = originalError;
        }
      });
    }
  }
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
  String scene,
  List<String> errors,
) async {
  await applyRealFontFallback(tester);
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
  manifest.add({
    'file': '$name.png',
    'scene': scene,
    'scope': 'Actual page or dialog, fixture-only services',
    'frameworkErrors': List<String>.of(errors),
  });
}
