import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../domain/fuel_price_service.dart';
import 'fuel_price_api_config.dart';

bool _validFuelPrice(double? value) =>
    value != null && value.isFinite && value > 0;

class ApiZeroFuelPriceSnapshot {
  final String province;
  final ProvinceFuelPrice price;
  final DateTime fetchedAt;
  final String sourceUrl;

  const ApiZeroFuelPriceSnapshot({
    required this.province,
    required this.price,
    required this.fetchedAt,
    required this.sourceUrl,
  });

  Map<String, dynamic> toJson() => {
        'province': province,
        'gas92': price.gas92,
        'gas95': price.gas95,
        'gas98': price.gas98,
        'diesel0': price.diesel0,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
        'priceDate': price.lastChangeDate.toIso8601String(),
        'sourceUrl': sourceUrl,
      };

  static ApiZeroFuelPriceSnapshot? fromJson(Map<String, dynamic> json) {
    final province = json['province'];
    final sourceUrl = json['sourceUrl'];
    final fetchedAt = json['fetchedAt'];
    if (province is! String || sourceUrl is! String || fetchedAt is! num) {
      return null;
    }

    double? number(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value');
    final gas92 = number(json['gas92']);
    final gas95 = number(json['gas95']);
    final gas98 = number(json['gas98']);
    final diesel0 = number(json['diesel0']);
    if (!_validFuelPrice(gas92) ||
        !_validFuelPrice(gas95) ||
        !_validFuelPrice(gas98) ||
        !_validFuelPrice(diesel0)) {
      return null;
    }
    final priceDate = DateTime.tryParse('${json['priceDate'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(fetchedAt.toInt());

    return ApiZeroFuelPriceSnapshot(
      province: province,
      price: ProvinceFuelPrice(
        province: province,
        gas92: gas92!,
        gas95: gas95!,
        gas98: gas98!,
        diesel0: diesel0!,
        lastChangeAmount: 0,
        lastChangeDate: priceDate,
      ),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt.toInt()),
      sourceUrl: sourceUrl,
    );
  }
}

class ApiZeroConnectionTestResult {
  final bool success;
  final String message;

  const ApiZeroConnectionTestResult({
    required this.success,
    required this.message,
  });
}

class ApiZeroFuelPriceService {
  static const Duration minimumRequestInterval = Duration(minutes: 30);
  static const Duration minimumManualRequestInterval = Duration(minutes: 1);
  static const Duration maximumCacheAge = Duration(days: 7);
  static String? _lastErrorMessage;

  static String? get lastErrorMessage => _lastErrorMessage;

  static Future<ApiZeroConnectionTestResult> testConnection({
    String province = '北京',
    String? apiKey,
  }) async {
    _lastErrorMessage = null;
    final snapshot = await _fetch(province, apiKey: apiKey);
    if (snapshot != null) {
      return const ApiZeroConnectionTestResult(
        success: true,
        message: 'ApiZero 连接成功，已读取测试省份在线油价',
      );
    }
    return ApiZeroConnectionTestResult(
      success: false,
      message: _lastErrorMessage ?? 'ApiZero 未返回有效油价数据',
    );
  }

  static String _cacheKey(String province) =>
      'apizero_oil_price_${Uri.encodeComponent(FuelPriceApiConfigStore.priceEndpoint)}_${Uri.encodeComponent(province)}';

  static String _attemptKey(String province) =>
      '${_cacheKey(province)}_last_attempt';

  static String _manualAttemptKey(String province) =>
      '${_cacheKey(province)}_last_manual_attempt';

  static String sourceUrlForProvince(String province) {
    return FuelPriceApiConfigStore.priceEndpoint;
  }

  static Future<ApiZeroFuelPriceSnapshot?> getCachedOrFetch(
    String province, {
    bool force = false,
  }) async {
    try {
      _lastErrorMessage = null;
      final cached = await _readCache(province);
      final usableCached = _isFresh(cached) ? cached : null;
      final prefs = await SharedPreferences.getInstance();
      final attemptKey =
          force ? _manualAttemptKey(province) : _attemptKey(province);
      final minimumInterval =
          force ? minimumManualRequestInterval : minimumRequestInterval;
      final lastAttemptMillis = prefs.getInt(attemptKey);
      if (lastAttemptMillis != null) {
        final elapsed = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(lastAttemptMillis),
        );
        if (!elapsed.isNegative && elapsed < minimumInterval) {
          if (usableCached == null) {
            _lastErrorMessage = cached == null
                ? (force ? '最近一次手动请求仍在 1 分钟限制内' : '最近一次自动请求仍在 30 分钟限制内，请点击手动更新')
                : '本地油价缓存已过期，请稍后重试';
          }
          return usableCached;
        }
      }

      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_attemptKey(province), nowMillis);
      if (force) await prefs.setInt(_manualAttemptKey(province), nowMillis);

