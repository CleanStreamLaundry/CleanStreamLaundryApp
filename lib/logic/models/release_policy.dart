import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';

enum ReleaseDecision { allowed, recommended, blocked, maintenance }

/// Presentation policy only. Backend authorization never trusts this policy.
class ReleasePolicy {
  final Version minimum;
  final Version recommended;
  final Set<int> blockedBuilds;
  final bool maintenance;
  final Uri? updateUrl;

  ReleasePolicy({
    required this.minimum,
    required this.recommended,
    this.blockedBuilds = const {},
    this.maintenance = false,
    this.updateUrl,
  });

  factory ReleasePolicy.safe() =>
      ReleasePolicy(minimum: Version(0, 0, 0), recommended: Version(0, 0, 0));

  factory ReleasePolicy.parse(String value, String platform) {
    final json = jsonDecode(value);
    if (json is! Map<String, dynamic> || json['schema'] != 1) {
      throw const FormatException('Unsupported release policy');
    }
    final data = json[platform];
    if (data is! Map<String, dynamic> ||
        data['maintenance'] is! bool ||
        data['blocked_builds'] is! List) {
      throw const FormatException('Incomplete release policy');
    }
    final minimum = Version.parse(data['minimum'] as String);
    final recommended = Version.parse(data['recommended'] as String);
    if (recommended < minimum) {
      throw const FormatException('Recommended version precedes minimum');
    }
    final builds = <int>{};
    for (final build in data['blocked_builds'] as List) {
      if (build is! int || build < 1) {
        throw const FormatException('Invalid blocked build');
      }
      builds.add(build);
    }
    final url = data['update_url'];
    if (url is! String) throw const FormatException('Missing update URL');
    final uri = url.isEmpty ? null : Uri.tryParse(url);
    if (uri != null &&
        (uri.scheme != 'https' ||
            uri.userInfo.isNotEmpty ||
            uri.hasPort ||
            uri.hasFragment ||
            !(platform == 'ios'
                ? uri.host == 'apps.apple.com' &&
                      RegExp(r'/id[0-9]+$').hasMatch(uri.path)
                : uri.host == 'play.google.com' &&
                      uri.path == '/store/apps/details' &&
                      uri.queryParameters['id'] ==
                          'com.cleanstreamlaundrysolutions.clean_stream_laundry_app'))) {
      throw const FormatException('Unapproved update URL');
    }
    if (url.isNotEmpty && uri == null) {
      throw const FormatException('Invalid update URL');
    }
    return ReleasePolicy(
      minimum: minimum,
      recommended: recommended,
      blockedBuilds: builds,
      maintenance: data['maintenance'] as bool,
      updateUrl: uri,
    );
  }

  ReleaseDecision evaluate(String version, String build) {
    if (maintenance) return ReleaseDecision.maintenance;
    if (blockedBuilds.contains(int.tryParse(build))) {
      return ReleaseDecision.blocked;
    }
    final current = Version.parse(version);
    if (current < minimum) {
      return ReleaseDecision.blocked;
    }
    return current < recommended
        ? ReleaseDecision.recommended
        : ReleaseDecision.allowed;
  }
}
