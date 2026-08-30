import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/input_formatters.dart';
import '../../../data/services/ai_audit_config_store.dart';
import '../../../data/services/ai_audit_service.dart';
import '../../widgets/ai_model_picker_sheet.dart';
import '../../widgets/custom_card.dart';

/// AI 供应商编辑页（第二层：连接配置与模型管理）。
///
/// 可编辑任意供应商（无论是否激活）：修改名称、接口类型、Base URL、API Key，
/// 管理该供应商的模型清单与默认模型；测试连接与模型列表都针对本供应商生效。
class AiProviderEditScreen extends StatefulWidget {
  final String profileId;

  const AiProviderEditScreen({super.key, required this.profileId});

  @override
  State<AiProviderEditScreen> createState() => _AiProviderEditScreenState();
}

class _AiProviderEditScreenState extends State<AiProviderEditScreen> {
  late AiProviderProfile _profile;
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _serviceNameController;

  bool _obscureKey = true;
  bool _isTesting = false;
  bool _isLoadingModels = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final stored = AiAuditConfigStore.profiles
        .where((p) => p.id == widget.profileId)
        .toList();
    _profile = stored.isNotEmpty
        ? AiProviderProfile.fromJson(stored.first.toJson())
        : AiProviderProfile(id: widget.profileId);
    _baseUrlController = TextEditingController(text: _profile.baseUrl);
    _apiKeyController = TextEditingController(text: _profile.apiKey);
    _serviceNameController = TextEditingController(text: _profile.name);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _serviceNameController.dispose();
    super.dispose();
  }

  Future<void> _persistConnection() async {
    _profile
      ..baseUrl = _baseUrlController.text.trim()
      ..apiKey = _apiKeyController.text.trim()
      ..name = _serviceNameController.text.trim();
    await AiAuditConfigStore.saveProfile(_profile);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isNotEmpty && !baseUrl.startsWith('http')) {
      _showMessage('Base URL 需以 http(s):// 开头', Colors.red);
      return;
    }
    await _persistConnection();
    if (!mounted) return;
    _showMessage('配置已保存到本机安全存储', Colors.green);
    setState(() {});
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    await _persistConnection();
    if (_profile.activeModel.isEmpty) {
      _showMessage('请先添加并选择一个模型', Colors.orange);
      return;
    }
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final (ok, message) = await AiAuditService.testConnection(
      model: _profile.activeModel,
      profile: _profile,
    );
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testOk = ok;
      _testResult = message;
    });
  }

  Future<void> _deleteProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除供应商'),
        content: Text(
          '将删除「${_profile.name.isEmpty ? AiInterfaceType.label(_profile.interfaceType) : _profile.name}」'
          '的全部配置（含模型清单）。',
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
    await AiAuditConfigStore.deleteProfile(_profile.id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _changeInterfaceType(String type) async {
    if (type == _profile.interfaceType) return;
    setState(() {
      _profile.interfaceType = type;
      // 切换接口类型时，若 Base URL 为空则填入官方默认
      if (_profile.baseUrl.isEmpty) {
        _profile.baseUrl = AiInterfaceType.defaultBaseUrl(type);
        _baseUrlController.text = _profile.baseUrl;
      }
    });
    await _persistConnection();
  }

  /// 获取模型列表 → 多选面板（写入当前供应商）
  Future<void> _fetchModels() async {
    if (_isLoadingModels) return;
    FocusScope.of(context).unfocus();
    await _persistConnection();

    setState(() => _isLoadingModels = true);
    List<String> fetched;
    try {
      fetched = await AiAuditService.fetchModels(profile: _profile);
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
    final picked = await showAiModelPickerSheet(
      context,
      fetched: fetched,
      initiallySelected: _profile.models.toSet(),
    );
    if (picked == null) return;
    _profile
      ..models = picked
      ..activeModel = picked.contains(_profile.activeModel)
          ? _profile.activeModel
          : (picked.isNotEmpty ? picked.first : '');
    await AiAuditConfigStore.saveProfile(_profile);
    if (!mounted) return;
    setState(() {});
    _showMessage('已保存 ${picked.length} 个模型', Colors.green);
  }

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
    _profile
      ..models = [..._profile.models.where((m) => m != added), added]
      ..activeModel = _profile.activeModel.isEmpty
          ? added
          : _profile.activeModel;
    await AiAuditConfigStore.saveProfile(_profile);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _removeModel(String model) async {
    _profile.models = _profile.models.where((m) => m != model).toList();
    if (_profile.activeModel == model) {
      _profile.activeModel = _profile.models.isEmpty
          ? ''
          : _profile.models.first;
    }
    await AiAuditConfigStore.saveProfile(_profile);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _activateModel(String model) async {
    _profile.activeModel = model;
    await AiAuditConfigStore.saveProfile(_profile);
    if (!mounted) return;
    setState(() {});
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const accent = Color(0xFFFF5A24);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _profile.name.isEmpty
              ? AiInterfaceType.label(_profile.interfaceType)
              : _profile.name,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '修改后请点击“保存配置”；测试连接与获取模型列表均针对当前编辑的供应商。'
            '发起 AI 审查时需要在上一页把该供应商设为使用中。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),

          // 连接配置
          CustomCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '连接配置',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
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
                  initialValue: _profile.interfaceType,
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
                    if (type != null) _changeInterfaceType(type);
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
                          _profile.interfaceType,
                        ).isEmpty
                        ? 'https://api.example.com/v1'
                        : AiInterfaceType.defaultBaseUrl(
                            _profile.interfaceType,
                          ),
                    prefixIcon: const Icon(AppIcons.link),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _endpointHint,
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
                    hintText: _profile.interfaceType == AiInterfaceType.gemini
                        ? 'AIza...'
                        : 'sk-...',
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
                          backgroundColor: accent,
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

          // 模型管理
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
                  _profile.models.isEmpty
                      ? '尚未添加模型：从服务获取列表，或手动添加'
                      : '当前默认: ${_profile.activeModel.isEmpty ? "未设置" : _profile.activeModel}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                for (final model in _profile.models)
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
                              _profile.activeModel == model
                                  ? AppIcons.check_circle
                                  : AppIcons.circle_outlined,
                              size: 18,
                              color: _profile.activeModel == model
                                  ? accent
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
                              fontWeight: _profile.activeModel == model
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

          // 危险操作
          CustomCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deleteProfile,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(AppIcons.delete_outline, size: 16),
                label: const Text('删除该供应商'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _endpointHint {
    switch (_profile.interfaceType) {
      case AiInterfaceType.anthropic:
        return '请求将发送到 {Base URL}/v1/messages 与 /v1/models';
      case AiInterfaceType.gemini:
        return '请求将发送到 {Base URL}/v1beta/models/…';
      case AiInterfaceType.openaiResponses:
        return '请求将发送到 {Base URL}/responses 与 /models';
      default:
        return '请求将发送到 {Base URL}/chat/completions 与 /models';
    }
  }
}
