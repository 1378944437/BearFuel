import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';

/// 小熊油耗 fprice 网页油价快照（备用与校准源）。
///
/// 网站为服务端渲染静态页面，仅提供 92#/95#/0#柴油 三个标号，
/// 没有 98# 数据；调价日期为 MM-DD，年份按抓取时间就近推算。
class XxyhPriceSnapshot {
  final String province;
  final double gas92;
  final double gas95;
  final double diesel0;
  final DateTime? lastChangeDate;
  final DateTime? nextAdjustDate;
  final DateTime fetchedAt;
  final String sourceUrl;

  const XxyhPriceSnapshot({
    required this.province,
    required this.gas92,
    required this.gas95,
    required this.diesel0,
    this.lastChangeDate,
    this.nextAdjustDate,
    required this.fetchedAt,
    required this.sourceUrl,
  });

  Map<String, dynamic> toJson() => {
    'province': province,
    'gas92': gas92,
    'gas95': gas95,
    'diesel0': diesel0,
    'lastChangeDate': lastChangeDate?.toIso8601String(),
    'nextAdjustDate': nextAdjustDate?.toIso8601String(),
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    'sourceUrl': sourceUrl,
  };

  static XxyhPriceSnapshot? fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v');
    final province = json['province'];
    final gas92 = asDouble(json['gas92']);
    final gas95 = asDouble(json['gas95']);
    final diesel0 = asDouble(json['diesel0']);
    final fetchedAt = json['fetchedAt'];
    if (province is! String ||
        gas92 == null ||
        gas95 == null ||
        diesel0 == null ||
        fetchedAt is! num) {
      return null;
    }
    return XxyhPriceSnapshot(
      province: province,
      gas92: gas92,
      gas95: gas95,
      diesel0: diesel0,
      lastChangeDate: DateTime.tryParse('${json['lastChangeDate'] ?? ''}'),
      nextAdjustDate: DateTime.tryParse('${json['nextAdjustDate'] ?? ''}'),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt.toInt()),
      sourceUrl: '${json['sourceUrl'] ?? ''}',
    );
  }
}

/// 小熊油耗油价网页抓取服务。
///
/// 定位：ApiZero 接口的备用与校准数据源。
/// - 校准：接口油价与网页数据不一致时，以网页数据为准（92/95/0）。
/// - 备用：接口失败时兜底（98 号只能沿用接口历史缓存）。
/// 网站对通用爬虫 robots 全站 Disallow，因此保持低频礼貌抓取：
/// 自动请求 6 小时节流、手动 10 分钟、缓存 3 天，只抓当前省份单页。
class XxyhFuelPriceService {
  static const String provinceEndpoint =
      'https://www.xiaoxiongyouhao.com/fprice/proilprice.php';
  static const Duration minimumRequestInterval = Duration(hours: 6);
  static const Duration minimumManualRequestInterval = Duration(minutes: 10);
  static const Duration maximumCacheAge = Duration(days: 3);
  static String? _lastErrorMessage;

  static String? get lastErrorMessage => _lastErrorMessage;

  static String _cacheKey(String province) =>
      'xxyh_oil_price_${Uri.encodeComponent(province)}';

  static String _attemptKey(String province) =>
      '${_cacheKey(province)}_last_attempt';

  static String _manualAttemptKey(String province) =>
      '${_cacheKey(province)}_last_manual_attempt';

  /// 读取缓存或低频抓取当前省份数据；失败时静默返回可用缓存或 null。
  static Future<XxyhPriceSnapshot?> getCachedOrFetch(
    String province, {
    bool force = false,
  }) async {
    try {
      _lastErrorMessage = null;
      final prefs = await SharedPreferences.getInstance();
      final cached = _readCache(prefs.getString(_cacheKey(province)));
      final usableCached = _isFresh(cached) ? cached : null;
      final attemptKey = force
          ? _manualAttemptKey(province)
          : _attemptKey(province);
      final minimumInterval = force
          ? minimumManualRequestInterval
          : minimumRequestInterval;
      final lastAttempt = prefs.getInt(attemptKey);
      if (lastAttempt != null) {
        final elapsed = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(lastAttempt),
        );
        if (!elapsed.isNegative && elapsed < minimumInterval) {
          return usableCached;
        }
      }

      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_attemptKey(province), nowMillis);
      if (force) await prefs.setInt(_manualAttemptKey(province), nowMillis);

