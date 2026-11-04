import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Store builds select complete public settings without reading the local asset.
/// Populate the existing dotenv instance so all current consumers stay aligned.
Future<void> initializeClientConfiguration({
  DotEnv? target,
  String channel = const String.fromEnvironment('CLIENT_CHANNEL'),
  String supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
  String publicKey = const String.fromEnvironment('ANON_KEY'),
  String stripeKey = const String.fromEnvironment('STRIPE_PUBLISHABLE_KEY'),
}) async {
  final environment = target ?? dotenv;
  if (channel.isEmpty &&
      supabaseUrl.isEmpty &&
      publicKey.isEmpty &&
      stripeKey.isEmpty) {
    await environment.load(fileName: '.env');
    return;
  }

  environment.clean();
  final test = channel == 'testflight' || channel == 'play-internal';
  final live = channel == 'production-ios' || channel == 'production-android';
  if (!test && !live) {
    throw StateError('An explicit valid client channel is required.');
  }
  final uri = Uri.tryParse(supabaseUrl);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (test && supabaseUrl != 'https://dnuuhupoxjtwqzaqylvb.supabase.co')) {
    throw StateError('Client backend does not match the selected channel.');
  }
  final mode = test ? 'test' : 'live';
  if (!RegExp('^pk_${mode}_[A-Za-z0-9_]+\$').hasMatch(stripeKey) ||
      RegExp('replace|placeholder', caseSensitive: false).hasMatch(stripeKey)) {
    throw StateError('Client Stripe key does not match the selected channel.');
  }
  var legacyAnon = false;
  try {
    final parts = publicKey.split('.');
    if (parts.length == 3 && RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(publicKey)) {
      legacyAnon =
          (jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>)['role'] ==
          'anon';
    }
  } catch (_) {
    // Malformed and privileged keys fail below, without logging their contents.
  }
  if (!RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(publicKey) &&
      !legacyAnon) {
    throw StateError('Client Supabase key must be public.');
  }
  environment.loadFromString(
    isOptional: true,
    mergeWith: {
      'SUPABASE_URL': supabaseUrl,
      'ANON_KEY': publicKey,
      'STRIPE_PUBLISHABLE_KEY': stripeKey,
    },
  );
}
