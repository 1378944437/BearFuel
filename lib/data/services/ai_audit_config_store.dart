import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AI 接口兼容类型
class AiInterfaceType {
  static const String openai = 'openai'; // OpenAI 兼容 /chat/completions
  static const String openaiResponses =
      'openai_responses'; // OpenAI /responses（Responses API）
  static const String anthropic = 'anthropic'; // Anthropic /v1/messages
  static const String gemini = 'gemini'; // Google Gemini :generateContent

  static const List<String> all = [openai, openaiResponses, anthropic, gemini];

  static String label(String type) {
    switch (type) {
      case openaiResponses:
        return 'OpenAI Responses';
      case anthropic:
        return 'Anthropic 兼容';
      case gemini:
        return 'Gemini 兼容';
      default:
        return 'OpenAI 兼容';
    }
  }

  static String defaultBaseUrl(String type) {
    switch (type) {
      case anthropic:
        return 'https://api.anthropic.com';
      case gemini:
        return 'https://generativelanguage.googleapis.com';
      default:
        return '';
    }
  }

  const AiInterfaceType._();
}

/// 单个 AI 服务供应商配置
class AiProviderProfile {
  final String id;
  String name; // 服务名称（选填）
  String interfaceType; // AiInterfaceType
  String baseUrl;
  String apiKey;
  List<String> models; // 已保存模型清单
  String activeModel; // 当前使用的模型

  AiProviderProfile({
    required this.id,
    this.name = '',
    this.interfaceType = AiInterfaceType.openai,
    this.baseUrl = '',
    this.apiKey = '',
    this.models = const [],
    this.activeModel = '',
  });

  bool get isComplete =>
      baseUrl.isNotEmpty && apiKey.isNotEmpty && activeModel.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'interfaceType': interfaceType,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'models': models,
    'activeModel': activeModel,
  };

  factory AiProviderProfile.fromJson(
    Map<String, dynamic> json,
  ) => AiProviderProfile(
    id: json['id'] as String? ?? 'p_${DateTime.now().microsecondsSinceEpoch}',
    name: json['name'] is String ? json['name'] as String : '',
    interfaceType: json['interfaceType'] is String
        ? json['interfaceType'] as String
        : AiInterfaceType.openai,
    baseUrl: json['baseUrl'] is String ? json['baseUrl'] as String : '',
    apiKey: json['apiKey'] is String ? json['apiKey'] as String : '',
    models: json['models'] is List
        ? (json['models'] as List).whereType<String>().toList()
        : [],
    activeModel: json['activeModel'] is String
        ? json['activeModel'] as String
        : '',
  );
}

/// AI 账本审查服务配置（多供应商）。
///
/// 支持保存多个供应商配置，每个供应商可选接口兼容类型与多个模型；
/// 全局指定当前激活供应商，发起 AI 审查时使用其激活模型（可临时切换）。
/// Key 与模型清单均使用安全存储保存，不写入源码、备份 JSON 与普通日志。
class AiAuditConfigStore {
  static const String _keyProfiles = 'ai_audit_profiles';
  static const String _keyActiveId = 'ai_audit_active_id';
  // 旧版单一配置键（仅用于一次性迁移）
  static const String _legacyBaseUrl = 'ai_audit_base_url';
  static const String _legacyApiKey = 'ai_audit_api_key';
  static const String _legacyModel = 'ai_audit_model';
  static const String _legacyModels = 'ai_audit_models';
  static const String _legacyServiceName = 'ai_audit_service_name';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static List<AiProviderProfile> _profiles = [];
  static String _activeProfileId = '';

  static List<AiProviderProfile> get profiles => List.unmodifiable(_profiles);

  static AiProviderProfile? get activeProfile {
    for (final p in _profiles) {
      if (p.id == _activeProfileId) return p;
    }
    return _profiles.isEmpty ? null : _profiles.first;
  }

  static bool get hasProfiles => _profiles.isNotEmpty;

  static bool get isConfigured => activeProfile?.isComplete == true;

  // ---- 兼容旧代码的激活配置读取口 ----
  static String get baseUrl => activeProfile?.baseUrl ?? '';
  static String get apiKey => activeProfile?.apiKey ?? '';
  static String get model => activeProfile?.activeModel ?? '';
  static String get serviceName =>
      (activeProfile?.name ?? '').isEmpty ? '自定义服务' : activeProfile!.name;
  static List<String> get models => activeProfile?.models ?? const [];
  static bool get hasModel => (activeProfile?.activeModel ?? '').isNotEmpty;

