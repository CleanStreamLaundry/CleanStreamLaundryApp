import 'dart:async';

import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'storage initialization failure falls back to light without saving',
    () async {
      final storage = MockStorageService();
      final ready = Completer<void>();
      when(() => storage.init()).thenAnswer((_) => ready.future);
      final manager = ThemeManager(storage: storage);
      addTearDown(manager.dispose);

      ready.completeError(StateError('Storage unavailable'));
      await manager.initialized;

      expect(manager.themeData, same(lightMode));
      verifyNever(() => storage.getValue(any()));
      verifyNever(() => storage.setValue(any(), any()));
    },
  );

  test(
    'deferred preference read failure falls back to light without saving',
    () async {
      final storage = MockStorageService();
      final preference = Completer<String?>();
      when(() => storage.init()).thenAnswer((_) async {});
      when(
        () => storage.getValue('themeData'),
      ).thenAnswer((_) => preference.future);
      final manager = ThemeManager(storage: storage);
      addTearDown(manager.dispose);

      await untilCalled(() => storage.getValue('themeData'));
      preference.completeError(StateError('Preference unavailable'));
      await manager.initialized;

      expect(manager.themeData, same(lightMode));
      verifyNever(() => storage.setValue(any(), any()));
    },
  );

  test(
    'toggle notifies and persists both themes under the existing key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final manager = ThemeManager();
      addTearDown(manager.dispose);
      await manager.initialized;
      expect(manager.themeData, same(lightMode));
      var notifications = 0;
      manager.addListener(() => notifications++);

      manager.toggleTheme();
      expect(manager.themeData, same(darkMode));
      expect(notifications, 1);
      expect(await manager.storage.getValue('themeData'), 'darkMode');

      final restoredDark = ThemeManager();
      addTearDown(restoredDark.dispose);
      await restoredDark.initialized;
      expect(restoredDark.themeData, same(darkMode));

      manager.toggleTheme();
      expect(manager.themeData, same(lightMode));
      expect(notifications, 2);
      expect(await manager.storage.getValue('themeData'), 'lightMode');

      final restoredLight = ThemeManager();
      addTearDown(restoredLight.dispose);
      await restoredLight.initialized;
      expect(restoredLight.themeData, same(lightMode));
    },
  );
}
