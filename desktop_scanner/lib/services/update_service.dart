import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// A newer build published as a GitHub release.
class UpdateInfo {
  UpdateInfo({required this.version, required this.downloadUrl, required this.releaseUrl});

  final String version;
  final String downloadUrl;
  final String releaseUrl;
}

/// Checks GitHub releases for a build newer than the one currently running.
///
/// The release tag is just the CI run number (`v1`, `v2`, ...), set by
/// .github/workflows/release-desktop.yml, and the exe is built with the same
/// number as its --build-number. So "is there an update" is just "is the
/// latest release's number bigger than mine" — no semver needed.
class UpdateService {
  static const _releasesUrl =
      'https://api.github.com/repos/amituti31-dev/homestock/releases/latest';
  static const _userAgent = 'HomeStock-DesktopScanner/1.0';

  /// Returns null when up to date or when the check fails — an update check
  /// should never block scanning.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(_releasesUrl),
        headers: {'User-Agent': _userAgent, 'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String? ?? '';
      final remoteBuild = int.tryParse(tag.replaceFirst('v', ''));
      if (remoteBuild == null) return null;

      final info = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(info.buildNumber) ?? 0;
      if (remoteBuild <= localBuild) return null;

      final assets = (data['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final setupAsset = assets.cast<Map<String, dynamic>?>().firstWhere(
            (a) => (a?['name'] as String?)?.endsWith('.exe') ?? false,
            orElse: () => null,
          );

      return UpdateInfo(
        version: tag,
        downloadUrl: setupAsset?['browser_download_url'] as String? ??
            data['html_url'] as String? ??
            '',
        releaseUrl: data['html_url'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
