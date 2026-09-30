import 'package:flutter/material.dart';
import 'dart:async';
import 'services/firebase/firebase_service.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'root_app.dart';
import 'core/di/di.dart';
import 'core/theme/theme_manager.dart';

late final GoRouter pageRouter;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  await setupDependencies();
  if (getIt.isRegistered<FirebaseService>()) {
    unawaited(getIt<FirebaseService>().start());
  }

  final router = getIt<GoRouter>();
  await runThemedApp(
    router: router,
    themeManager: ThemeManager(),
  );
}
