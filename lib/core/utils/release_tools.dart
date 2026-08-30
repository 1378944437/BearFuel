import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/config/app_config.dart';

/// 可注入的更新请求响应，用于生产请求与确定性测试。
class UpdateHttpResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const UpdateHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });
}

/// 更新请求传输函数。实现不应在 headers 中加入个人 GitHub Token。
typedef UpdateTransport =
    Future<UpdateHttpResponse> Function(Uri uri, Map<String, String> headers);

/// 比较两个语义化版本号：a<b 返回 -1，相等返回 0，a>b 返回 1。
/// 兼容 "v" 前缀与 "+build" / "-预发布" 后缀。
int compareVersions(String a, String b) {
  final aParts = _normalizeVersion(a).split('.').map(int.parse).toList();
  final bParts = _normalizeVersion(b).split('.').map(int.parse).toList();
  final len = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < len; i++) {
    final av = i < aParts.length ? aParts[i] : 0;
    final bv = i < bParts.length ? bParts[i] : 0;
    if (av != bv) return av > bv ? 1 : -1;
  }
  return 0;
}

String _normalizeVersion(String version) {
  var s = version.trim().toLowerCase();
  if (s.startsWith('v')) s = s.substring(1);
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  final dash = s.indexOf('-');
  if (dash >= 0) s = s.substring(0, dash);
  return s;
}

/// GitHub 最新 Release 信息
class RemoteRelease {
  final String tagName;
  final String name;
  final String htmlUrl;
  final String? notes;

  const RemoteRelease({
    required this.tagName,
    required this.name,
    required this.htmlUrl,
    this.notes,
  });
}

/// 检查更新结果
class UpdateCheckResult {
  final RemoteRelease? release;
  final String? errorMessage;

  /// 远端版本是否比 [currentVersion] 更新
  final bool isNewer;

  const UpdateCheckResult({
    this.release,
    this.errorMessage,
    this.isNewer = false,
  });
}

/// 通过 GitHub Releases API 检查新版本。
class UpdateChecker {
  UpdateChecker._();

  static Future<UpdateCheckResult> checkForUpdate(
    String currentVersion, {
    UpdateTransport? transport,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'BearFuel/${AppConfig.versionName}',
    };

    try {
      final response = transport == null
          ? await _request(
              Uri.parse(AppConfig.githubLatestReleaseApiUrl),
              headers,
            )
          : await transport(
              Uri.parse(AppConfig.githubLatestReleaseApiUrl),
              Map.unmodifiable(headers),
            );
      final result = _parseResponse(response, currentVersion);
      // GitHub REST API 有独立的匿名额度；403/429 时改读公开 raw 文件，
      // 不需要 Token，避免“接口请求受限”直接阻断更新检查。
      if (result.release == null && _isRateLimited(response.statusCode)) {
        final fallback = transport == null
            ? await _checkAtomFeed(currentVersion)
            : await _checkAtomFeedWithTransport(currentVersion, transport);
        if (fallback.release != null || fallback.errorMessage == null) {
          return fallback;
        }
        final rawFallback = transport == null
            ? await _checkRawManifest(currentVersion)
            : await _checkRawManifestWithTransport(currentVersion, transport);
        if (rawFallback.release != null) return rawFallback;
      }
      return result;
    } on SocketException {
      return const UpdateCheckResult(errorMessage: '网络连接失败，请检查网络后重试');
    } on TimeoutException {
      return const UpdateCheckResult(errorMessage: 'GitHub 请求超时，请稍后重试');
    } on FormatException {
      return const UpdateCheckResult(errorMessage: 'GitHub 返回的数据格式无效');
    } catch (_) {
      return const UpdateCheckResult(errorMessage: '检查更新失败，请稍后重试');
    }
  }

  static bool _isRateLimited(int statusCode) =>
      statusCode == HttpStatus.forbidden ||
      statusCode == HttpStatus.tooManyRequests;

  /// API 受限时从公开 raw 文件读取 main 的版本与首个 CHANGELOG 条目。
  /// 这条路径只验证公开仓库内容，不请求 GitHub Release API。
  static Future<UpdateCheckResult> _checkAtomFeedWithTransport(
    String currentVersion,
    UpdateTransport transport,
  ) async {
    final response = await transport(
      Uri.parse(AppConfig.githubReleasesAtomUrl),
      const {'User-Agent': 'BearFuel/update-check'},
    );
    if (response.statusCode != HttpStatus.ok) {
      return const UpdateCheckResult(errorMessage: 'GitHub Release 订阅源暂时不可用');
    }
    final tagMatch = RegExp(
      r'<entry>[\s\S]*?<title>v?([^<]+)</title>',
      caseSensitive: false,
    ).firstMatch(response.body);
    if (tagMatch == null) {
      return const UpdateCheckResult(errorMessage: 'GitHub Release 订阅源格式无效');
    }
    final version = tagMatch.group(1)!.trim();
    final linkMatch = RegExp(
      r'<link[^>]+href="([^"]+/releases/tag/[^"]+)"',
      caseSensitive: false,
    ).firstMatch(response.body);
    return UpdateCheckResult(
      release: RemoteRelease(
        tagName: 'v${_normalizeVersion(version)}',
        name: 'BearFuel $version',
        htmlUrl: linkMatch?.group(1) ?? AppConfig.githubLatestReleaseUrl,
      ),
      isNewer: compareVersions(version, currentVersion) > 0,
    );
  }

