import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/services/ai_audit_config_store.dart';
import '../../../data/services/ai_audit_service.dart';
import '../../widgets/custom_card.dart';

/// AI 账本审查服务设置（OpenAI 兼容接口）
///
/// 支持保存多个模型，发起 AI 审查时再从中选用一个。
class AiAuditSettingsScreen extends StatefulWidget {
  const AiAuditSettingsScreen({super.key});

  @override
  State<AiAuditSettingsScreen> createState() => _AiAuditSettingsScreenState();
}

class _AiAuditSettingsScreenState extends State<AiAuditSettingsScreen> {
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _serviceNameController;

  bool _obscureKey = true;
  bool _isTesting = false;
  bool _isLoadingModels = false;
  String? _testResult;
  bool _testOk = false;
  List<String> _models = [];
  String _activeModel = '';

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: AiAuditConfigStore.baseUrl,
    );
    _apiKeyController = TextEditingController(text: AiAuditConfigStore.apiKey);
    _serviceNameController = TextEditingController(
      text: AiAuditConfigStore.serviceName == '自定义服务'
          ? ''
          : AiAuditConfigStore.serviceName,
    );
    _models = List<String>.from(AiAuditConfigStore.models);
    _activeModel = AiAuditConfigStore.model;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _serviceNameController.dispose();
    super.dispose();
  }

  Future<void> _persistConnection() async {
    await AiAuditConfigStore.save(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      serviceName: _serviceNameController.text.trim(),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isNotEmpty && !baseUrl.startsWith('http')) {
      _showMessage('Base URL 需以 http(s):// 开头', Colors.red);
      return;
    }
    if (_models.isEmpty) {
      _showMessage('请至少添加一个模型（获取列表或手动添加）', Colors.orange);
      return;
    }
    await _persistConnection();
    await AiAuditConfigStore.saveModels(_models);
    if (_activeModel.isNotEmpty) {
      await AiAuditConfigStore.setActiveModel(_activeModel);
    }
    if (!mounted) return;
    _showMessage('AI 审查配置已保存到本机安全存储', Colors.green);
    setState(() {});
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    await _persistConnection();
    if (_activeModel.isEmpty) {
      _showMessage('请先添加并选择一个模型', Colors.orange);
      return;
    }
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final (ok, message) = await AiAuditService.testConnection(
      model: _activeModel,
    );
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
        content: const Text('将删除本机保存的 Base URL、API Key 与全部模型。清除后账本审查仍可使用本地规则。'),
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
    _serviceNameController.clear();
    if (!mounted) return;
    setState(() {
      _models = [];
      _activeModel = '';
      _testResult = null;
    });
    _showMessage('已清除本机 AI 配置', Colors.orange);
  }

  /// 从服务获取模型列表 → 多选面板
  Future<void> _fetchModels() async {
    if (_isLoadingModels) return;
    FocusScope.of(context).unfocus();
    await _persistConnection();

    setState(() => _isLoadingModels = true);
    List<String> fetched;
    try {
      fetched = await AiAuditService.fetchModels();
    } on AiServiceException catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingModels = false);
      _showMessage(e.message, Colors.orange);
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingModels = false);
      _showMessage('获取模型列表失败：$e', Colors.red);
      return;
    }
    if (!mounted) return;
    setState(() => _isLoadingModels = false);
    await _showMultiSelectSheet(fetched);
  }

  /// 多选面板：勾选要保存的模型（默认全选，可搜索）
  Future<void> _showMultiSelectSheet(List<String> fetched) async {
    final selected = {for (final m in fetched) m: true};
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final colors = Theme.of(sheetCtx).colorScheme;
        final queryController = TextEditingController();
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          expand: false,
          builder: (innerCtx, scrollController) {
            return StatefulBuilder(
              builder: (innerCtx, setSheetState) {
                final query = queryController.text.trim().toLowerCase();
                final visible = fetched
                    .where(
                      (m) => query.isEmpty || m.toLowerCase().contains(query),
                    )
                    .toList();
                final checkedCount = selected.values.where((v) => v).length;
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
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Text(
                              '选择要保存的模型（已选 $checkedCount）',
                              style: Theme.of(innerCtx).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(AppIcons.close, size: 18),
                              onPressed: () => Navigator.pop(sheetCtx),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: queryController,
                                onChanged: (_) => setSheetState(() {}),
                                decoration: const InputDecoration(
                                  hintText: '搜索模型',
                                  prefixIcon: Icon(AppIcons.search, size: 18),
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setSheetState(() {
                                final allChecked =
                                    visible.isNotEmpty &&
                                    visible.every((m) => selected[m] == true);
                                for (final m in visible) {
                                  selected[m] = !allChecked;
                                }
                              }),
                              child: const Text('全选/反选'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: visible.isEmpty
                            ? Center(
                                child: Text(
                                  '没有匹配的模型',
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: visible.length,
                                itemBuilder: (innerCtx, index) {
                                  final model = visible[index];
                                  final isChecked = selected[model] == true;
                                  return CheckboxListTile(
                                    dense: true,
                                    value: isChecked,
                                    title: Text(
                                      model,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    onChanged: (v) => setSheetState(
                                      () => selected[model] = v ?? false,
                                    ),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF5A24),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              final pickedModels = fetched
                                  .where((m) => selected[m] == true)
                                  .toList();
                              Navigator.pop(sheetCtx, pickedModels);
                            },
                            child: const Text('保存所选模型'),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (picked == null) return;
    // 合并：保留已保存的 + 新勾选的
    final merged = <String>[..._models];
    for (final m in picked) {
      if (!merged.contains(m)) merged.add(m);
    }
    await AiAuditConfigStore.saveModels(merged);
    if (!mounted) return;
    setState(() {
      _models = List<String>.from(AiAuditConfigStore.models);
      _activeModel = AiAuditConfigStore.model;
    });
    _showMessage('已保存 ${picked.length} 个模型', Colors.green);
  }

  /// 手动添加模型
  Future<void> _addManualModel() async {
    final controller = TextEditingController();
    final added = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('手动添加模型'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          inputFormatters: [AppInputFormatters.maxChars(80)],
          decoration: const InputDecoration(
            labelText: '模型名称',
            hintText: '如 gpt-4o-mini',
          ),
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (added == null || added.isEmpty) return;
    await AiAuditConfigStore.addModel(added);
    if (!mounted) return;
    setState(() {
      _models = List<String>.from(AiAuditConfigStore.models);
      _activeModel = AiAuditConfigStore.model;
    });
  }

  /// 删除模型
  Future<void> _removeModel(String model) async {
    await AiAuditConfigStore.removeModel(model);
    if (!mounted) return;
    setState(() {
      _models = List<String>.from(AiAuditConfigStore.models);
      _activeModel = AiAuditConfigStore.model;
    });
  }

  /// 切换激活模型
  Future<void> _activateModel(String model) async {
    await AiAuditConfigStore.setActiveModel(model);
    if (!mounted) return;
    setState(() => _activeModel = AiAuditConfigStore.model);
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
                  '将拼接为 {Base URL}/chat/completions 与 {Base URL}/models',
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
                      icon: const Icon(AppIcons.keyboard_arrow_down, size: 18),
                      tooltip: _obscureKey ? '显示 Key' : '隐藏 Key',
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
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
                        onPressed: _save,
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
          _buildModelManagerCard(colors),
          const SizedBox(height: 12),
          _buildPrivacyCard(colors),
        ],
      ),
    );
  }

  /// 模型管理卡片：多模型列表 + 获取/手动添加 + 激活切换 + 删除
  Widget _buildModelManagerCard(ColorScheme colors) {
    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                '模型管理',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              SizedBox(width: 6),
              _QuestionMarkTooltip(
                message: '可保存多个模型；发起 AI 审查时再选择使用哪一个。点名称左侧圆点设为默认。',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _models.isEmpty
                ? '尚未添加模型：从服务获取列表，或手动添加'
                : '当前使用: ${_activeModel.isEmpty ? "未设置" : _activeModel}',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          for (final model in _models)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _activateModel(model),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _activeModel == model
                            ? AppIcons.check_circle
                            : AppIcons.circle_outlined,
                        size: 18,
                        color: _activeModel == model
                            ? const Color(0xFFFF5A24)
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _activeModel == model
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      AppIcons.close,
                      size: 16,
                      color: Colors.red,
                    ),
                    tooltip: '移除模型',
                    onPressed: () => _removeModel(model),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoadingModels ? null : _fetchModels,
                  icon: _isLoadingModels
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppIcons.file_download_outlined, size: 16),
                  label: Text(_isLoadingModels ? '获取中…' : '获取模型列表'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addManualModel,
                  icon: const Icon(AppIcons.add, size: 16),
                  label: const Text('手动添加'),
                ),
              ),
            ],
          ),
        ],
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
              onPressed: _clear,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(AppIcons.delete_outline, size: 16),
              label: const Text('清除本机配置'),
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

/// "？" 说明气泡
class _QuestionMarkTooltip extends StatelessWidget {
  final String message;

  const _QuestionMarkTooltip({required this.message});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            width: 1,
          ),
        ),
        child: Text(
          '?',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