      final fetched = await _fetchPage(province);
      if (fetched == null) return usableCached;
      final parsed = parseProvincePage(province, fetched);
      if (parsed == null) {
        _lastErrorMessage = '小熊油耗页面解析失败（结构可能已变化）';
        return usableCached;
      }
      await prefs.setString(_cacheKey(province), jsonEncode(parsed.toJson()));
      return parsed;
    } catch (e) {
      _lastErrorMessage = '小熊油耗抓取异常：$e';
      return null;
    }
  }

  /// 与 App 省份口径对齐：'广东省'→'广东'，'北京市'→'北京'，
  /// '新疆维吾尔自治区'→'新疆' 等。
  static String normalizeRegionName(String name) {
    var n = name.trim();
    n = n.replaceAll(RegExp(r'维吾尔|壮族|回族'), '');
    n = n.replaceFirst(RegExp(r'(自治区|特别行政区|省|市)$'), '');
    return n;
  }

  /// 解析省份页 HTML：price-table 首行为省级 92/95/0，
  /// 头部含"上次调价：MM-DD / 下次调价：MM-DD"。
  static XxyhPriceSnapshot? parseProvincePage(
    String province,
    String htmlBody,
  ) {
    final doc = html_parser.parse(htmlBody);
    final rows = doc.querySelectorAll('table.price-table tbody tr');
    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 4) continue;
      final regionRaw = cells.first.text.trim();
      if (normalizeRegionName(regionRaw) != normalizeRegionName(province)) {
        continue;
      }
      final gas92 = _parsePrice(cells[1].text);
      final gas95 = _parsePrice(cells[2].text);
      final diesel0 = _parsePrice(cells[3].text);
      if (gas92 == null || gas95 == null || diesel0 == null) return null;

      final lastChange = _extractAdjustDate(htmlBody, '上次调价');
      final nextAdjust = _extractAdjustDate(htmlBody, '下次调价');
      return XxyhPriceSnapshot(
        province: normalizeRegionName(province),
        gas92: gas92,
        gas95: gas95,
        diesel0: diesel0,
        lastChangeDate: lastChange,
        nextAdjustDate: nextAdjust,
        fetchedAt: DateTime.now(),
        sourceUrl: provinceEndpoint,
      );
    }
    return null;
  }

  static double? _parsePrice(String text) {
    final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(text.trim());
    if (match == null) return null;
    final value = double.tryParse(match.group(0)!);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// '上次调价：<b>08-29</b>' → 当年日期；跨年时按就近原则修正年份。
  static DateTime? _extractAdjustDate(String htmlBody, String label) {
    final index = htmlBody.indexOf(label);
    if (index < 0) return null;
    final match = RegExp(
      r'(\d{2})-(\d{2})',
    ).firstMatch(htmlBody.substring(index, index + 60));
    if (match == null) return null;
    final now = DateTime.now();
    var date = DateTime(
      now.year,
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
    // 页面只给 MM-DD：上次调价不可能晚于今天 15 天以上（应为去年），
    // 下次调价不可能早于今天 15 天以上（应为明年）。
    if (label == '上次调价' && date.isAfter(now.add(const Duration(days: 15)))) {
      date = DateTime(now.year - 1, date.month, date.day);
    }
    if (label == '下次调价' &&
        date.isBefore(now.subtract(const Duration(days: 15)))) {
      date = DateTime(now.year + 1, date.month, date.day);
    }
    return date;
  }

  static Future<String?> _fetchPage(String province) async {
    HttpClient? client;
    try {
      final uri = Uri.parse(
        provinceEndpoint,
      ).replace(queryParameters: {'province': province});
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'text/html');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'BearFuel/${AppConfig.versionName} (personal use)',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        _lastErrorMessage = '小熊油耗页面返回 HTTP ${response.statusCode}';
        return null;
      }
      return body;
    } catch (e) {
      _lastErrorMessage = '小熊油耗网络异常：$e';
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static XxyhPriceSnapshot? _readCache(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? XxyhPriceSnapshot.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  static bool _isFresh(XxyhPriceSnapshot? snapshot) {
    if (snapshot == null) return false;
    final age = DateTime.now().difference(snapshot.fetchedAt);
    return !age.isNegative && age <= maximumCacheAge;
  }
}
