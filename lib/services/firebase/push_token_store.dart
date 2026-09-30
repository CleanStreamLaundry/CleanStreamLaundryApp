import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'firebase_service.dart';

class SupabasePushTokenStore implements PushTokenStore {
  final PostgrestClient client;
  final SharedPreferences preferences;
  final String environment;
  final String platform;
  SupabasePushTokenStore({
    required this.client,
    required this.preferences,
    required this.environment,
    required this.platform,
  });

  String get _key => 'firebase.$environment.push.';

  Future<String> _identifier(String key) async {
    final existing = preferences.getString('$_key$key');
    if (existing != null) return existing;
    final value = const Uuid().v4();
    if (!await preferences.setString('$_key$key', value)) {
      throw StateError('Could not persist push installation');
    }
    return value;
  }

  @override
  Future<void> bind(PushAccount account, String token) async {
    if (preferences.getBool('${_key}retired') == true) await revoke();
    final installation = await _identifier('installation');
    final secret = await _identifier('secret');
    // Prepare also mutates: a lost response must remain cleanable after restart.
    if (!await preferences.setBool('${_key}pending', true)) {
      throw StateError('Could not persist push cleanup');
    }
    // A late prepare contains no token; registration can only update this slot.
    await client
        .rpc(
          'prepare_push_installation',
          params: {'p_installation': installation, 'p_secret': secret},
        )
        .setHeader('Authorization', account.bearer)
        .timeout(const Duration(seconds: 10));
    await client
        .rpc(
          'register_push_token',
          params: {
            'p_installation': installation,
            'p_secret': secret,
            'p_environment': environment,
            'p_platform': platform,
            'p_token': token,
          },
        )
        .setHeader('Authorization', account.bearer)
        .timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> revoke() async {
    final installation = preferences.getString('${_key}installation');
    final secret = preferences.getString('${_key}secret');
    final pending = preferences.getBool('${_key}pending') == true;
    final retired = preferences.getBool('${_key}retired') == true;
    if (!pending && !retired && installation == null && secret == null) return;
    if (!retired) {
      if (installation != null && secret != null) {
        // Also recover legacy capabilities whose prepare response was lost
        // before the old implementation recorded pending cleanup.
        await client
            .rpc(
              'revoke_push_installation',
              params: {'p_installation': installation, 'p_secret': secret},
            )
            .timeout(const Duration(seconds: 10));
      } else if (pending) {
        throw StateError('Missing push cleanup capability');
      }
      if (!await preferences.setBool('${_key}retired', true)) {
        throw StateError('Could not persist push revocation');
      }
    }
    // Durable terminal marker precedes partial removals, so restart can finish
    // rotation without losing the capability needed by an uncertain revoke.
    for (final key in ['installation', 'secret']) {
      if (!await preferences.remove('$_key$key')) {
        throw StateError('Could not rotate push installation');
      }
    }
    if (!await preferences.setBool('${_key}pending', false)) {
      throw StateError('Could not persist push revocation');
    }
    if (!await preferences.remove('${_key}retired')) {
      throw StateError('Could not complete push rotation');
    }
  }
}
