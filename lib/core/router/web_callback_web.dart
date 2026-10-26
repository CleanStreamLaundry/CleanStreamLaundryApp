import 'dart:ui_web' show BrowserPlatformLocation;

// Only the actual document can supply a web callback, never an incoming link.
Uri? takeWebAuthCallback() {
  final document = Uri.base;
  if (!const {'http', 'https'}.contains(document.scheme) ||
      document.host.isEmpty ||
      document.userInfo.isNotEmpty) {
    return null;
  }
  final route = document.fragment.startsWith('/')
      ? Uri.tryParse(document.fragment)
      : null;
  if (document.fragment.startsWith('/') &&
      (route == null ||
          route.hasAuthority ||
          route.hasScheme ||
          !const {'/', '/loading'}.contains(route.path))) {
    return null;
  }
  final fragment = route?.fragment ?? document.fragment;
  final query = [
    document.query,
    if (route != null) route.query,
  ].where((part) => part.isNotEmpty).join('&');
  const sessionKeys = {
    'code',
    'access_token',
    'refresh_token',
    'error',
    'error_code',
    'error_description',
  };
  const authKeys = {
    ...sessionKeys,
    'expires_in',
    'expires_at',
    'token_type',
    'provider_token',
    'provider_refresh_token',
    'type',
  };
  bool hasKey(String pair, Set<String> keys) {
    try {
      return keys.contains(Uri.decodeQueryComponent(pair.split('=').first));
    } on FormatException {
      return false;
    }
  }

  // Keep unrelated encoded pairs byte-for-byte, including duplicate values.
  // Malformed auth values still reach Loading's fail-closed parser.
  String withoutAuth(String value) =>
      value.split('&').where((pair) => !hasKey(pair, authKeys)).join('&');
  if (route == null &&
      fragment.isNotEmpty &&
      !fragment.split('&').any((pair) => hasKey(pair, authKeys))) {
    return null;
  }
  if (![
    query,
    fragment,
  ].any((value) => value.split('&').any((pair) => hasKey(pair, sessionKeys)))) {
    return null;
  }
  final callback = Uri(
    scheme: 'clean-stream',
    host: 'oauth',
    query: query.isEmpty ? null : query,
    fragment: fragment.isEmpty ? null : fragment,
  );
  final cleanQuery = withoutAuth(document.query);
  final cleanRouteQuery = withoutAuth(route?.query ?? '');
  final cleanFragment = withoutAuth(fragment);
  final cleanHash = route == null
      ? cleanFragment
      : Uri(
          path: route.path,
          query: cleanRouteQuery.isEmpty ? null : cleanRouteQuery,
          fragment: cleanFragment.isEmpty ? null : cleanFragment,
        ).toString();
  final cleanDocument = Uri(
    scheme: document.scheme,
    host: document.host,
    port: document.hasPort ? document.port : null,
    path: document.path,
    query: cleanQuery.isEmpty ? null : cleanQuery,
    fragment: cleanHash.isEmpty ? null : cleanHash,
  );
  // gotrue parses but never cleans the URL. Remove single-use material before
  // any await, including failed exchanges and disposal; keep history state.
  const browser = BrowserPlatformLocation();
  browser.replaceState(browser.state, '', cleanDocument.toString());
  return callback;
}
