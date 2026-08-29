import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/input_formatters.dart';
import '../../../data/services/ai_audit_config_store.dart';
import '../../../data/services/ai_audit_service.dart';
import '../../../core/config/app_config.dart';
import '../../widgets/custom_card.dart';

/// AI 账本审查服务设置（OpenAI 兼容接口）
class AiAuditSettingsScreen extends StatefulWidget {
  const AiAuditSettingsScreen({super.key});

  @override
  State<AiAuditSettingsScreen> createState() => _AiAuditSettingsScreenState();
}

class _AiAuditSettingsScreenState extends State<AiAuditSettingsScreen> {
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  late TextEditingController _serviceNameController;

  bool _obscureKey = true;
  bool _isTesting = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: AiAuditConfigStore.baseUrl,
    );
    _apiKeyController = TextEditingController(text: AiAuditConfigStore.apiKey);
    _modelController = TextEditingController(text: AiAuditConfigStore.model);
    _serviceNameController = TextEditingController(
      text: AiAuditConfigStore.serviceName == '自定义服务'
          ? ''
          : AiAuditConfigStore.serviceName,
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _serviceNameController.dispose();
    super.dispose();
  }

  bool get _hasChanges =>
      _baseUrlController.text.trim() != AiAuditConfigStore.baseUrl ||
      _apiKeyController.text.trim() != AiAuditConfigStore.apiKey ||
      _modelController.text.trim() != AiAuditConfigStore.model ||
      _serviceNameController.text.trim() !=
          (AiAuditConfigStore.serviceName == '自定义服务'
              ? ''
              : AiAuditConfigStore.serviceName);

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isNotEmpty && !baseUrl.startsWith('http')) {
      _showMessage('Base URL 需以 http(s):// 开头', Colors.red);
      return;
    }
    await AiAuditConfigStore.save(
      baseUrl: baseUrl,
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      serviceName: _serviceNameController.text.trim(),
    );
    if (!mounted) return;
    _showMessage('AI 审查配置已保存到本机安全存储', Colors.green);
    setState(() {});
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    // 先临时应用当前输入再测试
    await AiAuditConfigStore.save(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      serviceName: _serviceNameController.text.trim(),
    );
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final (ok, message) = await AiAuditService.testConnection();
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testOk = ok;
      _testResult = message;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清除本机 AI 配置'),
        content: const Text('将删除本机保存的 Base URL、API Key 与模型名称。清除后账本审查仍可使用本地规则。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AiAuditConfigStore.clear();
    _baseUrlController.clear();
    _apiKeyController.clear();
    _modelController.clear();
    _serviceNameController.clear();
    if (!mounted) return;
    setState(() {
      _testResult = null;
    });
    _showMessage('已清除本机 AI 配置', Colors.orange);
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
      appBar: AppBar(title: const Text('AI 账本审查设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '连接 OpenAI 兼容接口，用于解释账本异常与给出修正建议。'
            'AI 结果仅用于辅助审查，不代表事实确认；原始账单不会被 AI 修改。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          CustomCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _serviceNameController,
                  inputFormatters: [AppInputFormatters.maxChars(30)],
                  decoration: const InputDecoration(
                    labelText: '服务名称（选填）',
                    hintText: '如 OpenRouter / DeepSeek / 本地中转',
                    prefixIcon: Icon(AppIcons.branding_watermark_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _baseUrlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Base URL *',
                    hintText: 'https://api.example.com/v1',
                    prefixIcon: Icon(AppIcons.link),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '将拼接为 {Base URL}/chat/completions',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API Key *',
                    hintText: 'sk-...',
                    prefixIcon: const Icon(AppIcons.gps_fixed),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey
                            ? AppIcons.arrow_drop_down
                            : AppIcons.arrow_drop_down,
                      ),
                      tooltip: _obscureKey ? '显示 Key' : '隐藏 Key',
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _modelController,
                  autocorrect: false,
                  inputFormatters: [AppInputFormatters.maxChars(80)],
                  decoration: const InputDecoration(
                    labelText: '模型名称 *',
                    hintText: '如 gpt-4o-mini / deepseek-chat',
                    prefixIcon: Icon(AppIcons.auto_awesome_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isTesting ? null : _test,
                        icon: _isTesting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                AppIcons.network_check_outlined,
                                size: 16,
                              ),
                        label: const Text('测试连接'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _hasChanges || _testResult != null
                            ? _save
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5A24),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(AppIcons.backup_outlined, size: 16),
                        label: const Text('保存配置'),
                      ),
                    ),
                  ],
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        _testOk
                            ? AppIcons.check_circle
                            : AppIcons.warning_amber_rounded,
                        size: 15,
                        color: _testOk ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _testOk ? Colors.green : Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          CustomCard(
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
                  '· API Key 保存在本机安全存储，不进入备份文件与日志\n'
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
                    onPressed: _clear,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    icon: const Icon(AppIcons.delete_outline, size: 16),
                    label: const Text('清除本机配置'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'BearFuel ${AppConfig.versionName} · 提示词版本 ${AiAuditService.promptVersion}',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
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
