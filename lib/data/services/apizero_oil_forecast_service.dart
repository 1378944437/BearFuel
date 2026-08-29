import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../domain/fuel_price_service.dart';
import 'fuel_price_api_config.dart';

int? _parseInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value');
}

double? _parseNumber(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

String? _cleanSummary(dynamic value) {
  if (value is! String) return null;
  final summary = value.replaceAll(r'\n', '\n').trim();
  return summary.isEmpty ? null : summary;
}

class ApiZeroOilForecast {
  final DateTime? nextAdjustmentDate;
  final int daysRemaining;
  final String direction;
  final double? estimatedChangePerTon;
  final double? estimatedChangePerLiter;
  final String? analysis;
  final double? wti;
  final double? brent;
  final double? wtiChange;
  final double? brentChange;

  const ApiZeroOilForecast({
    required this.nextAdjustmentDate,
    required this.daysRemaining,
    required this.direction,
    this.estimatedChangePerTon,
    this.estimatedChangePerLiter,
    this.analysis,
    this.wti,
    this.brent,
    this.wtiChange,
    this.brentChange,
  });

  AdjustmentForecast toDomain() {
    final date = nextAdjustmentDate;
    final delta = estimatedChangePerLiter ?? 0;
    final available = date != null && direction.isNotEmpty;
    return AdjustmentForecast(
      nextAdjustmentDate: date ?? DateTime(1970),
      daysRemaining: daysRemaining,
      forecastDelta: delta,
      isIncrease: direction.contains('上涨'),
      direction: direction,
      advice: analysis ?? '预测结果仅供参考，实际调价以官方公告为准',
      isAvailable: available,
    );
  }

  Map<String, dynamic> toJson() => {
    'nextAdjustmentDate': nextAdjustmentDate?.toIso8601String(),
    'daysRemaining': daysRemaining,
    'direction': direction,
    'estimatedChangePerTon': estimatedChangePerTon,
    'estimatedChangePerLiter': estimatedChangePerLiter,
    'analysis': analysis,
    'wti': wti,
    'brent': brent,
    'wtiChange': wtiChange,
    'brentChange': brentChange,
  };

  static ApiZeroOilForecast? fromJson(Map<String, dynamic> json) {
    final dateText = json['nextAdjustmentDate'];
    final direction = json['direction'];
    if (direction is! String || direction.isEmpty) return null;
    return ApiZeroOilForecast(
      nextAdjustmentDate: dateText is String
          ? DateTime.tryParse(dateText)
          : null,
      daysRemaining: _parseInt(json['daysRemaining']) ?? 0,
      direction: direction,
      estimatedChangePerTon: _parseNumber(json['estimatedChangePerTon']),
      estimatedChangePerLiter: _parseNumber(json['estimatedChangePerLiter']),
      analysis: json['analysis'] is String ? json['analysis'] as String : null,
      wti: _parseNumber(json['wti']),
      brent: _parseNumber(json['brent']),
      wtiChange: _parseNumber(json['wtiChange']),
      brentChange: _parseNumber(json['brentChange']),
    );
  }
}

class ApiZeroAdjustmentScheduleItem {
  final DateTime date;
  final String effective;
  final String status;
  final String? summary;
  final double? gasolineYuanPerTon;
  final double? dieselYuanPerTon;

  const ApiZeroAdjustmentScheduleItem({
    required this.date,
    required this.effective,
    required this.status,
    this.summary,
    this.gasolineYuanPerTon,
    this.dieselYuanPerTon,
  });

  bool get isPending => status == '待定';
  bool get isStagnant => status.contains('搁浅');

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'effective': effective,
    'status': status,
    'summary': summary,
    'gasolineYuanPerTon': gasolineYuanPerTon,
    'dieselYuanPerTon': dieselYuanPerTon,
  };

  static ApiZeroAdjustmentScheduleItem? fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse('${json['date'] ?? ''}');
    final status = json['status'];
    if (date == null || status is! String || status.isEmpty) return null;
    return ApiZeroAdjustmentScheduleItem(
      date: date,
      effective: '${json['effective'] ?? ''}',
      status: status,
      summary: _cleanSummary(json['summary']),
      gasolineYuanPerTon: _parseNumber(json['gasolineYuanPerTon']),
      dieselYuanPerTon: _parseNumber(json['dieselYuanPerTon']),
    );
  }
}

class ApiZeroOilForecastResponse {
  final ApiZeroOilForecast? forecast;
  final List<ApiZeroAdjustmentScheduleItem> schedule;
  final DateTime fetchedAt;

  const ApiZeroOilForecastResponse({
    required this.forecast,
    required this.schedule,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
    'forecast': forecast?.toJson(),
    'schedule': schedule.map((item) => item.toJson()).toList(),
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
  };

  static ApiZeroOilForecastResponse? fromJson(Map<String, dynamic> json) {
    final rawSchedule = json['schedule'];
    final fetchedAt = json['fetchedAt'];
    if (rawSchedule is! List || fetchedAt is! num) return null;
    final schedule = rawSchedule
        .whereType<Map>()
        .map(
          (item) => ApiZeroAdjustmentScheduleItem.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .whereType<ApiZeroAdjustmentScheduleItem>()
        .toList();
    final rawForecast = json['forecast'];
    return ApiZeroOilForecastResponse(
      forecast: rawForecast is Map
          ? ApiZeroOilForecast.fromJson(Map<String, dynamic>.from(rawForecast))
          : null,
      schedule: schedule,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt.toInt()),
    );
  }
}

class ApiZeroOilForecastService {
  static const Duration minimumRequestInterval = Duration(minutes: 30);
  static const Duration minimumManualRequestInterval = Duration(minutes: 1);
  static const Duration maximumCacheAge = Duration(days: 2);
  static String? _lastErrorMessage;

