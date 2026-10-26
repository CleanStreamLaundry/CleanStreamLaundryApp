import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const filename = 'library-update-synthetic-config';
  late DotEnv config;
  String? contents;

  setUp(() {
    config = DotEnv();
    contents = null;
    rootBundle.evict(filename);
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      expect(
        utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        ),
        filename,
      );
      final value = contents;
      return value == null ? null : ByteData.sublistView(utf8.encode(value));
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    rootBundle.evict(filename);
    config.clean();
  });

  test('mandatory asset load exposes synthetic values through env', () async {
    contents = 'SYNTHETIC_VALUE=present';
    await config.load(fileName: filename);
    expect(config.env, {'SYNTHETIC_VALUE': 'present'});
  });

  test(
    'missing mandatory asset fails and does not expose stale config',
    () async {
      config.loadFromString(envString: 'SYNTHETIC_VALUE=stale');
      await expectLater(
        config.load(fileName: filename),
        throwsA(isA<FileNotFoundError>()),
      );
      expect(config.isInitialized, isFalse);
      expect(() => config.env, throwsA(isA<NotInitializedError>()));
    },
  );

  test('empty mandatory asset fails', () async {
    contents = '';
    await expectLater(
      config.load(fileName: filename),
      throwsA(isA<EmptyEnvFileError>()),
    );
    expect(config.isInitialized, isFalse);
  });

  test('renamed string loader and clean initialization contract', () {
    config.loadFromString(envString: 'SYNTHETIC_VALUE=present');
    expect(config.env['SYNTHETIC_VALUE'], 'present');
    config.clean();
    expect(() => config.env, throwsA(isA<NotInitializedError>()));
  });
}
