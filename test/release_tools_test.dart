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
# Changelog

BearFuel follows semantic versioning.

## [0.2.13] - 2026-08-29

### Added

- 关于应用板块
  - 内含更新日志一栏

## [0.2.12] - 2026-08-29

- 修复账本左滑无法退出。

[0.2.5]: https://github.com/1378944437/BearFuel/releases/tag/v0.2.5
''';

    test('按 "## [版本] - 日期" 切分条目', () {
      final entries = ChangelogParser.parse(sample);
      expect(entries.length, equals(2));
      expect(entries[0].version, equals('0.2.13'));
      expect(entries[0].date, equals('2026-08-29'));
      expect(entries[0].title, equals('0.2.13（2026-08-29）'));
      expect(entries[1].version, equals('0.2.12'));
    });

    test('保留小节标题与条目行, 忽略空行与底部链接定义', () {
      final entries = ChangelogParser.parse(sample);
      expect(entries[0].lines, contains('### Added'));
      expect(entries[0].lines, contains('- 关于应用板块'));
      expect(entries[0].lines, contains('  - 内含更新日志一栏'));
      expect(entries.any((e) => e.lines.any((l) => l.contains(']:'))), isFalse);
      expect(entries[1].lines, contains('- 修复账本左滑无法退出。'));
    });

    test('无内容时返回空列表', () {
      expect(ChangelogParser.parse(''), isEmpty);
      expect(ChangelogParser.parse('# Changelog\n\n说明文字'), isEmpty);
    });
  });
}
