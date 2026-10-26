import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';
import 'package:clean_stream_laundry_app/logic/services/profile_service.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

class LoadingPageController extends ChangeNotifier {
  final AuthService authService;
  final AppLinks appLinks;
  final Uri? initialUri;
  final ProfileService? profileService;
  final bool forwardInitialLink;

  LoadingPageController({
    AuthService? authService,
    AppLinks? appLinks,
    this.initialUri,
    this.profileService,
    this.forwardInitialLink = false,
  }) : authService = authService ?? GetIt.instance<AuthService>(),
       appLinks = appLinks ?? AppLinks();

  String? error;
  Future<void>? _initialization;
  bool _disposed = false;
  StreamSubscription<bool>? _authSubscription;
  int _authGeneration = 0;
  bool _authStreamFailed = false;

  static String? deepLinkLocation(Uri uri) {
    if (uri.scheme == 'https' &&
        uri.host == 'cleanstreamlaundry.com' &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        uri.path == '/pay') {
      return Uri(
        path: '/pay',
        query: uri.hasQuery ? uri.query : null,
        fragment: uri.hasFragment ? uri.fragment : null,
      ).toString();
    }
    if (uri.scheme != 'clean-stream' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    if (!const {
      'oauth',
      'reset-protected',
      'email-verification',
      'change-email',
    }.contains(uri.host)) {
      return null;
    }
    if (uri.host == 'change-email') {
      try {
        final types = [
          ...?uri.queryParametersAll['type'],
          ...?Uri(query: uri.fragment).queryParametersAll['type'],
        ];
        if (types.any((type) => type != 'email_change')) return null;
      } on FormatException {
        return null;
      }
    }
    return Uri(
      path: '/auth-callback/${uri.host}',
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  Future<void> init({
    required void Function(String route, {Object? extra}) navigate,
    required ValueGetter<bool> isMounted,
  }) => _initialization ??= _init(navigate: navigate, isMounted: isMounted);

  Future<void> _init({
    required void Function(String route, {Object? extra}) navigate,
    required ValueGetter<bool> isMounted,
  }) async {
    await Future<void>.value();
    if (_disposed || !isMounted()) return;
    // A callback owns startup navigation; normal login must not race it.
    final handled = await _coldStartRedirect(
      navigate: navigate,
      isMounted: isMounted,
    );
    if (!handled && !_disposed && isMounted()) {
      await _automaticLogIn(navigate: navigate, isMounted: isMounted);
    }
  }

  Future<void> _automaticLogIn({
    required void Function(String route, {Object? extra}) navigate,
    required ValueGetter<bool> isMounted,
  }) async {
    try {
      final response = await authService.isLoggedIn();
      if (_disposed || !isMounted()) return;

      if (response == AuthenticationResponses.success) {
        navigate('/homePage');
      } else {
        navigate('/login');
      }
    } catch (e) {
      if (_disposed || !isMounted()) return;
      error = e.toString();
      notifyListeners();
    }
  }

  Future<bool> _coldStartRedirect({
    required void Function(String route, {Object? extra}) navigate,
    required ValueGetter<bool> isMounted,
  }) async {
    if (_disposed || !isMounted()) return true;
    Uri? uri;
    try {
      uri = initialUri ?? await appLinks.getInitialLink();
    } catch (_) {
      return false;
    }
    if (_disposed || !isMounted()) return true;
    final location = uri == null ? null : deepLinkLocation(uri);
    if (location == null) {
      if (initialUri?.hasScheme == true) {
        navigate('/login');
        return true;
      }
      return false;
    }
    if (forwardInitialLink) {
      navigate(uri.toString(), extra: uri);
      return true;
    }
    if (uri!.scheme == 'https') {
      navigate(location);
      return true;
    }
    final destination = Uri(
      path: uri.host == 'change-email' ? '/editProfile' : '/${uri.host}',
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
    String? provisioningUserId;
    int? provisioningGeneration;
    bool canComplete() {
      if (_disposed || !isMounted()) return false;
      if (_authStreamFailed ||
          (provisioningUserId != null &&
              (_authGeneration != provisioningGeneration ||
                  authService.getCurrentUser()?.id != provisioningUserId))) {
        error = 'Your sign-in changed. Please return to Login.';
        notifyListeners();
        return false;
      }
      return true;
    }

    try {
      if (uri.host == 'oauth') {
        // Observe before exchange so its initial replay is not a write change.
        _authSubscription = authService.onAuthChange.listen(
          (_) => _authGeneration++,
          onError: (Object _) => _authStreamFailed = true,
        );
      }
      // The app is the sole callback consumer (SDK detectSessionInUri is off).
      final payload = {
        ...uri.queryParameters,
        ...Uri.splitQueryString(uri.fragment),
      };
      final hasSessionPayload = const [
        'code',
        'access_token',
        'refresh_token',
        'error',
        'error_code',
        'error_description',
      ].any(payload.containsKey);
      if (uri.host == 'change-email' && !hasSessionPayload) {
        navigate('/login');
        return true;
      }
      if (uri.host == 'oauth' || hasSessionPayload) {
        await authService.getSessionFromURI(uri);
        if (_disposed || !isMounted()) return true;
      }
      if (uri.host == 'reset-protected' || uri.host == 'email-verification') {
        navigate(
          destination,
          extra: uri.host == 'reset-protected' ? uri : null,
        );
        return true;
      }
      final response = await authService.isLoggedIn();
      if (_disposed || !isMounted()) return true;
      if (response == AuthenticationResponses.success &&
          uri.host == 'change-email') {
        await authService.refreshSession();
        if (_disposed || !isMounted()) return true;
      }
      if (response == AuthenticationResponses.success && uri.host == 'oauth') {
        if (!canComplete()) return true;
        final user = authService.getCurrentUser();
        if (user == null) {
          navigate('/login');
          return true;
        }
        provisioningUserId = user.id;
        provisioningGeneration = _authGeneration;
        var name = '';
        for (final candidate in [
          user.userMetadata?['full_name'],
          user.userMetadata?['name'],
          user.userMetadata?['given_name'],
        ]) {
          if (candidate is String && candidate.trim().isNotEmpty) {
            name = candidate;
            break;
          }
        }
        try {
          await (profileService ?? GetIt.instance<ProfileService>())
              .createAccount(id: user.id, name: name);
        } finally {
          // Auth events may be queued behind the provisioning completion.
          await Future<void>.delayed(Duration.zero);
        }
        if (!canComplete()) return true;
      }
      navigate(
        response == AuthenticationResponses.success
            ? (uri.host == 'oauth' ? '/homePage' : destination)
            : '/login',
      );
    } catch (_) {
      if (canComplete()) navigate('/login');
    } finally {
      _cancelAuthObservation();
    }
    return true;
  }

  void disposeController() {
    _disposed = true;
    _cancelAuthObservation();
  }

  void _cancelAuthObservation() {
    _authSubscription?.cancel().ignore();
    _authSubscription = null;
  }

  @override
  void dispose() {
    disposeController();
    super.dispose();
  }
}
