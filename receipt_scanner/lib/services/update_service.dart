import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// A newer build published as a GitHub release.
class UpdateInfo {
  UpdateInfo({required this.version, required this.downloadUrl});

  final String version;
  final String downloadUrl;
}

/// Checks GitHub releases for a phone build newer than the one running.
///
/// The desktop scanner publishes its own releases to the same repo tagged
/// `vN`, so this can't just ask for ".../releases/latest" — that would
/// return whichever app released most recently. Instead it lists releases
/// and picks the newest one tagged `android-vN`, set by
/// .github/workflows/release-mobile.yml, which also builds the APK with
/// --build-number=N to match.
class UpdateService {
  static const _releasesUrl =
      'https://api.github.com/repos/amituti31-dev/homestock/releases';
  static final _tagPattern = RegExp(r'^android-v(\d+)$');

  /// Returns null when up to date or when the check fails — an update check
  /// should never block the app.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(_releasesUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final releases = jsonDecode(response.body) as List;
      Map<String, dynamic>? latest;
      int latestBuild = 0;
      for (final r in releases.cast<Map<String, dynamic>>()) {
        final match = _tagPattern.firstMatch(r['tag_name'] as String? ?? '');
        if (match == null) continue;
        final build = int.parse(match.group(1)!);
        if (build > latestBuild) {
          latestBuild = build;
          latest = r;
        }
      }
      if (latest == null) return null;

      final info = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(info.buildNumber) ?? 0;
      if (latestBuild <= localBuild) return null;

      final assets = (latest['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final apkAsset = assets.cast<Map<String, dynamic>?>().firstWhere(
            (a) => (a?['name'] as String?)?.endsWith('.apk') ?? false,
            orElse: () => null,
          );

      final downloadUrl = apkAsset?['browser_download_url'] as String? ??
          latest['html_url'] as String? ??
          '';
      if (downloadUrl.isEmpty) return null;

      return UpdateInfo(version: latest['tag_name'] as String, downloadUrl: downloadUrl);
    } catch (_) {
      return null;
    }
  }
}
