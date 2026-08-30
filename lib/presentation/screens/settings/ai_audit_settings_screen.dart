import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/services/ai_audit_config_store.dart';
import '../../../data/services/ai_audit_service.dart';
import '../../widgets/custom_card.dart';

/// AI 账本审查服务设置（多供应商，支持 OpenAI / Anthropic / Gemini 兼容接口）
///
/// 可保存多个供应商配置，每个供应商可保存多个模型；
/// 发起 AI 审查时使用激活供应商的激活模型（审查页可临时切换模型）。
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
  String _activeId = '';
  List<AiProviderProfile> _profiles = [];

  AiProviderProfile? get _active {
    for (final p in _profiles) {
      if (p.id == _activeId) return p;
    }
    return _profiles.isEmpty ? null : _profiles.first;
  }

  @override
  void initState() {
    super.initState();
    _activeId = AiAuditConfigStore.activeProfile?.id ?? '';
    _profiles = AiAuditConfigStore.profiles
        .map((p) => _copyProfile(p))
        .toList();
    final active = _active;
    _baseUrlController = TextEditingController(text: active?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: active?.apiKey ?? '');
    _serviceNameController = TextEditingController(text: active?.name ?? '');
  }

  AiProviderProfile _copyProfile(AiProviderProfile p) => AiProviderProfile(
    id: p.id,
    name: p.name,
    interfaceType: p.interfaceType,
    baseUrl: p.baseUrl,
    apiKey: p.apiKey,
    models: List<String>.from(p.models),
    activeModel: p.activeModel,
  );

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _serviceNameController.dispose();
    super.dispose();
  }

  Future<void> _persistConnection() async {
    final active = _active;
    if (active == null) return;
    active
      ..baseUrl = _baseUrlController.text.trim()
      ..apiKey = _apiKeyController.text.trim()
      ..name = _serviceNameController.text.trim();
    await AiAuditConfigStore.saveProfile(active);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isNotEmpty && !baseUrl.startsWith('http')) {
      _showMessage('Base URL 需以 http(s):// 开头', Colors.red);
      return;
    }
    final active = _active;
    if (active == null || active.models.isEmpty) {
      _showMessage('请至少添加一个模型（获取列表或手动添加）', Colors.orange);
      return;
    }
    await _persistConnection();
    await AiAuditConfigStore.saveProfile(active);
    if (!mounted) return;
    _showMessage('AI 审查配置已保存到本机安全存储', Colors.green);
    setState(() {});
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    await _persistConnection();
    final active = _active;
    if (active == null || active.activeModel.isEmpty) {
      _showMessage('请先添加并选择一个模型', Colors.orange);
      return;
    }
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final (ok, message) = await AiAuditService.testConnection(
      model: active.activeModel,
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
    _baseUrlController.clear();
    _apiKeyController.clear();
    _serviceNameController.clear();
    if (!mounted) return;
    setState(() {
      _profiles = [];
      _activeId = '';
      _testResult = null;
    });
    _showMessage('已清除全部 AI 配置', Colors.orange);
  }

  /// 切换激活供应商（字段同步为该供应商的配置）
  Future<void> _switchProfile(String id) async {
    if (id == _activeId) return;
    await _persistConnection(); // 保存当前编辑
    await AiAuditConfigStore.setActiveProfile(id);
    if (!mounted) return;
    final profile = AiAuditConfigStore.activeProfile;
    setState(() {
      _activeId = id;
      _profiles = AiAuditConfigStore.profiles.map(_copyProfile).toList();
      _baseUrlController.text = profile?.baseUrl ?? '';
      _apiKeyController.text = profile?.apiKey ?? '';
      _serviceNameController.text = (profile?.name ?? '') == '自定义服务'
          ? ''
          : (profile?.name ?? '');
      _testResult = null;
    });
  }

  /// 新增供应商
  Future<void> _addProfile() async {
    // 先保存当前编辑，避免丢失
    await _persistConnection();
    if (!mounted) return;
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
    await AiAuditConfigStore.setActiveProfile(created.id);
    if (!mounted) return;
    setState(() {
      _profiles = AiAuditConfigStore.profiles.map(_copyProfile).toList();
      _activeId = created.id;
      _baseUrlController.text = created.baseUrl;
      _apiKeyController.text = '';
      _serviceNameController.text = created.name;
      _testResult = null;
    });
  }

  /// 删除当前供应商
  Future<void> _deleteActiveProfile() async {
    final active = _active;
    if (active == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除供应商'),
        content: Text(
          '将删除「${active.name.isEmpty ? AiInterfaceType.label(active.interfaceType) : active.name}」的全部配置（含模型清单）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AiAuditConfigStore.deleteProfile(active.id);
    if (!mounted) return;
    setState(() {
      _profiles = AiAuditConfigStore.profiles.map(_copyProfile).toList();
      _activeId = AiAuditConfigStore.activeProfile?.id ?? '';
      final profile = _active;
      _baseUrlController.text = profile?.baseUrl ?? '';
      _apiKeyController.text = profile?.apiKey ?? '';
      _serviceNameController.text = ((profile?.name ?? '') == '自定义服务')
          ? ''
          : (profile?.name ?? '');
      _testResult = null;
    });
  }

  /// 获取模型列表 → 多选面板（写入当前供应商）
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

  Future<void> _showMultiSelectSheet(List<String> fetched) async {
    final profile = _active;
    final selected = {
      for (final m in fetched) m: (profile?.models.contains(m) ?? false),
    };
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
    final updatedProfile = _active;
    if (updatedProfile == null) return;
    updatedProfile
      ..models = picked
      ..activeModel = picked.contains(updatedProfile.activeModel)
          ? updatedProfile.activeModel
          : (picked.isNotEmpty ? picked.first : '');
    await AiAuditConfigStore.saveProfile(updatedProfile);
    if (!mounted) return;
    setState(() {
      _profiles = AiAuditConfigStore.profiles.map(_copyProfile).toList();
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
    final active = _active;
    if (active == null) return;
    active
      ..models = [...active.models, added]
      ..activeModel = active.activeModel.isEmpty ? added : active.activeModel;
    await AiAuditConfigStore.saveProfile(active);
    if (!mounted) return;
    setState(() {
      _profiles = AiAuditConfigStore.profiles.map(_copyProfile).toList();
    });
  }

  /// 删除模型
  Future<void> _removeModel(String model) async {
    final active = _active;
    if (active == null) return;
    active.models = active.models.where((m) => m != model).toList();
    if (active.activeModel == model) {
      active.activeModel = active.models.isEmpty ? '' : active.models.first;
    }
    await AiAuditConfigStore.saveProfile(active);
    if (!mounted) return;
    setState(() {
      _profiles = AiAuditConfigStore.profiles.map(_copyProfile).toList();
    });
  }

  /// 切换激活模型
  Future<void> _activateModel(String model) async {
    final active = _active;
    if (active == null) return;
    active.activeModel = model;
    await AiAuditConfigStore.saveProfile(active);
    if (!mounted) return;
    setState(() {
      _profiles = AiAuditConfigStore.profiles.map(_copyProfile).toList();
    });
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = _active;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 账本审查设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '支持保存多个 AI 供应商（OpenAI / Anthropic / Gemini 兼容接口），'
            '发起 AI 审查时使用激活供应商的激活模型。'
            'AI 结果仅用于辅助审查，原始账单不会被 AI 修改。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),

          // 供应商切换与管理
          CustomCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  AppIcons.branding_watermark_outlined,
                  size: 18,
                  color: Color(0xFF6558D3),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<String>(
                    value: _activeId.isEmpty ? null : _activeId,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    hint: const Text('选择供应商'),
                    items: [
                      for (final p in _profiles)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.name.isEmpty
                                ? AiInterfaceType.label(p.interfaceType)
                                : p.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) _switchProfile(id);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(AppIcons.add, size: 20),
                  tooltip: '新增供应商',
                  onPressed: _addProfile,
                ),
                if (_profiles.length > 1)
                  IconButton(
                    icon: const Icon(
                      AppIcons.delete_outline,
                      size: 18,
                      color: Colors.red,
                    ),
                    tooltip: '删除当前供应商',
                    onPressed: _deleteActiveProfile,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          if (active == null)
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
          else ...[
            // 连接配置
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
                      hintText: '如 DeepSeek / Claude / Gemini',
                      prefixIcon: Icon(AppIcons.branding_watermark_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: active.interfaceType,
                    decoration: const InputDecoration(
                      labelText: '接口类型 *',
                      prefixIcon: Icon(AppIcons.link),
                    ),
                    items: [
                      for (final type in AiInterfaceType.all)
                        DropdownMenuItem(
                          value: type,
                          child: Text(AiInterfaceType.label(type)),
                        ),
                    ],
                    onChanged: (type) {
                      if (type == null || type == active.interfaceType) return;
                      setState(() {
                        active.interfaceType = type;
                        // 切换接口类型时，若 Base URL 为空则填入官方默认
                        if (active.baseUrl.isEmpty) {
                          active.baseUrl = AiInterfaceType.defaultBaseUrl(type);
                          _baseUrlController.text = active.baseUrl;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _baseUrlController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Base URL *',
                      hintText:
                          AiInterfaceType.defaultBaseUrl(
                            active.interfaceType,
                          ).isEmpty
                          ? 'https://api.example.com/v1'
                          : AiInterfaceType.defaultBaseUrl(
                              active.interfaceType,
                            ),
                      prefixIcon: const Icon(AppIcons.link),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active.interfaceType == AiInterfaceType.anthropic
                        ? '请求将发送到 {Base URL}/v1/messages 与 /v1/models'
                        : active.interfaceType == AiInterfaceType.gemini
                        ? '请求将发送到 {Base URL}/v1beta/models/…'
                        : '请求将发送到 {Base URL}/chat/completions 与 /models',
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
                      hintText: active.interfaceType == AiInterfaceType.gemini
                          ? 'AIza...'
                          : 'sk-...',
                      prefixIcon: const Icon(AppIcons.gps_fixed),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          AppIcons.keyboard_arrow_down,
                          size: 18,
                        ),
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

            // 模型管理（多模型）
            CustomCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        '模型管理',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 6),
                      Tooltip(
                        message: '可保存多个模型；发起 AI 审查时再选择使用哪一个。点名称左侧圆点设为默认。',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Icon(
                          AppIcons.info_outline,
                          size: 15,
                          color: Color(0xFF8B9497),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active.models.isEmpty
                        ? '尚未添加模型：从服务获取列表，或手动添加'
                        : '当前使用: ${active.activeModel.isEmpty ? "未设置" : active.activeModel}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final model in active.models)
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
                                active.activeModel == model
                                    ? AppIcons.check_circle
                                    : AppIcons.circle_outlined,
                                size: 18,
                                color: active.activeModel == model
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
                                fontWeight: active.activeModel == model
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  AppIcons.file_download_outlined,
                                  size: 16,
                                ),
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
            ),
            const SizedBox(height: 12),
          ],

          _buildPrivacyCard(colors),
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
