import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch);
  final int major, minor, patch;
  static ReleaseVersion? parse(String value) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(value);
    return m == null
        ? null
        : ReleaseVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (final pair in [
      [major, other.major],
      [minor, other.minor],
      [patch, other.patch],
    ]) {
      final c = pair[0].compareTo(pair[1]);
      if (c != 0) return c;
    }
    return 0;
  }
}

class AvailableRelease {
  const AvailableRelease(this.version, this.page, this.preview);
  final String version;
  final Uri page;
  final bool preview;
}

class UpdateChecker {
  static AvailableRelease? select(
    dynamic data,
    String installed, {
    bool previews = true,
  }) {
    final current = ReleaseVersion.parse(installed);
    if (current == null || data is! List) {
      throw const FormatException('Invalid release response.');
    }
    AvailableRelease? best;
    var highest = current;
    for (final row in data.take(30)) {
      if (row is! Map ||
          row['draft'] != false ||
          (!previews && row['prerelease'] == true)) {
        continue;
      }
      final tag = row['tag_name'];
      if (tag is! String) continue;
      final version = ReleaseVersion.parse(tag);
      final page = Uri.tryParse(
        row['html_url'] is String ? row['html_url'] as String : '',
      );
      if (version == null ||
          version.compareTo(highest) <= 0 ||
          page == null ||
          page.scheme != 'https' ||
          page.host != 'github.com' ||
          (page.hasPort && page.port != 443) ||
          page.userInfo.isNotEmpty ||
          page.path != '/NotAl2/Linqo/releases/tag/$tag' ||
          page.hasQuery ||
          page.hasFragment) {
        continue;
      }
      final assets = row['assets'];
      if (assets is! List ||
          !assets.any(
            (a) =>
                a is Map &&
                a['state'] == 'uploaded' &&
                a['name'] == 'Linqo-$tag-android-arm64.apk',
          )) {
        continue;
      }
      highest = version;
      best = AvailableRelease(tag, page, row['prerelease'] == true);
    }
    return best;
  }

  Future<AvailableRelease?> check(
    String installed, {
    bool previews = true,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.https('api.github.com', '/repos/NotAl2/Linqo/releases', {
            'per_page': '30',
          }),
        );
        request.followRedirects = false;
        request.headers.set('User-Agent', 'Linqo/$installed');
        request.headers.set('Accept', 'application/vnd.github+json');
        final response = await request.close();
        if (response.statusCode != 200) {
          throw const HttpException(
            'GitHub could not check for updates. Try again later.',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const FormatException('Release response is too large.');
          }
          bytes.addAll(chunk);
        }
        return select(
          jsonDecode(utf8.decode(bytes)),
          installed,
          previews: previews,
        );
      })().timeout(const Duration(seconds: 12));
    } finally {
      client.close(force: true);
    }
  }
}
