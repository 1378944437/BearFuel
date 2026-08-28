import 'package:flutter/foundation.dart';

import '../core/utils/historical_data_policy.dart';
import '../core/utils/location_service.dart';
import '../data/database/database_helper.dart';
import '../data/models/weather_snapshot_model.dart';
import '../data/services/moji_weather_service.dart';

class WeatherProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  WeatherSnapshotModel? _current;
  List<WeatherSnapshotModel> _snapshots = [];
  String _statusText = '尚未读取在线天气';
  bool _isRefreshing = false;
  bool _isResolvingLocation = false;
  String? _requestKey;
  DateTime? _lastFetchedAt;
  UserLocation? _actualLocation;
  DateTime? _lastLocationCheckedAt;
  static const _locationCheckInterval = Duration(minutes: 5);

  WeatherSnapshotModel? get current => _current;
  List<WeatherSnapshotModel> get snapshots => List.unmodifiable(_snapshots);
  HistoricalDataWindow get historyWindow => HistoricalDataWindow.fromDates(
        _snapshots.map((snapshot) => snapshot.snapshotDate),
      );
  String get statusText => _statusText;
  bool get isRefreshing => _isRefreshing;
  UserLocation? get actualLocation => _actualLocation;

  Future<void> refreshForLocation({
    required String city,
    Iterable<DateTime> referenceDates = const [],
    bool force = false,
  }) async {
    if (_isRefreshing) return;
    final trimmedCity = city.trim();
    if (trimmedCity.isEmpty) return;
    if (!force && trimmedCity == _requestKey && _lastFetchedAt != null) {
      final elapsed = DateTime.now().difference(_lastFetchedAt!);
      if (!elapsed.isNegative && elapsed < _locationCheckInterval) {
        return;
      }
    }

    _isRefreshing = true;
    if (_requestKey != trimmedCity) {
      _current = null;
      _snapshots = [];
    }
    _requestKey = trimmedCity;
    _statusText = '正在读取墨迹天气并保存历史快照...';
    notifyListeners();
    try {
      final cities = await MojiWeatherService.searchCities(trimmedCity);
      if (cities == null || cities.isEmpty) {
        _statusText =
            '天气查询失败：${MojiWeatherService.lastErrorMessage ?? '未找到城市'}';
        return;
      }

      final normalizedQuery = _normalizeCityName(trimmedCity);
      MojiWeatherCity? matchedCity;
      for (final candidate in cities) {
        if (_normalizeCityName(candidate.name) == normalizedQuery) {
          matchedCity = candidate;
          break;
        }
      }
      if (matchedCity == null) {
        _statusText = '天气查询失败：未找到与“$trimmedCity”精确匹配的城市';
        return;
      }
      final cityId = matchedCity.id;
      final cachedSnapshots = await _db.getWeatherSnapshots(cityKey: cityId);
      if (cachedSnapshots.isNotEmpty) {
        _snapshots = cachedSnapshots;
        _current = cachedSnapshots.last;
        notifyListeners();
      }
      final current = await MojiWeatherService.fetchCurrent(cityId: cityId);
      if (current == null) {
        _statusText = cachedSnapshots.isEmpty
            ? '天气查询失败：${MojiWeatherService.lastErrorMessage ?? '未返回实况数据'}'
            : '在线天气读取失败，当前显示本地 ${cachedSnapshots.length} 天快照';
        return;
      }
      _current = current;

      final now = DateTime.now();
      final monthKeys = HistoricalDataWindow.weatherMonthKeysToFetch(
        now: now,
        referenceDates: referenceDates,
        existingDates: _snapshots.map((snapshot) => snapshot.snapshotDate),
      );
      final fetchedSnapshots = <WeatherSnapshotModel>[];
      for (final month in monthKeys) {
        final history = await MojiWeatherService.fetchHistoryMonth(
          cityId: cityId,
          month: month,
        );
        if (history != null) fetchedSnapshots.addAll(history);
      }
      // The history endpoint may include today. Write current conditions last
      // so a same-day history row cannot overwrite the freshest observation.
      fetchedSnapshots.add(current);
      await _db.upsertWeatherSnapshots(fetchedSnapshots);
      _snapshots = await _db.getWeatherSnapshots(cityKey: cityId);
      _lastFetchedAt = DateTime.now();
      _statusText = '已读取墨迹天气，已保存 ${_snapshots.length} 天本地快照';
    } catch (e) {
      _statusText = '天气查询异常：$e';
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  static String _normalizeCityName(String value) {
    return value.trim().replaceFirst(RegExp(r'(自治区|自治州|地区|省|市)$'), '');
  }

  /// 先读取当前设备位置，再按定位城市查询天气。
  /// 保存的城市只作为定位失败时的回退，避免天气长期停留在旧城市。
  Future<void> refreshForActualLocation({
    required String fallbackCity,
    Iterable<DateTime> referenceDates = const [],
    bool force = false,
  }) async {
    final fallback = fallbackCity.trim();
    if (fallback.isEmpty || _isResolvingLocation || _isRefreshing) return;

    final lastChecked = _lastLocationCheckedAt;
    if (!force && lastChecked != null) {
      final elapsed = DateTime.now().difference(lastChecked);
      if (!elapsed.isNegative && elapsed < const Duration(minutes: 30)) {
        await refreshForLocation(
          city: _actualLocation?.cityName ?? fallback,
          referenceDates: referenceDates,
        );
        return;
      }
    }

    _isResolvingLocation = true;
    _statusText = '正在获取实际定位以更新天气...';
    notifyListeners();

    UserLocation? location;
    try {
      final result = await LocationService.getCurrentLocation();
      _lastLocationCheckedAt = DateTime.now();
      if (result.isSuccess && result.location != null) {
        final candidate = result.location!;
        // GPS 不可用时 LocationService 可能返回上次缓存，不能冒充实时定位。
        if (candidate.source != LocationSource.cachedLocation) {
          location = candidate;
          _actualLocation = candidate;
        }
      }
    } finally {
      _isResolvingLocation = false;
    }

    await refreshForLocation(
      city: location?.cityName ?? fallback,
      referenceDates: referenceDates,
      force: force,
    );
  }
}