  static Future<UpdateCheckResult> _checkAtomFeed(String currentVersion) async {
    try {
      final response = await _request(
        Uri.parse(AppConfig.githubReleasesAtomUrl),
        const {'User-Agent': 'BearFuel/update-check'},
      );
      return _parseAtomFeed(response, currentVersion);
    } catch (_) {
      return const UpdateCheckResult(errorMessage: 'GitHub Release 订阅源暂时不可用');
    }
  }

  static UpdateCheckResult _parseAtomFeed(
    UpdateHttpResponse response,
    String currentVersion,
  ) {
    if (response.statusCode != HttpStatus.ok) {
      return const UpdateCheckResult(errorMessage: 'GitHub Release 订阅源暂时不可用');
    }
    final tagMatch = RegExp(
      r'<entry>[\s\S]*?<title>v?([^<]+)</title>',
      caseSensitive: false,
    ).firstMatch(response.body);
    if (tagMatch == null) {
      return const UpdateCheckResult(errorMessage: 'GitHub Release 订阅源格式无效');
    }
    final version = tagMatch.group(1)!.trim();
    final linkMatch = RegExp(
      r'<link[^>]+href="([^"]+/releases/tag/[^"]+)"',
      caseSensitive: false,
    ).firstMatch(response.body);
    return UpdateCheckResult(
      release: RemoteRelease(
        tagName: 'v${_normalizeVersion(version)}',
        name: 'BearFuel $version',
        htmlUrl: linkMatch?.group(1) ?? AppConfig.githubLatestReleaseUrl,
      ),
      isNewer: compareVersions(version, currentVersion) > 0,
    );
  }

  /// API/Atom 均不可用时，从公开 raw 的 pubspec 与 CHANGELOG 最后兜底。
  static Future<UpdateCheckResult> _checkRawManifest(
    String currentVersion,
  ) async {
    try {
      final pubspec = await _request(
        Uri.parse(AppConfig.githubRawPubspecUrl),
        const {'User-Agent': 'BearFuel/update-check'},
      );
      if (pubspec.statusCode != HttpStatus.ok) {
        return const UpdateCheckResult(errorMessage: 'GitHub 更新源暂时不可用，请稍后重试');
      }
      final versionMatch = RegExp(
        r'^version:\s*([^\s]+)',
        multiLine: true,
      ).firstMatch(pubspec.body);
      if (versionMatch == null) {
        return const UpdateCheckResult(errorMessage: '版本清单格式无效');
      }
      final version = versionMatch.group(1)!.trim();
      final changelog = await _request(
        Uri.parse(AppConfig.githubRawChangelogUrl),
        const {'User-Agent': 'BearFuel/update-check'},
      );
      String notes = '';
      if (changelog.statusCode == HttpStatus.ok) {
        final lines = changelog.body.split('\n');
        final heading = '## [$version]';
        final start = lines.indexWhere(
          (line) => line.trim().startsWith(heading),
        );
        if (start >= 0) {
          final noteLines = <String>[];
          for (var i = start + 1; i < lines.length; i++) {
            if (lines[i].trim().startsWith('## ')) break;
            noteLines.add(lines[i]);
          }
          notes = noteLines.join('\n').trim();
        }
      }
      final release = RemoteRelease(
        tagName: 'v${_normalizeVersion(version)}',
        name: 'BearFuel $version',
        htmlUrl: AppConfig.githubLatestReleaseUrl,
        notes: notes,
      );
      return UpdateCheckResult(
        release: release,
        isNewer: compareVersions(version, currentVersion) > 0,
      );
    } catch (_) {
      return const UpdateCheckResult(errorMessage: 'GitHub 更新源暂时不可用，请稍后重试');
    }
  }

