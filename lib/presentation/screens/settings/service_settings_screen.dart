import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../data/services/amap_location_service.dart';
import '../../../data/services/fuel_price_api_config.dart';
import '../../../data/services/weather_api_config.dart';
import '../../widgets/custom_card.dart';
import '../audit/audit_review_screen.dart';
import 'about_section.dart';
import 'audit_rules_screen.dart';
import 'amap_key_settings_screen.dart';
import 'data_import_export_screen.dart';
import 'fuel_price_api_settings_screen.dart';
import 'weather_api_settings_screen.dart';

class ServiceSettingsScreen extends StatefulWidget {
  const ServiceSettingsScreen({super.key});

  @override
  State<ServiceSettingsScreen> createState() => _ServiceSettingsScreenState();
}

class _ServiceSettingsScreenState extends State<ServiceSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '连接与数据',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '管理服务连接与本地数据。密钥仅保存在当前设备。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const _SettingsSectionHeader(
            icon: AppIcons.network_check_outlined,
            title: '服务',
          ),
          _ServiceTile(
            icon: AppIcons.assessment_outlined,
            color: const Color(0xFF00838F),
            title: '账本审查',
            subtitle: '按规则库检查金额、里程、重复与油价差异，确认后修正',
            configured: true,
            statusLabel: '入口',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuditReviewScreen()),
            ),
          ),
          _ServiceTile(
            icon: AppIcons.auto_awesome_outlined,
            color: const Color(0xFF6558D3),
            title: '审查规则库',
            subtitle: '内置默认规则可编辑与恢复默认，支持多套规则切换',
            configured: true,
            optional: true,
            statusLabel: '可选',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AuditRuleSetsScreen()),
              );
              if (context.mounted) setState(() {});
            },
          ),
          _ServiceTile(
            icon: AppIcons.map_outlined,
            color: const Color(0xFFFF5A24),
            title: '地图服务',
            subtitle: AmapLocationService.isConfigured
                ? '高德服务已连接，可定位并查询附近加油站'
                : '尚未配置高德 Key，地图选站不会显示站点',
            configured: AmapLocationService.isConfigured,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AmapKeySettingsScreen()),
            ),
          ),
          _ServiceTile(
            icon: AppIcons.local_gas_station_outlined,
            color: const Color(0xFF007D83),
            title: '实时油价服务',
            subtitle: FuelPriceApiConfigStore.hasApiKey
                ? 'ApiZero 个人 Key 已配置'
                : '当前使用 ApiZero 匿名模式，可选配置个人 Key',
            configured: FuelPriceApiConfigStore.hasApiKey,
            optional: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FuelPriceApiSettingsScreen(),
              ),
            ),
          ),
          _ServiceTile(
            icon: AppIcons.cloud_outlined,
            color: const Color(0xFF1D7A52),
            title: '天气服务',
            subtitle: WeatherApiConfigStore.hasApiKey
                ? '墨迹天气个人 Key 已配置'
                : '当前使用墨迹天气匿名模式，可选配置个人 Key',
            configured: WeatherApiConfigStore.hasApiKey,
            optional: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WeatherApiSettingsScreen(),
              ),
            ),
          ),
          const _SettingsSectionHeader(
            icon: AppIcons.backup_outlined,
            title: '备份',
          ),
          _ServiceTile(
            icon: AppIcons.import_export,
            color: const Color(0xFF6558D3),
            title: '数据导入与备份',
            subtitle: '导入历史账本，或导出全部本地数据进行备份',
            configured: true,
            statusLabel: '本地',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataImportExportScreen()),
            ),
          ),

          // 关于应用：版本 / 检查更新 / Release / 更新日志 / 构建与发布
          const AboutSection(),
        ],
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SettingsSectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: colors.outlineVariant)),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool configured;
  final bool optional;
  final String? statusLabel;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.configured,
    required this.onTap,
    this.optional = false,
    this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status =
        statusLabel ?? (configured ? '已连接' : (optional ? '匿名模式' : '待配置'));
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
                      Text(
                        status,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: configured || optional ? color : colors.error,
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
