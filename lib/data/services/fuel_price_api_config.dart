import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ApiZero 统一油价服务的本机 Key 配置。
/// 接口地址和认证方式固定，避免普通使用者误配请求协议。
class FuelPriceApiConfigStore {
  /// 当前省级油价接口：只负责 92/95/98/0 号油价。
  static const String priceEndpoint = 'https://v1.apizero.cn/api/oil-price';

  /// 调价预测接口：负责国际原油、预测和调价日历。
  static const String forecastEndpoint =
      'https://v1.apizero.cn/api/oil-price-forecast';
  static const String _storageKey = 'fuel_price_api_key';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static String? _apiKey;
  static Future<void> _requestTail = Future<void>.value();
  static DateTime? _lastRequestAt;

  static String get apiKey => _apiKey ?? '';
  static bool get hasApiKey => _apiKey?.isNotEmpty == true;

  /// ApiZero 匿名方案有 QPS 限制，所有油价动作共用一个请求节奏。
  static Future<void> waitForRequestSlot() {
    final previous = _requestTail;
    final next = previous.then((_) async {
      final last = _lastRequestAt;
      if (last != null) {
        final wait =
            const Duration(milliseconds: 1100) -
            DateTime.now().difference(last);
        if (!wait.isNegative && wait > Duration.zero) {
          await Future<void>.delayed(wait);
        }
      }
      _lastRequestAt = DateTime.now();
    });
    _requestTail = next;
    return next;
  }

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

/// 油价数据源选择：ApiZero 接口（默认，92/95/98/0 齐全）或
/// 小熊油耗网页（无需 Key，仅 92/95/0，可完全独立支撑运行）。
/// 两种模式下小熊油耗网页始终作为校准与备用源。
class FuelPriceSourceStore {
  static const String apizero = 'apizero';
  static const String xxyh = 'xxyh';
  static const String _key = 'fuel_price_source';

  static String _source = apizero;

  static String get source => _source;
  static bool get useXxyh => _source == xxyh;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == xxyh) {
        _source = xxyh;
      } else if (saved == apizero) {
        _source = apizero;
      }
    } catch (_) {
      _source = apizero;
    }
  }

  static Future<void> save(String value) async {
    _source = value == xxyh ? xxyh : apizero;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _source);
    } catch (_) {}
  }
}