  static Future<UpdateCheckResult> _checkRawManifestWithTransport(
    String currentVersion,
    UpdateTransport transport,
  ) async {
    try {
      final pubspec = await transport(
        Uri.parse(AppConfig.githubRawPubspecUrl),
        const {'User-Agent': 'BearFuel/update-check'},
      );
      if (pubspec.statusCode != HttpStatus.ok) {
        return const UpdateCheckResult(errorMessage: 'GitHub 更新源暂时不可用，请稍后重试');
      }
      final versionMatch = RegExp(
        r'^version:\s*([^\s]+)',
        multiLine: true,
      ).firstMatch(pubspec.body);
      if (versionMatch == null) {
        return const UpdateCheckResult(errorMessage: '版本清单格式无效');
      }
      final version = versionMatch.group(1)!.trim();
      final changelog = await transport(
        Uri.parse(AppConfig.githubRawChangelogUrl),
        const {'User-Agent': 'BearFuel/update-check'},
      );
      var notes = '';
      if (changelog.statusCode == HttpStatus.ok) {
        final lines = changelog.body.split('\n');
        final start = lines.indexWhere(
          (line) => line.trim().startsWith('## [$version]'),
        );
        if (start >= 0) {
          final noteLines = <String>[];
          for (var i = start + 1; i < lines.length; i++) {
            if (lines[i].trim().startsWith('## ')) break;
            noteLines.add(lines[i]);
          }
          notes = noteLines.join('\n').trim();
        }
      }
      final release = RemoteRelease(
        tagName: 'v${_normalizeVersion(version)}',
        name: 'BearFuel $version',
        htmlUrl: AppConfig.githubLatestReleaseUrl,
        notes: notes,
      );
      return UpdateCheckResult(
        release: release,
        isNewer: compareVersions(version, currentVersion) > 0,
      );
    } catch (_) {
      return const UpdateCheckResult(errorMessage: 'GitHub 更新源暂时不可用，请稍后重试');
    }
  }

  static Future<UpdateHttpResponse> _request(
    Uri uri,
    Map<String, String> headers,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(',');
      });
      return UpdateHttpResponse(
        statusCode: response.statusCode,
        body: body,
        headers: responseHeaders,
      );
    } finally {
      client?.close(force: true);
    }
  }

  static UpdateCheckResult _parseResponse(
    UpdateHttpResponse response,
    String currentVersion,
  ) {
    if (response.statusCode != HttpStatus.ok) {
      final retryAfter = response.headers['retry-after'];
      final remaining = response.headers['x-ratelimit-remaining'];
      if (response.statusCode == HttpStatus.forbidden &&
          (retryAfter != null || remaining == '0')) {
        final suffix = retryAfter == null ? '' : '，约 $retryAfter 秒后重试';
        return UpdateCheckResult(
          errorMessage: 'GitHub API 匿名请求额度已用尽，请稍后重试$suffix',
        );
      }
      final message = switch (response.statusCode) {
        HttpStatus.forbidden => 'GitHub 拒绝了请求，请稍后重试或检查网络策略',
        HttpStatus.notFound => '暂无可访问的公开 Release',
        >= 500 && < 600 => 'GitHub 服务暂时不可用，请稍后重试',
        _ => 'GitHub 返回 HTTP ${response.statusCode}',
      };
      return UpdateCheckResult(errorMessage: message);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('release response is not an object');
    }
    final tagName = (decoded['tag_name'] ?? '').toString().trim();
    if (tagName.isEmpty) {
      return const UpdateCheckResult(errorMessage: '仓库尚未发布任何 Release');
    }
    final release = RemoteRelease(
      tagName: tagName,
      name: (decoded['name'] ?? tagName).toString(),
      htmlUrl: (decoded['html_url'] ?? AppConfig.githubReleasesUrl).toString(),
      notes: (decoded['body'] ?? '').toString().trim(),
    );
    return UpdateCheckResult(
      release: release,
      isNewer: compareVersions(release.tagName, currentVersion) > 0,
    );
  }
}

/// 单个版本的更新日志条目
class ChangelogEntry {
  final String version;
  final String? date;

  /// 条目正文（保留 "- " / "### " 前缀的原始行）
  final List<String> lines;

  const ChangelogEntry({
    required this.version,
    this.date,
    this.lines = const [],
  });

  String get title =>
      date == null || date!.isEmpty ? version : '$version（$date）';
}

/// 解析 CHANGELOG.md（Keep-a-Changelog 风格 "## [x.y.z] - 日期"）。
class ChangelogParser {
  ChangelogParser._();

  static final RegExp _heading = RegExp(r'^##\s+\[([^\]]+)\]\s*-?\s*(.*)$');

  static List<ChangelogEntry> parse(String markdown) {
    final entries = <ChangelogEntry>[];
    ChangelogEntry? current;
    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      final match = _heading.firstMatch(trimmed);
      if (match != null) {
        current = ChangelogEntry(
          version: match.group(1)!.trim(),
          date: match.group(2)!.trim(),
          lines: <String>[],
        );
        entries.add(current);
        continue;
      }
      if (current == null || trimmed.isEmpty) continue;
      // 跳过文末的链接定义（如 "[0.2.5]: https://..."）
      if (trimmed.startsWith('[') && trimmed.contains(']:')) continue;
      // 保留原始缩进，便于界面区分一级条目与二级条目
      current.lines.add(line);
    }
    return entries;
  }
}
