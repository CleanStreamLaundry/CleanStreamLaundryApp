import 'dart:async';
import 'package:clean_stream_laundry_app/core/di/di.dart';
import 'package:clean_stream_laundry_app/features/release_controls/release_gate.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:app_links/app_links.dart';
import 'package:clean_stream_laundry_app/features/loading/controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

Future<void> runThemedApp({
  required GoRouter router,
  required ThemeManager themeManager,
}) async {
  await themeManager.initialized;
  runApp(
    ChangeNotifierProvider(
      create: (_) => themeManager,
      child: RootApp(router: router),
    ),
  );
}

class RootApp extends StatefulWidget {
  final GoRouter router;
  final AppLinks? appLinks;

  const RootApp({super.key, required this.router, this.appLinks});

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  late final StreamSubscription<Uri> _linkSubscription;
  bool _logoRequested = false;
  bool _firstFrameDeferred = false;

  @override
  void initState() {
    super.initState();
    _linkSubscription = (widget.appLinks ?? AppLinks()).uriLinkStream.listen((
      uri,
    ) {
      if (mounted && LoadingPageController.deepLinkLocation(uri) != null) {
        widget.router.go(uri.toString(), extra: uri);
      }
    }, onError: (Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logoRequested) return;
    _logoRequested = true;
    // Keep the native splash until the shared startup logo can paint.
    _firstFrameDeferred = true;
    WidgetsBinding.instance.deferFirstFrame();
    unawaited(
      precacheImage(
        const AssetImage('assets/splash-logo.png'),
        context,
      ).whenComplete(_allowFirstFrame),
    );
  }

  void _allowFirstFrame() {
    if (!_firstFrameDeferred) return;
    _firstFrameDeferred = false;
    WidgetsBinding.instance.allowFirstFrame();
  }

  @override
  void dispose() {
    _allowFirstFrame();
    _linkSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeManager>().themeData;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Clean Stream Laundry Solutions',
      theme: theme,
      routerConfig: widget.router,
      builder: (context, child) => getIt.isRegistered<FirebaseService>()
          ? ReleaseGate(service: getIt<FirebaseService>(), child: child!)
          : child!,
    );
  }
}