  static String? get lastErrorMessage => _lastErrorMessage;

  static String _cacheKey(String province, int year) =>
      'apizero_oil_forecast_${Uri.encodeComponent(province)}_$year';

  static Future<ApiZeroOilForecastResponse?> getCachedOrFetch({
    required String province,
    required int year,
    bool force = false,
  }) async {
    try {
      _lastErrorMessage = null;
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _cacheKey(province, year);
      final cached = _readCache(prefs.getString(cacheKey));
      final usableCached = _isFresh(cached) ? cached : null;
      final forecast = await _fetchAction(
        prefs: prefs,
        cacheKey: cacheKey,
        action: 'forecast',
        force: force,
        query: {'action': 'forecast', 'province': province},
      );
      final schedule = await _fetchAction(
        prefs: prefs,
        cacheKey: cacheKey,
        action: 'schedule',
        force: force,
        query: {'action': 'schedule', 'year': '$year'},
      );
      if (forecast == null && schedule == null) return usableCached;

      final parsedForecast = forecast == null ? null : _parseForecast(forecast);
      final parsedSchedule = schedule == null ? null : _parseSchedule(schedule);
      final response = ApiZeroOilForecastResponse(
        forecast: parsedForecast ?? usableCached?.forecast,
        schedule: parsedSchedule ?? (usableCached?.schedule ?? const []),
        fetchedAt: DateTime.now(),
      );
      await prefs.setString(cacheKey, jsonEncode(response.toJson()));
      return response;
    } catch (e) {
      _lastErrorMessage = '请求或缓存异常：$e';
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchAction({
    required SharedPreferences prefs,
    required String cacheKey,
    required String action,
    required bool force,
    required Map<String, String> query,
  }) async {
    final attemptKey = '$cacheKey:last_attempt_$action';
    final manualKey = '$cacheKey:last_manual_attempt_$action';
    final lastAttempt = prefs.getInt(force ? manualKey : attemptKey);
    final interval = force
        ? minimumManualRequestInterval
        : minimumRequestInterval;
    if (lastAttempt != null) {
      final elapsed = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(lastAttempt),
      );
      if (!elapsed.isNegative && elapsed < interval) return null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(attemptKey, now);
    if (force) await prefs.setInt(manualKey, now);
    return _request(query);
  }

  static Future<Map<String, dynamic>?> _request(
    Map<String, String> query,
  ) async {
    HttpClient? client;
    try {
      await FuelPriceApiConfigStore.waitForRequestSlot();
      final uri = Uri.parse(
        FuelPriceApiConfigStore.forecastEndpoint,
      ).replace(queryParameters: query);
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'BearFuel/${AppConfig.versionName} (personal use)',
      );
      final key = FuelPriceApiConfigStore.apiKey;
      if (key.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      // 响应体读取加超时，防止服务器中途停摆导致永久悬挂
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || response.statusCode != 200) {
        _lastErrorMessage = response.statusCode == HttpStatus.tooManyRequests
            ? 'ApiZero 请求过于频繁（HTTP 429），请稍后重试或配置个人 Key'
            : 'HTTP 状态码 ${response.statusCode}';
        return null;
      }
      if (_int(decoded['code']) != 0) {
        _lastErrorMessage =
            '业务码 ${decoded['code'] ?? '--'}：${decoded['msg'] ?? '请求失败'}';
        return null;
      }
      final data = decoded['data'];
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      _lastErrorMessage = '网络或 JSON 解析异常：$e';
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static ApiZeroOilForecast? _parseForecast(Map<String, dynamic> data) {
    final prediction = data['prediction'];
    if (prediction is! Map) return null;
    final crude = data['crude_oil'];
    return ApiZeroOilForecast(
      nextAdjustmentDate: DateTime.tryParse(
        '${data['next_adjust_date'] ?? ''}',
      ),
      daysRemaining: _int(data['days_remaining']) ?? 0,
      direction: '${prediction['direction'] ?? ''}',
      estimatedChangePerTon: _number(prediction['estimated_change_per_ton']),
      estimatedChangePerLiter: _number(
        prediction['estimated_change_per_liter'],
      ),
      analysis: prediction['analysis'] is String
          ? prediction['analysis'] as String
          : null,
      wti: crude is Map ? _number(crude['wti']) : null,
      brent: crude is Map ? _number(crude['brent']) : null,
      wtiChange: crude is Map ? _number(crude['wti_change']) : null,
      brentChange: crude is Map ? _number(crude['brent_change']) : null,
    );
  }

  static List<ApiZeroAdjustmentScheduleItem> _parseSchedule(
    Map<String, dynamic> data,
  ) {
    final raw = data['schedule'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) {
          final date = DateTime.tryParse('${item['date'] ?? ''}');
          if (date == null) return null;
          return ApiZeroAdjustmentScheduleItem(
            date: date,
            effective: '${item['effective'] ?? ''}',
            status: '${item['status'] ?? ''}',
            summary: _cleanSummary(item['summary']),
            gasolineYuanPerTon: _number(item['gasoline_yuan_per_ton']),
            dieselYuanPerTon: _number(item['diesel_yuan_per_ton']),
          );
        })
        .whereType<ApiZeroAdjustmentScheduleItem>()
        .toList();
  }

  static ApiZeroOilForecastResponse? _readCache(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? ApiZeroOilForecastResponse.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  static bool _isFresh(ApiZeroOilForecastResponse? response) {
    if (response == null) return false;
    final age = DateTime.now().difference(response.fetchedAt);
    return !age.isNegative && age <= maximumCacheAge;
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