      final fetched = await _fetch(province);
      if (fetched == null) return usableCached;
      await prefs.setString(_cacheKey(province), jsonEncode(fetched.toJson()));
      return fetched;
    } catch (e) {
      _lastErrorMessage = '请求或缓存异常：$e';
      return null;
    }
  }

  static Future<ApiZeroFuelPriceSnapshot?> _readCache(String province) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(province));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? ApiZeroFuelPriceSnapshot.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<ApiZeroFuelPriceSnapshot?> _fetch(
    String province, {
    String? apiKey,
  }) async {
    HttpClient? client;
    try {
      final endpoint = Uri.parse(FuelPriceApiConfigStore.priceEndpoint).replace(
        queryParameters: {
          'action': 'price',
          'province': province,
        },
      );
      await FuelPriceApiConfigStore.waitForRequestSlot();
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(endpoint);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader,
          'BearFuel/${AppConfig.versionName} (personal use)');

      final effectiveKey = apiKey ?? FuelPriceApiConfigStore.apiKey;
      if (effectiveKey.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $effectiveKey');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        _lastErrorMessage = response.statusCode == HttpStatus.tooManyRequests
            ? 'ApiZero 请求过于频繁（HTTP 429），请稍后重试或配置个人 Key'
            : 'HTTP 状态码 ${response.statusCode}';
        return null;
      }
      return _parseResponse(
          province, await response.transform(utf8.decoder).join());
    } catch (e) {
      _lastErrorMessage = '网络或 JSON 解析异常：$e';
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static ApiZeroFuelPriceSnapshot? _parseResponse(
      String province, String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      _lastErrorMessage = '接口返回的 JSON 结构无效';
      return null;
    }
    if (_asInt(decoded['code']) != 0) {
      _lastErrorMessage =
          '业务码 ${decoded['code'] ?? '--'}：${decoded['msg'] ?? '未知错误'}';
      return null;
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      _lastErrorMessage = '接口成功但缺少 data 数据';
      return null;
    }
    final prices = data['prices'];
    if (prices is! Map<String, dynamic> && prices is! List) {
      _lastErrorMessage = '接口成功但缺少 data.prices 数据';
      return null;
    }

    double? numberFor(List<String> keys) {
      if (prices is Map<String, dynamic>) {
        for (final key in keys) {
          final parsed = _parsePrice(prices[key]);
          if (parsed != null) return parsed;
        }
      } else if (prices is List) {
        for (final raw in prices) {
          if (raw is! Map) continue;
          final type = '${raw['type'] ?? ''}';
          final name = '${raw['name'] ?? ''}';
          if (keys.contains(type) || keys.contains(name)) {
            final parsed = _parsePrice(raw['price']);
            if (parsed != null) return parsed;
          }
        }
      }
      return null;
    }

    final gas92 = numberFor(['92', '92号汽油', 'gas92', 'gasoline_92', 'p92']);
    final gas95 = numberFor(['95', '95号汽油', 'gas95', 'gasoline_95', 'p95']);
    final gas98 = numberFor(['98', '98号汽油', 'gas98', 'gasoline_98', 'p98']);
    final diesel0 =
        numberFor(['0', '0号柴油', '柴油0', 'diesel0', 'diesel_0', 'p0', '0#']);
    if (!_validFuelPrice(gas92) ||
        !_validFuelPrice(gas95) ||
        !_validFuelPrice(gas98) ||
        !_validFuelPrice(diesel0)) {
      _lastErrorMessage = '接口成功但 data.prices 缺少 92/95/98/0 完整字段';
      return null;
    }

    final normalizedProvince = FuelPriceService.cityToProvince(province);
    final priceDate = DateTime.tryParse(
          '${data['update_date'] ?? data['update_time'] ?? data['time'] ?? decoded['time'] ?? ''}',
        ) ??
        DateTime.now();
    return ApiZeroFuelPriceSnapshot(
      province: normalizedProvince,
      price: ProvinceFuelPrice(
        province: normalizedProvince,
        gas92: gas92!,
        gas95: gas95!,
        gas98: gas98!,
        diesel0: diesel0!,
        lastChangeAmount: 0,
        lastChangeDate: priceDate,
      ),
      fetchedAt: DateTime.now(),
      sourceUrl: sourceUrlForProvince(normalizedProvince),
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }

  static double? _parsePrice(dynamic value) {
    if (value is num) return value.toDouble();
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch('$value');
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  static bool _isFresh(ApiZeroFuelPriceSnapshot? snapshot) {
    if (snapshot == null) return false;
    final age = DateTime.now().difference(snapshot.fetchedAt);
    return !age.isNegative && age <= maximumCacheAge;
  }
}
