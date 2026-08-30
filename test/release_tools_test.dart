import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/core/utils/release_tools.dart';

void main() {
  group('版本号比较 (compareVersions)', () {
    test('常规语义化版本比较', () {
      expect(compareVersions('0.2.13', '0.2.12'), equals(1));
      expect(compareVersions('0.2.12', '0.2.13'), equals(-1));
      expect(compareVersions('1.0.0', '1.0.0'), equals(0));
      expect(compareVersions('0.3.0', '0.2.99'), equals(1));
      expect(compareVersions('1.0.0', '0.99.99'), equals(1));
    });

    test('兼容 v 前缀与 build / 预发布后缀', () {
      expect(compareVersions('v0.2.13', '0.2.12'), equals(1));
      expect(compareVersions('v0.2.12', '0.2.12+23'), equals(0));
      expect(compareVersions('0.2.13-beta', '0.2.12'), equals(1));
      expect(compareVersions('v1.0.0+24', 'v1.0.0'), equals(0));
    });

    test('段数不一致时按 0 补齐', () {
      expect(compareVersions('1.0', '1.0.0'), equals(0));
      expect(compareVersions('1.1', '1.0.5'), equals(1));
    });
  });

  group('更新日志解析 (ChangelogParser)', () {
    const sample = '''
# 更新日志

## [0.2.13] - 2026-08-29

### 新增

- 关于应用板块
  - 内含更新日志一栏

## [0.2.12] - 2026-08-29

- 修复账本左滑无法退出。

[0.2.5]: https://github.com/1378944437/BearFuel/releases/tag/v0.2.5
''';

    test('按版本标题切分条目', () {
      final entries = ChangelogParser.parse(sample);
      expect(entries.length, equals(2));
      expect(entries[0].version, equals('0.2.13'));
      expect(entries[0].date, equals('2026-08-29'));
      expect(entries[0].title, equals('0.2.13（2026-08-29）'));
      expect(entries[1].version, equals('0.2.12'));
    });

    test('保留小节与缩进行, 忽略链接定义', () {
      final entries = ChangelogParser.parse(sample);
      expect(entries[0].lines, contains('### 新增'));
      expect(entries[0].lines, contains('- 关于应用板块'));
      expect(entries[0].lines, contains('  - 内含更新日志一栏'));
      expect(entries.any((e) => e.lines.any((l) => l.contains(']:'))), isFalse);
    });

    test('无内容时返回空列表', () {
      expect(ChangelogParser.parse(''), isEmpty);
      expect(ChangelogParser.parse('# 更新日志\n\n说明文字'), isEmpty);
    });
  });

  group('更新检查网络结果', () {
    test('正常响应解析最新版本且不发送授权头', () async {
      final seen = <Map<String, String>>[];
      final result = await UpdateChecker.checkForUpdate(
        '0.2.20',
        transport: (uri, headers) async {
          seen.add(headers);
          return const UpdateHttpResponse(
            statusCode: 200,
            body:
                '{"tag_name":"v0.2.21","name":"BearFuel 0.2.21","html_url":"https://github.com/1378944437/BearFuel/releases/tag/v0.2.21","body":"修复更新检查"}',
          );
        },
      );
      expect(result.release?.tagName, 'v0.2.21');
      expect(result.isNewer, isTrue);
      expect(seen.single.containsKey('Authorization'), isFalse);
    });

    test('403 限流时回退公开 Release Atom 订阅源', () async {
      final requested = <String>[];
      final result = await UpdateChecker.checkForUpdate(
        '0.2.20',
        transport: (uri, headers) async {
          requested.add(uri.toString());
          if (uri.toString().contains('api.github.com')) {
            return const UpdateHttpResponse(
              statusCode: 403,
              body: '{"message":"rate limit"}',
              headers: {'x-ratelimit-remaining': '0', 'retry-after': '60'},
            );
          }
          if (uri.toString().contains('releases.atom')) {
            return const UpdateHttpResponse(
              statusCode: 200,
              body:
                  '<feed><entry><title>v0.2.21</title><link href="https://github.com/1378944437/BearFuel/releases/tag/v0.2.21"/></entry></feed>',
            );
          }
          return const UpdateHttpResponse(statusCode: 500, body: '{}');
        },
      );
      expect(result.release?.tagName, 'v0.2.21');
      expect(result.isNewer, isTrue);
      expect(
        requested.any(
          (url) => url.contains('github.com/1378944437/BearFuel/releases.atom'),
        ),
        isTrue,
      );
      expect(
        requested.any((url) => url.contains('raw.githubusercontent.com')),
        isFalse,
      );
    });

    test('Atom 失败时回退公开 raw 版本清单', () async {
      final requested = <String>[];
      final result = await UpdateChecker.checkForUpdate(
        '0.2.20',
        transport: (uri, headers) async {
          requested.add(uri.toString());
          if (uri.toString().contains('api.github.com') ||
              uri.toString().contains('releases.atom')) {
            return const UpdateHttpResponse(statusCode: 403, body: '{}');
          }
          if (uri.toString().endsWith('pubspec.yaml')) {
            return const UpdateHttpResponse(
              statusCode: 200,
              body: 'name: bearfuel\nversion: 0.2.21+32\n',
            );
          }
          return const UpdateHttpResponse(
            statusCode: 200,
            body: '# 更新日志\n\n## [0.2.21] - 2026-08-30\n\n- 修复更新检查。\n',
          );
        },
      );
      expect(result.release?.tagName, 'v0.2.21');
      expect(result.isNewer, isTrue);
      expect(
        requested.any((url) => url.contains('raw.githubusercontent.com')),
        isTrue,
      );
    });
    test('403 非限流请求给出明确拒绝提示', () async {
      final result = await UpdateChecker.checkForUpdate(
        '0.2.20',
        transport: (uri, headers) async => const UpdateHttpResponse(
          statusCode: 403,
          body: '{"message":"forbidden"}',
          headers: {'x-ratelimit-remaining': '12'},
        ),
      );
      expect(result.release, isNull);
      expect(result.errorMessage, contains('拒绝'));
    });

    test('404 与 5xx 给出可操作提示', () async {
      final notFound = await UpdateChecker.checkForUpdate(
        '0.2.20',
        transport: (uri, headers) async =>
            const UpdateHttpResponse(statusCode: 404, body: '{}'),
      );
      final serverError = await UpdateChecker.checkForUpdate(
        '0.2.20',
        transport: (uri, headers) async =>
            const UpdateHttpResponse(statusCode: 503, body: '{}'),
      );
      expect(notFound.errorMessage, contains('暂无可访问的公开 Release'));
      expect(serverError.errorMessage, contains('暂时不可用'));
    });
  });
}
