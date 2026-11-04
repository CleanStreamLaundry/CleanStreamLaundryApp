import 'dart:convert';
import 'dart:io';

import 'package:clean_stream_laundry_app/logic/models/release_policy.dart';
import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service_test.dart' show Driver, Tokens, policyJson;

class ReleasePreferences extends Mock implements SharedPreferences {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in ['android', 'ios']) {
    test('$platform checked-in defaults match the production parser', () {
      final raw = File('config/firebase/release-policy.example.json')
          .readAsStringSync();
      final policy = ReleasePolicy.parse(raw, platform);
      expect(policy.evaluate('0.0.0', '1'), ReleaseDecision.allowed);
      expect(policy.evaluate('99.0.0', '42'), ReleaseDecision.allowed);
      expect(policy.updateUrl, isNull);
    });

    test('$platform configuration fields retain their release semantics', () {
      final data = jsonDecode(
        File('config/firebase/release-policy.example.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final target = data[platform] as Map<String, dynamic>;
      target.addAll({
        'minimum': '1.2.0',
        'recommended': '1.10.0',
        'blocked_builds': [42],
        'update_url': platform == 'ios'
            ? 'https://apps.apple.com/app/id123456789'
            : 'https://play.google.com/store/apps/details?id=com.cleanstreamlaundrysolutions.clean_stream_laundry_app',
      });
      final policy = ReleasePolicy.parse(jsonEncode(data), platform);
      expect(policy.evaluate('1.1.0', '1'), ReleaseDecision.blocked);
      expect(policy.evaluate('1.2.0', '1'), ReleaseDecision.recommended);
      expect(policy.evaluate('1.10.0', '1'), ReleaseDecision.allowed);
      expect(policy.evaluate('1.10.0', '42'), ReleaseDecision.blocked);
      expect(policy.updateUrl, isNotNull);
      target['maintenance'] = true;
      expect(
        ReleasePolicy.parse(jsonEncode(data), platform).evaluate('1.10.0', '1'),
        ReleaseDecision.maintenance,
      );
    });
  }

  final policies = {
    ReleaseDecision.allowed: policyJson(recommended: '1.0.0'),
    ReleaseDecision.recommended: policyJson(),
    ReleaseDecision.blocked: policyJson(blocked: [10]),
    ReleaseDecision.maintenance: policyJson(maintenance: true),
  };
  for (final current in [
    ReleaseDecision.allowed,
    ReleaseDecision.blocked,
    ReleaseDecision.maintenance,
  ]) {
    for (final fetched in policies.keys) {
      for (final write in ['false', 'throw', 'success']) {
        test('$current -> $fetched with cache write $write', () async {
          final prefs = ReleasePreferences();
          final driver = Driver()..raw = policies[fetched]!;
          final diagnostics = <String>[];
          when(
            () => prefs.setString('firebase.dev.android.release.v1', driver.raw),
          ).thenAnswer((_) async {
            if (write == 'throw') throw StateError('Disk unavailable');
            return write == 'success';
          });
          final service = FirebaseService(
            driver: driver,
            tokens: Tokens(),
            preferences: prefs,
            environment: 'dev',
            platform: 'android',
            version: '1.0.0',
            build: '10',
            navigate: (_) async {},
            showNotification: (_) async {},
            diagnostic: diagnostics.add,
          );
          addTearDown(service.dispose);
          service.available = true;
          final previous = ReleasePolicy.parse(policies[current]!, 'android');
          service.policy = previous;
          var notifications = 0;
          service.addListener(() => notifications++);
          await service.refreshReleasePolicy();
          final applied =
              write == 'success' ||
              fetched == ReleaseDecision.blocked ||
              fetched == ReleaseDecision.maintenance;
          expect(service.decision, applied ? fetched : current);
          expect(identical(service.policy, previous), !applied);
          expect(notifications, applied ? 1 : 0);
          expect(diagnostics, write == 'success' ? isEmpty : hasLength(1));
          verify(
            () => prefs.setString('firebase.dev.android.release.v1', driver.raw),
          ).called(1);
        });
      }
    }
  }
}
