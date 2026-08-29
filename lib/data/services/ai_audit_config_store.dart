import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AI 账本审查服务配置（OpenAI 兼容接口）。
///
/// Key 使用安全存储保存，不写入源码、备份 JSON 与普通日志。
class AiAuditConfigStore {
  static const String _keyBaseUrl = 'ai_audit_base_url';
  static const String _keyApiKey = 'ai_audit_api_key';
  static const String _keyModel = 'ai_audit_model';
  static const String _keyServiceName = 'ai_audit_service_name';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _baseUrl = '';
  static String _apiKey = '';
  static String _model = '';
  static String _serviceName = '';

  static String get baseUrl => _baseUrl;
  static String get apiKey => _apiKey;
  static String get model => _model;
  static String get serviceName =>
      _serviceName.isEmpty ? '自定义服务' : _serviceName;

  static bool get hasBaseUrl => _baseUrl.isNotEmpty;
  static bool get hasApiKey => _apiKey.isNotEmpty;
  static bool get hasModel => _model.isNotEmpty;

  /// 配置是否完整（三项均为发起 AI 审查的必要条件）
  static bool get isConfigured => hasBaseUrl && hasApiKey && hasModel;

  static Future<void> load() async {
    try {
      _baseUrl = await _storage.read(key: _keyBaseUrl) ?? '';
      _apiKey = await _storage.read(key: _keyApiKey) ?? '';
      _model = await _storage.read(key: _keyModel) ?? '';
      _serviceName = await _storage.read(key: _keyServiceName) ?? '';
    } catch (_) {
      _baseUrl = '';
      _apiKey = '';
      _model = '';
      _serviceName = '';
    }
  }

  /// 保存配置；传空字符串代表清除对应项
  static Future<void> save({
    required String baseUrl,
    required String apiKey,
    required String model,
    String? serviceName,
  }) async {
    _baseUrl = baseUrl.trim();
    _apiKey = apiKey.trim();
    _model = model.trim();
    _serviceName = (serviceName ?? '').trim();

    await _write(_keyBaseUrl, _baseUrl);
    await _write(_keyApiKey, _apiKey);
    await _write(_keyModel, _model);
    await _write(_keyServiceName, _serviceName);
  }

  static Future<void> clear() async {
    _baseUrl = '';
    _apiKey = '';
    _model = '';
    _serviceName = '';
    await _storage.delete(key: _keyBaseUrl);
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keyModel);
    await _storage.delete(key: _keyServiceName);
  }

  static Future<void> _write(String key, String value) async {
    if (value.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value);
  }
}
