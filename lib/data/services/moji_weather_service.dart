import 'dart:convert';
import 'dart:io';

import '../models/weather_snapshot_model.dart';
import 'weather_api_config.dart';

class MojiWeatherCity {
  final String id;
  final String name;
  final String? province;

  const MojiWeatherCity({
    required this.id,
    required this.name,
    this.province,
  });
}

class MojiWeatherTestResult {
  final bool success;
  final String message;

  const MojiWeatherTestResult({
    required this.success,
    required this.message,
  });
}

class MojiWeatherService {
  static String? _lastErrorMessage;

  static String? get lastErrorMessage => _lastErrorMessage;

  static Future<MojiWeatherTestResult> testConnection({
    String? apiKey,
    String city = '北京',
  }) async {
    _lastErrorMessage = null;
    final cities = await searchCities(city, apiKey: apiKey);
    if (cities == null || cities.isEmpty) {
      return MojiWeatherTestResult(
        success: false,
        message: _lastErrorMessage ?? '未找到测试城市',
      );
    }
    final snapshot = await fetchCurrent(
      cityId: cities.first.id,
      apiKey: apiKey,
    );
    return MojiWeatherTestResult(
      success: snapshot != null,
      message: snapshot == null
          ? (_lastErrorMessage ?? '墨迹天气未返回有效数据')
          : '墨迹天气连接成功，已读取${cities.first.name}实时天气',
    );
  }

  static Future<List<MojiWeatherCity>?> searchCities(
    String keyword, {
    String? apiKey,
  }) async {
    final data = await _request({
      'op': 'search',
      'keyword': keyword,
      'limit': '10',
    }, apiKey: apiKey);
    if (data == null) return null;
    final rawCities = data['cities'];
    if (rawCities is! List) return <MojiWeatherCity>[];
    return rawCities
        .whereType<Map>()
        .map((raw) {
          return MojiWeatherCity(
            id: '${raw['id'] ?? raw['city_id'] ?? ''}',
            name: '${raw['name'] ?? ''}',
            province: raw['parent'] as String?,
          );
        })
        .where((city) => city.id.isNotEmpty && city.name.isNotEmpty)
        .toList();
  }

  static Future<WeatherSnapshotModel?> fetchCurrent({
    String? city,
    String? cityId,
    String? apiKey,
  }) async {
    final query = <String, String>{};
    if (cityId != null && cityId.isNotEmpty) {
      query['id'] = cityId;
    } else if (city != null && city.trim().isNotEmpty) {
      query['city'] = city.trim();
    } else {
      _lastErrorMessage = '缺少天气查询城市';
      return null;
    }

    final data = await _request(query, apiKey: apiKey);
    if (data == null) return null;
    final cityData = data['city'];
    final condition = data['condition'];
    if (cityData is! Map || condition is! Map) {
      _lastErrorMessage = '接口成功但缺少实况天气字段';
      return null;
    }
    final temperature = _number(condition['temperature']);
    if (temperature == null) {
      _lastErrorMessage = '接口成功但缺少实时温度';
      return null;
    }
    final forecastDay = data['forecast_day'];
    final today = forecastDay is List && forecastDay.isNotEmpty
        ? forecastDay.first
        : null;
    final now = DateTime.now();
    return WeatherSnapshotModel(
      cityKey: '${cityData['id'] ?? cityId ?? city ?? ''}',
      cityName: '${cityData['name'] ?? city ?? '当前位置'}',
      province: cityData['parent'] as String?,
      snapshotDate: DateTime(now.year, now.month, now.day),
      temperature: temperature,
      tempHigh: today is Map ? _number(today['temp_day']) : null,
      tempLow: today is Map ? _number(today['temp_night']) : null,
      condition: condition['condition'] as String?,
      aqi: _int((data['aqi'] as Map?)?['value']),
      source: 'apizero-moji-weather',
      fetchedAt: now,
    );
  }

  static Future<List<WeatherSnapshotModel>?> fetchHistoryMonth({
    required String month,
    String? city,
    String? cityId,
    String? apiKey,
  }) async {
    final query = <String, String>{
      'op': 'history',
      'month': month,
    };
    if (cityId != null && cityId.isNotEmpty) {
      query['id'] = cityId;
    } else if (city != null && city.trim().isNotEmpty) {
      query['city'] = city.trim();
    } else {
      _lastErrorMessage = '缺少历史天气查询城市';
      return null;
    }

    final data = await _request(query, apiKey: apiKey);
    if (data == null) return null;
    final cityData = data['city'];
    final items = data['items'];
    if (cityData is! Map || items is! List) {
      _lastErrorMessage = '接口成功但缺少历史天气列表';
      return null;
    }
    final fetchedAt = DateTime.now();
    return items
        .whereType<Map>()
        .map((raw) {
          final date = DateTime.tryParse('${raw['date'] ?? ''}');
          if (date == null) return null;
          return WeatherSnapshotModel(
            cityKey: '${cityData['id'] ?? cityId ?? city ?? ''}',
            cityName: '${cityData['name'] ?? city ?? '未知城市'}',
            province: cityData['parent'] as String?,
            snapshotDate: date,
            tempHigh: _number(raw['temp_high']),
            tempLow: _number(raw['temp_low']),
            condition: raw['condition'] as String?,
            aqi: _int(raw['aqi_value']),
            source: 'apizero-moji-weather',
            fetchedAt: fetchedAt,
          );
        })
        .whereType<WeatherSnapshotModel>()
        .toList();
  }

  static Future<Map<String, dynamic>?> _request(
    Map<String, String> query, {
    String? apiKey,
  }) async {
    HttpClient? client;
    try {
      final endpoint = Uri.parse(WeatherApiConfigStore.endpoint);
      final uri = endpoint.replace(queryParameters: query);
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers
          .set(HttpHeaders.userAgentHeader, 'BearFuel/0.2.5 (personal use)');
      final effectiveKey = apiKey ?? WeatherApiConfigStore.apiKey;
      if (effectiveKey.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $effectiveKey');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        _lastErrorMessage = '接口返回的 JSON 结构无效';
        return null;
      }
      final code = int.tryParse('${decoded['code']}');
      if (response.statusCode != HttpStatus.ok || code != 0) {
        _lastErrorMessage =
            '业务码 ${decoded['code'] ?? response.statusCode}：${decoded['msg'] ?? '请求失败'}';
        return null;
      }
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        _lastErrorMessage = '接口成功但缺少 data 数据';
        return null;
      }
      return data;
    } catch (e) {
      _lastErrorMessage = '网络或 JSON 解析异常：$e';
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }
}
