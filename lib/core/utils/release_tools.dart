import 'dart:convert';
import 'dart:io';

import '../../core/config/app_config.dart';

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

  static Future<UpdateCheckResult> checkForUpdate(String currentVersion) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client
          .getUrl(Uri.parse(AppConfig.githubLatestReleaseApiUrl))
          .timeout(const Duration(seconds: 5));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'BearFuel/${AppConfig.versionName}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      // 响应体读取加超时，防止服务器中途停摆
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        // 403：多为接口限流或网络拦截；404：仓库为私有或尚无 Release，
        // 私有仓库无法匿名读取发布信息。
        final message = response.statusCode == HttpStatus.forbidden
            ? 'GitHub 接口请求受限（403），请稍后重试'
            : response.statusCode == HttpStatus.notFound
            ? '仓库为私有或暂无 Release，无法在线检查更新'
            : 'GitHub 返回 HTTP ${response.statusCode}';
        return UpdateCheckResult(errorMessage: message);
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const UpdateCheckResult(errorMessage: '接口返回的 JSON 结构无效');
      }
      final tagName = (decoded['tag_name'] ?? '').toString();
      if (tagName.isEmpty) {
        return const UpdateCheckResult(errorMessage: '仓库尚未发布任何 Release');
      }
      final release = RemoteRelease(
        tagName: tagName,
        name: (decoded['name'] ?? tagName).toString(),
        htmlUrl: (decoded['html_url'] ?? AppConfig.githubReleasesUrl)
            .toString(),
        notes: (decoded['body'] ?? '').toString().trim(),
      );
      return UpdateCheckResult(
        release: release,
        isNewer: compareVersions(release.tagName, currentVersion) > 0,
      );
    } catch (_) {
      return const UpdateCheckResult(errorMessage: '检查更新失败，请检查网络后重试');
    } finally {
      client?.close(force: true);
    }
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
