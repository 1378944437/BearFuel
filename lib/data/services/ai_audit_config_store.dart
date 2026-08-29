import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AI 账本审查服务配置（OpenAI 兼容接口）。
///
/// 支持保存多个模型，使用时从中选择一个；当前激活模型单独持久化。
/// Key 与模型清单均使用安全存储保存，不写入源码、备份 JSON 与普通日志。
class AiAuditConfigStore {
  static const String _keyBaseUrl = 'ai_audit_base_url';
  static const String _keyApiKey = 'ai_audit_api_key';
  static const String _keyModel = 'ai_audit_model'; // 当前激活模型
  static const String _keyModels = 'ai_audit_models'; // 模型清单（JSON 数组）
  static const String _keyServiceName = 'ai_audit_service_name';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _baseUrl = '';
  static String _apiKey = '';
  static String _model = ''; // 当前激活模型
  static List<String> _models = [];
  static String _serviceName = '';

  static String get baseUrl => _baseUrl;
  static String get apiKey => _apiKey;

  /// 当前激活模型（发起 AI 请求时使用）
  static String get model => _model;
  static String get serviceName =>
      _serviceName.isEmpty ? '自定义服务' : _serviceName;

  /// 已保存的模型清单（含激活模型）
  static List<String> get models => List.unmodifiable(_models);

  static bool get hasBaseUrl => _baseUrl.isNotEmpty;
  static bool get hasApiKey => _apiKey.isNotEmpty;

  /// 至少有一个可用模型
  static bool get hasModel => _model.isNotEmpty || _models.isNotEmpty;

  /// 配置是否完整（URL/Key/模型均为发起 AI 审查的必要条件）
  static bool get isConfigured => hasBaseUrl && hasApiKey && hasModel;

  static Future<void> load() async {
    try {
      _baseUrl = await _storage.read(key: _keyBaseUrl) ?? '';
      _apiKey = await _storage.read(key: _keyApiKey) ?? '';
      _model = await _storage.read(key: _keyModel) ?? '';
      _serviceName = await _storage.read(key: _keyServiceName) ?? '';
      final raw = await _storage.read(key: _keyModels);
      _models = _decodeModels(raw);
      // 兼容旧版单一模型配置
      if (_models.isEmpty && _model.isNotEmpty) {
        _models = [_model];
      }
    } catch (_) {
      _baseUrl = '';
      _apiKey = '';
      _model = '';
      _models = [];
      _serviceName = '';
    }
  }

  /// 保存连接配置；传空字符串代表清除对应项
  static Future<void> save({
    required String baseUrl,
    required String apiKey,
    String? serviceName,
  }) async {
    _baseUrl = baseUrl.trim();
    _apiKey = apiKey.trim();
    _serviceName = (serviceName ?? '').trim();

    await _write(_keyBaseUrl, _baseUrl);
    await _write(_keyApiKey, _apiKey);
    await _write(_keyServiceName, _serviceName);
  }

  /// 覆盖保存模型清单
  static Future<void> saveModels(List<String> models) async {
    final cleaned = <String>[];
    for (final m in models) {
      final trimmed = m.trim();
      if (trimmed.isNotEmpty && !cleaned.contains(trimmed)) {
        cleaned.add(trimmed);
      }
    }
    _models = cleaned;
    await _write(_keyModels, jsonEncode(cleaned));
    // 激活模型不在清单中时，回退到第一项
    if (_model.isNotEmpty && !cleaned.contains(_model)) {
      await setActiveModel(cleaned.isEmpty ? '' : cleaned.first);
    }
    if (_model.isEmpty && cleaned.isNotEmpty) {
      await setActiveModel(cleaned.first);
    }
  }

  /// 追加一个模型（已存在则忽略）
  static Future<void> addModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    if (_models.contains(trimmed)) return;
    _models = [..._models, trimmed];
    await _write(_keyModels, jsonEncode(_models));
    if (_model.isEmpty) {
      await setActiveModel(trimmed);
    }
  }

  /// 移除模型；若移除的是激活模型则顺延
  static Future<void> removeModel(String model) async {
    _models = _models.where((m) => m != model).toList();
    await _write(_keyModels, jsonEncode(_models));
    if (_model == model) {
      await setActiveModel(_models.isEmpty ? '' : _models.first);
    }
  }

  /// 设置当前激活模型（发起 AI 请求时使用的那个）
  static Future<void> setActiveModel(String model) async {
    _model = model.trim();
    await _write(_keyModel, _model);
  }

  static Future<void> clear() async {
    _baseUrl = '';
    _apiKey = '';
    _model = '';
    _models = [];
    _serviceName = '';
    await _storage.delete(key: _keyBaseUrl);
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keyModel);
    await _storage.delete(key: _keyModels);
    await _storage.delete(key: _keyServiceName);
  }

  static List<String> _decodeModels(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(String key, String value) async {
    if (value.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value);
  }
}
