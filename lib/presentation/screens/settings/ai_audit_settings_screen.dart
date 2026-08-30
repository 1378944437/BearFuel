import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/services/ai_audit_config_store.dart';
import '../../../data/services/ai_audit_service.dart';
import '../../widgets/custom_card.dart';
import 'ai_provider_edit_screen.dart';

/// AI 审查服务设置（第一层：供应商列表）。
///
/// 层级结构：
/// 服务设置 → 本页（供应商清单，选择激活供应商）→ 供应商编辑页（连接与模型管理）。
/// 可保存多个供应商，支持 OpenAI 兼容 / OpenAI Responses / Anthropic / Gemini 接口；
/// 发起 AI 审查时使用激活供应商的激活模型（审查页可临时切换模型）。
class AiAuditSettingsScreen extends StatefulWidget {
  const AiAuditSettingsScreen({super.key});

  @override
  State<AiAuditSettingsScreen> createState() => _AiAuditSettingsScreenState();
}

class _AiAuditSettingsScreenState extends State<AiAuditSettingsScreen> {
  List<AiProviderProfile> _profiles = [];
  String _activeId = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _profiles = AiAuditConfigStore.profiles
          .map((p) => AiProviderProfile.fromJson(p.toJson()))
          .toList();
      _activeId = AiAuditConfigStore.activeProfile?.id ?? '';
    });
  }

  Future<void> _addProfile() async {
    final nameController = TextEditingController();
    String interfaceType = AiInterfaceType.openai;
    final created = await showDialog<AiProviderProfile>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('新增 AI 供应商'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                inputFormatters: [AppInputFormatters.maxChars(30)],
                decoration: const InputDecoration(
                  labelText: '服务名称（选填）',
                  hintText: '如 DeepSeek / Claude / Gemini',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: interfaceType,
                decoration: const InputDecoration(labelText: '接口类型'),
                items: [
                  for (final type in AiInterfaceType.all)
                    DropdownMenuItem(
                      value: type,
                      child: Text(AiInterfaceType.label(type)),
                    ),
                ],
                onChanged: (v) => setDialog(
                  () => interfaceType = v ?? AiInterfaceType.openai,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5A24),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(
                ctx,
                AiProviderProfile(
                  id: 'p_${DateTime.now().microsecondsSinceEpoch}',
                  name: nameController.text.trim(),
                  interfaceType: interfaceType,
                  baseUrl: AiInterfaceType.defaultBaseUrl(interfaceType),
                ),
              ),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (created == null) return;
    await AiAuditConfigStore.saveProfile(created);
    if (!mounted) return;
    _reload();
    await _openEditor(created.id);
  }

  Future<void> _openEditor(String profileId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiProviderEditScreen(profileId: profileId),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  Future<void> _setActive(String id) async {
    if (id == _activeId) return;
    await AiAuditConfigStore.setActiveProfile(id);
    if (!mounted) return;
    _reload();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清除全部 AI 配置'),
        content: const Text(
          '将删除所有供应商的 Base URL、API Key 与模型清单。清除后账本审查仍可使用本地规则。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('全部清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AiAuditConfigStore.clear();
    if (!mounted) return;
    _reload();
    _showMessage('已清除全部 AI 配置', Colors.orange);
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 审查服务'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.add, size: 20),
            tooltip: '新增供应商',
            onPressed: _addProfile,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '支持保存多个 AI 供应商（OpenAI 兼容 / OpenAI Responses / '
            'Anthropic / Gemini 接口），发起 AI 审查时使用激活供应商的激活模型。'
            'AI 结果仅用于辅助审查，原始账单不会被 AI 修改。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          if (_profiles.isEmpty)
            CustomCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    AppIcons.auto_awesome_outlined,
                    size: 32,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  const Text('尚未添加 AI 供应商'),
                  const SizedBox(height: 4),
                  Text(
                    '未配置 AI 时，本地规则审查始终可用',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _addProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5A24),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(AppIcons.add, size: 16),
                    label: const Text('新增供应商'),
                  ),
                ],
              ),
            )
          else
            for (final p in _profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildProviderTile(colors, p),
              ),
          const SizedBox(height: 4),
          _buildPrivacyCard(colors),
        ],
      ),
    );
  }

  Widget _buildProviderTile(ColorScheme colors, AiProviderProfile p) {
    final isActive = p.id == _activeId;
    const accent = Color(0xFFFF5A24);
    return CustomCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openEditor(p.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _setActive(p.id),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isActive ? AppIcons.check_circle : AppIcons.circle_outlined,
                    size: 20,
                    color: isActive ? accent : colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name.isEmpty
                                ? AiInterfaceType.label(p.interfaceType)
                                : p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '使用中',
                              style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFFFF5A24),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${AiInterfaceType.label(p.interfaceType)}'
                      ' · 默认模型: ${p.activeModel.isEmpty ? '未设置' : p.activeModel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${p.models.length} 个模型',
                style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: 2),
              Icon(
                AppIcons.keyboard_arrow_down,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyCard(ColorScheme colors) {
    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '隐私与安全',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            '· API Key 与模型清单保存在本机安全存储，不进入备份文件与日志\n'
            '· 仅发送异常记录的必要字段（日期、里程、油量、价格、油品），\n'
            '  不发送车牌号、完整备注与定位信息\n'
            '· AI 返回内容经过结构校验，非法响应不会展示\n'
            '· AI 不直接修改账单，任何修改都需你确认\n'
            '· 未配置 AI 时，本地规则审查仍然可用',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _profiles.isEmpty ? null : _clear,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(AppIcons.delete_outline, size: 16),
              label: const Text('清除全部配置'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'BearFuel ${AppConfig.versionName} · 提示词版本 ${AiAuditService.promptVersion}',
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
