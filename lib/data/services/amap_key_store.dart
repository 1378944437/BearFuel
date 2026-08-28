import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AmapKeyStore {
  static const String _storageKey = 'amap_web_service_key';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static String? _userKey;

  static String get currentKey => _userKey ?? '';

  static bool get hasUserKey => _userKey?.isNotEmpty == true;

  static Future<void> load() async {
    try {
      _userKey = await _storage.read(key: _storageKey);
    } catch (_) {
      _userKey = null;
    }
  }

  static Future<void> save(String value) async {
    final key = value.trim();
    if (key.isEmpty) {
      await _storage.delete(key: _storageKey);
      _userKey = '';
      return;
    }
    await _storage.write(key: _storageKey, value: key);
    _userKey = key;
  }
}
