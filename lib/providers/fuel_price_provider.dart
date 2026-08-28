import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/fuel_price_service.dart';
import '../core/utils/location_service.dart';
import '../data/services/apizero_fuel_price_service.dart';
import '../data/services/apizero_oil_forecast_service.dart';

/// 全局油价与常驻城市定位状态管理 Provider
class FuelPriceProvider extends ChangeNotifier {
  static const String _keyCity = 'fuel_price_selected_city';
  static const String _keyProvince = 'fuel_price_selected_province';

  String _currentCity = '北京';
  String _currentProvince = '北京';
  int _priceRequestId = 0;
  bool _isLocating = false;
  bool _isRefreshingPrice = false;
  String _statusText = '已就绪';
  String _priceStatusText = '尚未读取在线油价';
  final Map<String, ApiZeroFuelPriceSnapshot> _onlinePricesByProvince = {};
  ApiZeroOilForecastResponse? _oilForecastResponse;
  bool _isRefreshingForecast = false;
  String _forecastStatusText = '尚未读取在线调价预测';

  FuelPriceProvider() {
    _initFromStorage();
  }

  String get currentCity => _currentCity;
  String get currentProvince => _currentProvince;
  bool get isLocating => _isLocating;
  bool get isRefreshingPrice => _isRefreshingPrice;
  String get statusText => _statusText;
  String get priceStatusText => _priceStatusText;
  bool get isRefreshingForecast => _isRefreshingForecast;
  String get forecastStatusText => _forecastStatusText;
  List<ApiZeroAdjustmentScheduleItem> get adjustmentSchedule =>
      List.unmodifiable(_oilForecastResponse?.schedule ?? const []);

  bool get isPriceFromApi =>
      _onlinePricesByProvince.containsKey(_currentProvince);

  DateTime? get priceFetchedAt =>
      _onlinePricesByProvince[_currentProvince]?.fetchedAt;

  String? get priceSourceUrl =>
      _onlinePricesByProvince[_currentProvince]?.sourceUrl;

  /// 当前城市对应的最新指导油价
  ProvinceFuelPrice get currentPrice => priceForProvince(_currentProvince);

  ProvinceFuelPrice priceForProvince(String provinceOrCity) {
    final province = FuelPriceService.cityToProvince(provinceOrCity);
    return _onlinePricesByProvince[province]?.price ??
        FuelPriceService.getProvincePrice(province);
  }

  /// 下一轮发改委调价窗口期预测
  AdjustmentForecast get forecast =>
      _oilForecastResponse?.forecast?.toDomain() ??
      FuelPriceService.getAdjustmentForecast();

  /// 从持久化本地缓存加载用户常驻城市
  Future<void> _initFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCity = prefs.getString(_keyCity);
      final savedProvince = prefs.getString(_keyProvince);

      if (savedCity != null && savedCity.isNotEmpty) {
        _currentCity = savedCity;
        _currentProvince =
            savedProvince ?? FuelPriceService.cityToProvince(savedCity);
        notifyListeners();
        await _loadRemotePriceForCity(_currentCity);
      } else {
        // 若尚未保存过，自动触发一次静默 GPS 卫星定位
        await autoLocate(silent: true);
      }
    } catch (_) {
      // 定位和本地偏好都不可用时，保留默认城市，但不伪造油价。
    }
  }

  /// 用户手动切换/选择城市
  Future<void> updateCity(String cityName) async {
    final province = FuelPriceService.cityToProvince(cityName);
    _currentCity = cityName;
    _currentProvince = province;
    _oilForecastResponse = null;
    _forecastStatusText = '尚未读取在线调价预测';
    _statusText = '已切换至 $cityName ($province)';
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCity, cityName);
      await prefs.setString(_keyProvince, province);
    } catch (_) {}

    await _loadRemotePriceForCity(cityName);
  }

  /// 触发 GPS 卫星硬件定位与逆地理编码
  Future<bool> autoLocate({bool silent = false}) async {
    _isLocating = true;
    _statusText = '正在通过 GPS 卫星定位所在城市...';
    if (!silent) notifyListeners();

    try {
      final result = await LocationService.getCurrentLocation();
      if (result.isSuccess && result.location != null) {
        final loc = result.location!;
        final detectedCity = loc.cityName;
        final detectedProvince = FuelPriceService.cityToProvince(detectedCity);

        _currentCity = detectedCity;
        _currentProvince = detectedProvince;
        _oilForecastResponse = null;
        _forecastStatusText = '尚未读取在线调价预测';
        _statusText = loc.source == LocationSource.cachedLocation
            ? result.message
            : 'GPS 定位成功 ($detectedCity)';
        _isLocating = false;
        notifyListeners();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyCity, detectedCity);
        await prefs.setString(_keyProvince, detectedProvince);
        await _loadRemotePriceForCity(detectedCity);
        return true;
      } else {
        _statusText = result.message;
        _isLocating = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _statusText = '定位异常: $e';
      _isLocating = false;
      notifyListeners();
      return false;
    }
  }

  /// Manually refreshes only the currently selected city price.
  Future<void> refreshCurrentPrice() async {
    if (_isRefreshingPrice) return;
    _isRefreshingPrice = true;
    notifyListeners();
    try {
      await _loadRemotePriceForCity(_currentCity, force: true);
    } finally {
      _isRefreshingPrice = false;
      notifyListeners();
    }
  }

  Future<void> refreshAdjustmentData({bool force = false}) async {
    if (_isRefreshingForecast) return;
    _isRefreshingForecast = true;
    _forecastStatusText = '正在读取 ApiZero 调价预测和日历...';
    notifyListeners();
    try {
      final response = await ApiZeroOilForecastService.getCachedOrFetch(
        province: _currentProvince,
        year: DateTime.now().year,
        force: force,
      );
      if (response == null) {
        _forecastStatusText =
            '调价数据读取失败：${ApiZeroOilForecastService.lastErrorMessage ?? '未知原因'}';
        return;
      }
      _oilForecastResponse = response;
      if (response.forecast != null && response.schedule.isNotEmpty) {
        _forecastStatusText = '已读取调价预测和 ${response.schedule.length} 个调价日历记录';
      } else if (response.schedule.isNotEmpty) {
        _forecastStatusText = '已读取 ${response.schedule.length} 个调价日历记录，预测暂不可用';
      } else {
        _forecastStatusText = '已读取调价预测，历史调价日历暂不可用';
      }
    } finally {
      _isRefreshingForecast = false;
      notifyListeners();
    }
  }

  Future<void> _loadRemotePriceForCity(String cityName,
      {bool force = false}) async {
    final requestId = ++_priceRequestId;
    _priceStatusText = force ? '正在手动读取实时油价...' : '正在读取实时油价...';
    notifyListeners();

    final apiSnapshot = await ApiZeroFuelPriceService.getCachedOrFetch(
      _currentProvince,
      force: force,
    );
    if (requestId != _priceRequestId || _currentCity != cityName) return;

    if (apiSnapshot != null) {
      _onlinePricesByProvince[_currentProvince] = apiSnapshot;
      _priceStatusText = '已读取在线实时油价（自动 30 分钟内不重复请求）';
    } else {
      final reason = ApiZeroFuelPriceService.lastErrorMessage;
      _priceStatusText = 'ApiZero 实时油价查询失败：${reason ?? '未知原因'}；当前未显示本地示例数据';
    }
    await refreshAdjustmentData(force: force);
    notifyListeners();
  }
}
