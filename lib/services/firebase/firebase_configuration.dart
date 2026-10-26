import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseConfiguration {
  final String environment;
  final String platform;
  final FirebaseOptions options;
  const FirebaseConfiguration(this.environment, this.platform, this.options);

  static FirebaseConfiguration? fromBuild() => resolve(
    environment: const String.fromEnvironment('FIREBASE_ENV'),
    platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
    androidKey: const String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
    iosKey: const String.fromEnvironment('FIREBASE_IOS_API_KEY'),
  );

  static FirebaseConfiguration? resolve({
    required String environment,
    required String platform,
    required String androidKey,
    required String iosKey,
  }) {
    if (!const ['dev', 'prod'].contains(environment) ||
        !const ['android', 'iOS', 'ios'].contains(platform)) {
      return null;
    }
    final ios = platform != 'android';
    final key = ios ? iosKey : androidKey;
    if (!RegExp(r'^AIza[0-9A-Za-z_-]{35}$').hasMatch(key)) return null;
    final dev = environment == 'dev';
    return FirebaseConfiguration(
      environment,
      ios ? 'ios' : 'android',
      FirebaseOptions(
        apiKey: key,
        projectId: dev ? 'clean-stream-dev' : 'clean-stream-production',
        messagingSenderId: dev ? '83380736317' : '863183154828',
        appId: dev
            ? (ios
                  ? '1:83380736317:ios:3fe930785b224eb30af554'
                  : '1:83380736317:android:7b074a257825c9670af554')
            : (ios
                  ? '1:863183154828:ios:1f263e0ea3df94bde615a9'
                  : '1:863183154828:android:3c15f3dbc067244de615a9'),
        iosBundleId: ios
            ? 'com.cleanstreamlaundrysolutions.clenaStreamLaundryApp'
            : null,
      ),
    );
  }
}
