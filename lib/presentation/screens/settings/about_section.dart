import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/external_url_launcher.dart';
import '../../../core/utils/release_tools.dart';
import '../../widgets/custom_card.dart';

/// "关于应用"板块：版本信息、检查更新、GitHub Release、
/// 更新日志与构建发布入口。
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Row(
            children: [
              Icon(AppIcons.info_outline, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text('关于应用', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 12),
              Expanded(child: Divider(color: colors.outlineVariant)),
            ],
          ),
        ),
        _VersionTile(),
        _AboutTile(
          icon: AppIcons.file_download_outlined,
          color: const Color(0xFF1D7A52),
          title: '检查更新',
          subtitle: '通过 GitHub Releases 检测新版本',
          onTap: () => _runUpdateCheck(context),
        ),
        _AboutTile(
          icon: AppIcons.menu_book_outlined,
          color: const Color(0xFF6558D3),
          title: '更新日志',
          subtitle: '应用内查看历届版本变更说明',
          onTap: () => _showChangelogSheet(context),
        ),
        _AboutTile(
          icon: AppIcons.build_circle_outlined,
          color: const Color(0xFFFF5A24),
          title: '构建与发布',
          subtitle: '推送版本标签触发远端构建，自动发布 Release',
          onTap: () => _showReleasePipelineSheet(context),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 检查更新
  // ------------------------------------------------------------------
  Future<void> _runUpdateCheck(BuildContext context) async {
    // 收集当前版本：优先安装包信息，失败时回退到编译期注入的版本名
    String currentVersion = AppConfig.versionName;
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) currentVersion = info.version;
    } catch (_) {}

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 18),
              Expanded(child: Text('正在检查更新…')),
            ],
          ),
        ),
      ),
    );

    final result = await UpdateChecker.checkForUpdate(currentVersion);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage!),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final release = result.release!;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(result.isNewer ? '发现新版本' : '已是最新版本'),
        content: result.isNewer
            ? SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${release.name.isNotEmpty ? release.name : release.tagName} 已发布，'
                      '当前版本 v$currentVersion。',
                    ),
                    if ((release.notes ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        release.notes!,
                        maxLines: 14,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ],
                  ],
                ),
              )
            : Text(
                '当前版本 v$currentVersion 已与最新 Release '
                '${release.tagName} 一致。',
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('关闭'),
          ),
          if (result.isNewer)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                ExternalUrlLauncher.open(release.htmlUrl);
              },
              child: const Text('打开下载页'),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 更新日志
  // ------------------------------------------------------------------
  Future<void> _showChangelogSheet(BuildContext context) async {
    String markdown;
    try {
      markdown = await rootBundle.loadString('CHANGELOG.md');
    } catch (_) {
      markdown = '';
    }
    final entries = ChangelogParser.parse(markdown);

    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final colors = Theme.of(sheetCtx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          maxChildSize: 0.94,
          minChildSize: 0.5,
          expand: false,
          builder: (innerCtx, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(sheetCtx).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      children: [
                        Text(
                          '更新日志',
                          style: Theme.of(sheetCtx).textTheme.titleLarge,
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Text(
                              '未能读取更新日志',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 24,
                              color: colors.outlineVariant,
                            ),
                            itemBuilder: (innerCtx, index) {
                              final entry = entries[index];
                              final isFirst = index == 0;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Text(
                                        entry.title,
                                        style: Theme.of(sheetCtx)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: isFirst
                                                  ? AppBrandColors.brand
                                                  : null,
                                            ),
                                      ),
                                      if (isFirst) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppBrandColors.brand
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            '当前版本',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppBrandColors.brand,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ...entry.lines.map(
                                    (line) => _ChangelogLine(text: line),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // 构建与发布
  // ------------------------------------------------------------------
  void _showReleasePipelineSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final colors = Theme.of(sheetCtx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(sheetCtx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '构建与发布流水线',
                  style: Theme.of(sheetCtx).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '发布以远端构建为主，推送版本标签即可自动完成：',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                const _PipelineStep(
                  index: '1',
                  title: '升版',
                  description:
                      '更新 pubspec.yaml 的版本与 build 号，并在 CHANGELOG.md 写入本版变更说明。',
                ),
                const _PipelineStep(
                  index: '2',
                  title: '推送版本标签（远端构建）',
                  description:
                      '提交后推送 vX.Y.Z 标签，GitHub Actions 自动构建'
                      '签名 APK×3（armeabi-v7a / arm64-v8a / x86_64）+ 未签名 iOS IPA，'
                      '并发布 GitHub Release。',
                ),
                const _PipelineStep(
                  index: '3',
                  title: '本地构建（可选）',
                  description:
                      '发布前自验或离线安装时，可本地构建分架构 Android APK'
                      '（flutter build apk --release --split-per-abi，'
                      '检测到发布密钥时自动签名）。',
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetCtx).brightness == Brightness.dark
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFF5F6F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const SelectableText(
                    AppConfig.releaseCommand,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            const ClipboardData(text: AppConfig.releaseCommand),
                          );
                          ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            const SnackBar(content: Text('发布命令已复制到剪贴板')),
                          );
                        },
                        icon: const Icon(AppIcons.import_export, size: 16),
                        label: const Text('复制命令'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => ExternalUrlLauncher.open(
                          AppConfig.githubActionsUrl,
                        ),
                        icon: const Icon(AppIcons.open_in_new, size: 16),
                        label: const Text('构建进度'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => ExternalUrlLauncher.open(
                      AppConfig.githubLatestReleaseUrl,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppBrandColors.brand,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(AppIcons.file_download_outlined, size: 16),
                    label: const Text('打开发布页下载安装包'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '安装包包含：已签名 Android APK（三架构）与未签名 iOS IPA，'
                  '均附带 SHA-256 校验文件。',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =====================================================================
// 内部小组件
// =====================================================================

/// 版本信息卡片（读取安装包版本与 build 号）
class _VersionTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final versionText = info == null || info.version.isEmpty
            ? AppConfig.versionName
            : info.version;
        final subtitle = info == null || info.version.isEmpty
            ? '编译期注入版本：${AppConfig.versionName}'
            : 'BearFuel · 本地数据版，版本号以 pubspec 为唯一来源';
        return _AboutTile(
          icon: AppIcons.info_outline,
          color: const Color(0xFF1E88E5),
          title: '版本信息',
          subtitle: subtitle,
          trailingText: versionText,
          onTap: () => _showVersionDetailDialog(context, info),
        );
      },
    );
  }

  void _showVersionDetailDialog(BuildContext context, PackageInfo? info) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('版本信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('版本号', info?.version ?? AppConfig.versionName),
            _detailRow('Build 号', info?.buildNumber ?? '-'),
            _detailRow('包名', info?.packageName ?? '-'),
            _detailRow('发布渠道', 'GitHub Releases'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? trailingText;
  final VoidCallback onTap;

  const _AboutTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (trailingText != null)
                        Text(
                          trailingText!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: color,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              AppIcons.chevron_right,
              size: 17,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineStep extends StatelessWidget {
  final String index;
  final String title;
  final String description;

  const _PipelineStep({
    required this.index,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppBrandColors.brand.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              index,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppBrandColors.brand,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 更新日志正文行：区分小节标题、普通条目与缩进条目
class _ChangelogLine extends StatelessWidget {
  final String text;

  const _ChangelogLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (text.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          text.substring(4),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }
    var bullet = text;
    var indent = 0.0;
    if (bullet.startsWith('- ')) {
      bullet = bullet.substring(2);
      indent = 10;
    } else if (bullet.startsWith('  - ')) {
      bullet = bullet.substring(4);
      indent = 22;
    }
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (indent > 0)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          if (indent > 0) const SizedBox(width: 8),
          Expanded(
            child: Text(
              bullet,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
