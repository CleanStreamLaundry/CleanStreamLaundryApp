import 'dart:async';

import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'package:clean_stream_laundry_app/root_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'core/theme/mocks.dart';

void main() {
  for (final preference in <String?, Brightness>{
    'darkMode': Brightness.dark,
    'lightMode': Brightness.light,
    null: Brightness.light,
    'invalid': Brightness.light,
  }.entries) {
    testWidgets('first app frame restores preference ${preference.key}', (
      tester,
    ) async {
      final storage = MockStorageService();
      final storageReady = Completer<void>();
      final savedTheme = Completer<String?>();
      when(() => storage.init()).thenAnswer((_) => storageReady.future);
      when(
        () => storage.getValue('themeData'),
      ).thenAnswer((_) => savedTheme.future);
      final renderedBrightnesses = <Brightness>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) {
              renderedBrightnesses.add(Theme.of(context).brightness);
              return const Scaffold(body: Text('Theme ready'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      final startup = runThemedApp(
        router: router,
        themeManager: ThemeManager(storage: storage),
      );
      await tester.pump();
      final framesBeforeStorage = renderedBrightnesses.toList();

      storageReady.complete();
      await tester.pump();
      final framesBeforePreference = renderedBrightnesses.toList();

      savedTheme.complete(preference.key);
      await startup;
      await tester.pumpAndSettle();

      expect(framesBeforeStorage, isEmpty);
      expect(framesBeforePreference, isEmpty);
      expect(find.text('Theme ready'), findsOneWidget);
      expect(renderedBrightnesses, isNotEmpty);
      expect(renderedBrightnesses, everyElement(preference.value));
    });
  }
}
