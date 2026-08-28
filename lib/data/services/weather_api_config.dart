import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ApiZero 墨迹天气服务的本机 Key 配置。Key 可选，未配置时使用匿名额度。
class WeatherApiConfigStore {
  static const String endpoint = 'https://v1.apizero.cn/api/moji-weather';
  static const String _storageKey = 'weather_api_key';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static String? _apiKey;

  static String get apiKey => _apiKey ?? '';
  static bool get hasApiKey => _apiKey?.isNotEmpty == true;

  static Future<void> load() async {
    try {
      _apiKey = await _storage.read(key: _storageKey);
    } catch (_) {
      _apiKey = null;
    }
  }

  static Future<void> save(String value) async {
    final key = value.trim();
    if (key.isEmpty) {
      await _storage.delete(key: _storageKey);
      _apiKey = '';
      return;
    }
    await _storage.write(key: _storageKey, value: key);
    _apiKey = key;
  }
}
