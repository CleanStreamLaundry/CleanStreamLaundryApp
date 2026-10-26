import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:yaml/yaml.dart';

class _MockCallback extends Mock {
  void call(String value);
}

class _RegisteredValue {}

void main() {
  test('lazy singleton resolves once and reset awaits disposal', () async {
    final getIt = GetIt.asNewInstance();
    final callback = _MockCallback();
    var creations = 0;
    var disposed = false;
    getIt.registerLazySingleton<_RegisteredValue>(
      () {
        creations++;
        return _RegisteredValue();
      },
      dispose: (_) async {
        await Future<void>.value();
        disposed = true;
        callback('disposed');
      },
    );
    addTearDown(getIt.reset);
    expect(creations, 0);
    expect(
      identical(getIt<_RegisteredValue>(), getIt<_RegisteredValue>()),
      isTrue,
    );
    expect(creations, 1);
    await getIt.reset();
    expect(disposed, isTrue);
    expect(getIt.isRegistered<_RegisteredValue>(), isFalse);
    verify(() => callback('disposed')).called(1);
    verifyNoMoreInteractions(callback);
  });

  test('semver preserves alphanumeric identifiers and release ordering', () {
    expect(Version.parse('1.0.0-0x10').preRelease, ['0x10']);
    expect(Version.parse('1.0.0+0x10').build, ['0x10']);
    expect(Version.parse('1.0.0-rc.1') < Version.parse('1.0.0'), isTrue);
    expect(Version.parse('1.9.9') < Version.parse('2.0.0'), isTrue);
    expect(() => Version.parse('not-a-version'), throwsFormatException);
  });

  test('yaml handles terminal block strings and rejects recursive maps', () {
    expect(
      (loadYaml('value: |\n  synthetic') as YamlMap)['value'],
      'synthetic\n',
    );
    expect(() => loadYaml('&a {self: *a}'), throwsFormatException);
  });

  test(
    'existing in-memory preference fixture preserves value and removal',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = InMemorySharedPreferencesStore.empty();
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      expect(
        await store.setValue('String', 'flutter.synthetic', 'value'),
        isTrue,
      );
      expect(await store.getAll(), {'flutter.synthetic': 'value'});
      expect(await store.remove('flutter.synthetic'), isTrue);
      expect(await store.getAll(), isEmpty);
    },
  );
}