  static Future<void> load() async {
    try {
      final raw = await _storage.read(key: _keyProfiles);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _profiles = decoded
              .whereType<Map>()
              .map(
                (item) =>
                    AiProviderProfile.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList();
        }
      }
      _activeProfileId = await _storage.read(key: _keyActiveId) ?? '';
      if (_profiles.isEmpty) {
        await _migrateLegacyConfig();
      }
      if (activeProfile == null && _profiles.isNotEmpty) {
        _activeProfileId = _profiles.first.id;
      }
    } catch (_) {
      _profiles = [];
      _activeProfileId = '';
    }
  }

  /// 旧版单一配置 → 单个 OpenAI 兼容供应商
  static Future<void> _migrateLegacyConfig() async {
    final baseUrl = await _storage.read(key: _legacyBaseUrl) ?? '';
    final apiKey = await _storage.read(key: _legacyApiKey) ?? '';
    final model = await _storage.read(key: _legacyModel) ?? '';
    final serviceName = await _storage.read(key: _legacyServiceName) ?? '';
    if (baseUrl.isEmpty && apiKey.isEmpty && model.isEmpty) return;

    final rawModels = await _storage.read(key: _legacyModels);
    List<String> models = [];
    try {
      if (rawModels != null && rawModels.isNotEmpty) {
        final decoded = jsonDecode(rawModels);
        if (decoded is List) {
          models = decoded.whereType<String>().toList();
        }
      }
    } catch (_) {}
    if (model.isNotEmpty && !models.contains(model)) {
      models.insert(0, model);
    }

    final profile = AiProviderProfile(
      id: 'p_${DateTime.now().microsecondsSinceEpoch}',
      name: serviceName,
      interfaceType: AiInterfaceType.openai,
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: models,
      activeModel: model,
    );
    _profiles = [profile];
    _activeProfileId = profile.id;
    await _persist();
  }

  static Future<void> _persist() async {
    await _storage.write(
      key: _keyProfiles,
      value: jsonEncode(_profiles.map((p) => p.toJson()).toList()),
    );
    await _storage.write(key: _keyActiveId, value: _activeProfileId);
  }

  /// 新增供应商并设为激活
  static Future<AiProviderProfile> addProfile({
    String name = '',
    String interfaceType = AiInterfaceType.openai,
  }) async {
    final profile = AiProviderProfile(
      id: 'p_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      interfaceType: interfaceType,
    );
    _profiles = [..._profiles, profile];
    _activeProfileId = profile.id;
    await _persist();
    return profile;
  }

  /// 保存（更新）供应商配置
  static Future<void> saveProfile(AiProviderProfile profile) async {
    _profiles = _profiles.map((p) => p.id == profile.id ? profile : p).toList();
    await _persist();
  }

  /// 删除供应商；删除激活供应商时顺延
  static Future<void> deleteProfile(String id) async {
    _profiles = _profiles.where((p) => p.id != id).toList();
    if (_activeProfileId == id) {
      _activeProfileId = _profiles.isEmpty ? '' : _profiles.first.id;
    }
    await _persist();
  }

  /// 切换激活供应商
  static Future<void> setActiveProfile(String id) async {
    _activeProfileId = id;
    await _persist();
  }

  /// 保存激活供应商的模型清单
  static Future<void> saveModels(List<String> models) async {
    final profile = activeProfile;
    if (profile == null) return;
    final cleaned = <String>[];
    for (final m in models) {
      final trimmed = m.trim();
      if (trimmed.isNotEmpty && !cleaned.contains(trimmed)) {
        cleaned.add(trimmed);
      }
    }
    profile.models = cleaned;
    if (profile.activeModel.isNotEmpty &&
        !cleaned.contains(profile.activeModel)) {
      profile.activeModel = cleaned.isEmpty ? '' : cleaned.first;
    }
    if (profile.activeModel.isEmpty && cleaned.isNotEmpty) {
      profile.activeModel = cleaned.first;
    }
    await _persist();
  }

  /// 添加模型到激活供应商
  static Future<void> addModel(String model) async {
    final profile = activeProfile;
    if (profile == null) return;
    final trimmed = model.trim();
    if (trimmed.isEmpty || profile.models.contains(trimmed)) return;
    profile.models = [...profile.models, trimmed];
    if (profile.activeModel.isEmpty) profile.activeModel = trimmed;
    await _persist();
  }

  /// 从激活供应商移除模型；移除激活模型时顺延
  static Future<void> removeModel(String model) async {
    final profile = activeProfile;
    if (profile == null) return;
    profile.models = profile.models.where((m) => m != model).toList();
    if (profile.activeModel == model) {
      profile.activeModel = profile.models.isEmpty ? '' : profile.models.first;
    }
    await _persist();
  }

  /// 设置激活供应商的激活模型
  static Future<void> setActiveModel(String model) async {
    final profile = activeProfile;
    if (profile == null) return;
    profile.activeModel = model.trim();
    await _persist();
  }

  static Future<void> clear() async {
    _profiles = [];
    _activeProfileId = '';
    await _storage.delete(key: _keyProfiles);
    await _storage.delete(key: _keyActiveId);
    // 同步清理旧版键
    await _storage.delete(key: _legacyBaseUrl);
    await _storage.delete(key: _legacyApiKey);
    await _storage.delete(key: _legacyModel);
    await _storage.delete(key: _legacyModels);
    await _storage.delete(key: _legacyServiceName);
  }
}
