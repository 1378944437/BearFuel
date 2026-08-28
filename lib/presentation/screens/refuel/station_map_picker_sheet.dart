import 'package:bearfuel/core/theme/app_icons.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../../providers/fuel_price_provider.dart';
import '../../../data/services/amap_location_service.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/map_coordinate_utils.dart';
import '../../widgets/city_picker_sheet.dart';
import '../settings/amap_key_settings_screen.dart';

/// 加油站详细信息模型（包含真实 GPS 经纬度、实时指导油价看板、优惠政策与营业时间）
class GasStationInfo {
  final String name; // 加油站全称
  final String brand; // 所属品牌 (中国石化、中国石油、壳牌等)
  final String address; // 详细地址
  final double distanceKm; // 距离当前位置 (km)
  final double latitude; // 纬度坐标
  final double longitude; // 经度坐标
  final List<String> availableFuels; // 支持油品
  final String? discountInfo; // 优惠信息 (如: 95#直降0.3元)
  final Map<String, double> fuelPrices; // 实时各标号指导/特惠油价
  final String businessHours; // 营业时间
  final List<String> services; // 服务设施
  final String? phone; // 电话

  const GasStationInfo({
    required this.name,
    required this.brand,
    required this.address,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
    required this.availableFuels,
    this.discountInfo,
    this.fuelPrices = const {},
    this.businessHours = '暂无营业时间数据',
    this.services = const [],
    this.phone,
  });

  /// 根据当前 GPS 坐标生成新距离的实例
  GasStationInfo copyWithDistance(double newDistanceKm) {
    return GasStationInfo(
      name: name,
      brand: brand,
      address: address,
      distanceKm: newDistanceKm,
      latitude: latitude,
      longitude: longitude,
      availableFuels: availableFuels,
      discountInfo: discountInfo,
      fuelPrices: fuelPrices,
      businessHours: businessHours,
      services: services,
      phone: phone,
    );
  }
}

/// 智能加油站地图选点组件（支持真实硬件 GPS 卫星定位与全国地市自适应测距）
class StationMapPickerSheet extends StatefulWidget {
  final String? initialStationName;
  final String? initialCity;

  const StationMapPickerSheet({
    super.key,
    this.initialStationName,
    this.initialCity,
  });

  static Future<String?> show(
    BuildContext context, {
    String? initialStationName,
    String? initialCity,
  }) async {
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return null;

    String? defaultCity = initialCity;
    try {
      defaultCity ??= context.read<FuelPriceProvider>().currentCity;
    } catch (_) {}

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StationMapPickerSheet(
        initialStationName: initialStationName,
        initialCity: defaultCity,
      ),
    );
  }

  @override
  State<StationMapPickerSheet> createState() => _StationMapPickerSheetState();
}

class _StationMapPickerSheetState extends State<StationMapPickerSheet> {
  late TextEditingController _searchController;

  late String _currentCity;
  String _selectedBrand = '全部';
  String _selectedDistanceRange = '不限';
  UserLocation? _currentGpsLocation;
  bool _isLocating = false;
  String _gpsStatusText = '正在获取卫星 GPS 定位...';
  Offset _mapPanOffset = Offset.zero;
  bool _manualLocationOverride = false;
  int _locationRequestId = 0;
  List<GasStationInfo>? _onlineStations;
  String? _stationError;
  UserLocation? _lastOnlineQueryLocation;
  int _stationRequestId = 0;

  // 常用品牌分类
  final List<String> _brands = [
    '全部',
    '中国石化',
    '中国石油',
    '中国海油',
    '壳牌',
    '道达尔',
    '民营特惠'
  ];

  // 距离范围限定选项
  final List<String> _distanceRanges = [
    '不限',
    '500m',
    '1km',
    '2km',
    '3km',
    '5km'
  ];

  StreamSubscription<Position>? _positionStreamSub;
  bool _isFetchingStations = false;

  bool get _isDemoMode => !AmapLocationService.isConfigured;

  double get _mapCenterLatitude =>
      _currentGpsLocation?.latitude ??
      LocationService.cityAnchors[_currentCity]?[0] ??
      39.9042;

  double get _mapCenterLongitude =>
      _currentGpsLocation?.longitude ??
      LocationService.cityAnchors[_currentCity]?[1] ??
      116.4074;

  void _refreshStationsForCurrentLocation() {
    final location = _currentGpsLocation;
    if (location != null) {
      _refreshOnlineStations(location);
    }
  }

  Future<void> _openAmapKeySettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AmapKeySettingsScreen()),
    );
    if (!mounted) return;
    setState(() {
      _onlineStations = null;
      _lastOnlineQueryLocation = null;
    });
    if (AmapLocationService.isConfigured && _currentGpsLocation == null) {
      _triggerGpsLocation();
    } else {
      _refreshStationsForCurrentLocation();
    }
  }

  Future<void> _refreshOnlineStations(UserLocation location) async {
    if (!AmapLocationService.isConfigured) {
      if (mounted && (_onlineStations != null || _stationError != null)) {
        setState(() {
          _onlineStations = null;
          _stationError = null;
        });
      }
      return;
    }

    if (_isFetchingStations) return;

    final last = _lastOnlineQueryLocation;
    if (last != null &&
        _onlineStations != null &&
        LocationService.calculateDistanceKm(
              lat1: last.latitude,
              lon1: last.longitude,
              lat2: location.latitude,
              lon2: location.longitude,
            ) <
            0.2) {
      return;
    }

    final requestId = ++_stationRequestId;
    _isFetchingStations = true;
    if (mounted) {
      setState(() {
        _onlineStations = null;
        _stationError = null;
      });
    }

    try {
      final pois = await AmapLocationService.searchGasStations(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (!mounted || requestId != _stationRequestId) return;

      final stations =
          pois?.map(_toGasStationInfo).toList() ?? <GasStationInfo>[];
      setState(() {
        _onlineStations = stations.isEmpty ? null : stations;
        _stationError = pois == null
            ? '加油站查询失败，请检查高德 Key 或网络后重试'
            : stations.isEmpty
                ? '当前位置附近暂未查询到加油站，可扩大范围或调整地图中心'
                : null;
        // 请求失败时允许下一次手动定位/刷新重试，不锁死在失败坐标上。
        _lastOnlineQueryLocation =
            pois == null || stations.isEmpty ? null : location;
      });
    } catch (e) {
      if (mounted && requestId == _stationRequestId) {
        setState(() {
          _onlineStations = null;
          _stationError = '加油站查询异常，请稍后重试';
        });
      }
    } finally {
      // 取消、超时和页面切换都必须释放加载锁，否则后续刷新会被永久拦截。
      _isFetchingStations = false;
    }
  }

  GasStationInfo _toGasStationInfo(AmapPoi poi) {
    return GasStationInfo(
      name: poi.name,
      brand: poi.brand ?? '其他',
      address: poi.address,
      distanceKm: poi.distanceKm,
      latitude: poi.latitude,
      longitude: poi.longitude,
      availableFuels: const [],
      fuelPrices: const {},
      businessHours: '暂无营业时间数据',
      services: const ['加油服务'],
      phone: poi.phone,
    );
  }

  @override
  void initState() {
    super.initState();
    _currentCity = widget.initialCity ?? '北京';
    _gpsStatusText = _isDemoMode ? '未配置高德 Key，不加载真实站点数据' : '正在获取卫星 GPS 定位...';
    _searchController =
        TextEditingController(text: widget.initialStationName ?? '');
    if (!_isDemoMode) {
      _initQuickLocation();
      _startContinuousGpsTracking();
    }
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// 快速读取持久化缓存与最后已知位置，实现零延迟精准显示
  Future<void> _initQuickLocation() async {
    try {
      // 1. 优先读取用户在应用中最后确认/定位的片区与坐标
      final cached = await LocationService.getCachedLocation();
      if (cached != null && mounted && !_manualLocationOverride) {
        setState(() {
          _currentGpsLocation = cached;
          _currentCity = cached.cityName;
          _gpsStatusText = '已恢复位置 · ${cached.displayLocationName}';
        });
        _refreshStationsForCurrentLocation();
      }

      // 2. 次选读取硬件最后已知坐标
      if (_currentGpsLocation == null) {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null && mounted && !_manualLocationOverride) {
          final nearest = LocationService.findNearestTownship(
              lastPos.latitude, lastPos.longitude);
          final townName = nearest?.townName;
          final displayCity = nearest?.cityName ?? _currentCity;
          final distToUrban = LocationService.distanceToCityCenter(
            lastPos.latitude,
            lastPos.longitude,
            displayCity,
          );
          final distText = distToUrban > 0
              ? ' (距市中心 ${distToUrban.toStringAsFixed(1)}km)'
              : '';
          setState(() {
            _currentGpsLocation = UserLocation(
              latitude: lastPos.latitude,
              longitude: lastPos.longitude,
              accuracy: lastPos.accuracy,
              cityName: nearest?.cityName ?? _currentCity,
              district: nearest?.districtName,
              township: townName,
              fullAddress:
                  '当前位置 (${lastPos.latitude.toStringAsFixed(4)}, ${lastPos.longitude.toStringAsFixed(4)})',
              source: LocationSource.cachedLocation,
            );
            _gpsStatusText = '锁定已知位置 · ${townName ?? displayCity}$distText';
          });
        }
      }
    } catch (_) {
      if (mounted && !_manualLocationOverride && _currentGpsLocation == null) {
        setState(() {
          _isLocating = false;
          _gpsStatusText = '读取缓存定位失败，正在尝试重新定位';
        });
      }
    }
    if (mounted && !_manualLocationOverride) {
      _triggerGpsLocation();
    }
  }

  /// 启动底层硬件 GNSS/北斗卫星持续数据流监听（自动实时平滑校准）
  void _startContinuousGpsTracking() {
    try {
      final settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
        forceLocationManager: true, // 强制原生底层硬件北斗/GPS芯片
        intervalDuration: const Duration(milliseconds: 1000),
      );
      _positionStreamSub =
          Geolocator.getPositionStream(locationSettings: settings).listen(
        (Position pos) {
          if (!mounted) return;
          if (_manualLocationOverride || !LocationService.isUsablePosition(pos))
            return;
          final nearest =
              LocationService.findNearestTownship(pos.latitude, pos.longitude);
          final urbanDist = LocationService.distanceToCityCenter(
            pos.latitude,
            pos.longitude,
            nearest?.cityName ?? _currentCity,
          );
          final isRural = urbanDist > 12;
          final distStr =
              isRural ? ' · 距市中心 ${urbanDist.toStringAsFixed(1)}km' : '';

          final newLoc = UserLocation(
            latitude: pos.latitude,
            longitude: pos.longitude,
            accuracy: pos.accuracy,
            cityName: nearest?.cityName ?? _currentCity,
            district: nearest?.districtName ??
                (isRural
                    ? '距市中心 ${urbanDist.toStringAsFixed(1)}km'
                    : _currentGpsLocation?.district),
            township: nearest?.townName ?? _currentGpsLocation?.township,
            street: _currentGpsLocation?.street,
            fullAddress:
                '北斗卫星实时锁定 (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})',
            source: LocationSource.hardwareGnss,
          );

          LocationService.saveCachedLocation(newLoc);

          setState(() {
            _currentGpsLocation = newLoc;
            _currentCity = newLoc.cityName;
            _isLocating = false;
            _gpsStatusText =
                '北斗硬件锁定 (±${pos.accuracy.toStringAsFixed(0)}m$distStr)';
          });
          _refreshStationsForCurrentLocation();
        },
        onError: (error) {
          if (!mounted || _manualLocationOverride) return;
          setState(() {
            _isLocating = false;
            if (_currentGpsLocation == null) {
              _gpsStatusText = 'GPS 定位失败，请检查定位权限后重试';
            }
          });
        },
      );
    } catch (_) {
      if (mounted && !_manualLocationOverride) {
        setState(() {
          _isLocating = false;
          if (_currentGpsLocation == null) {
            _gpsStatusText = '无法启动 GPS 定位，请检查定位权限后重试';
          }
        });
      }
    }
  }

  /// 距离范围换算为千米
  double? get _distanceLimitKm {
    switch (_selectedDistanceRange) {
      case '500m':
        return 0.5;
      case '1km':
        return 1.0;
      case '2km':
        return 2.0;
      case '3km':
        return 3.0;
      case '5km':
        return 5.0;
      default:
        return null;
    }
  }

  /// 触发真实硬件 GPS 卫星定位与逆地理编码
  Future<void> _triggerGpsLocation() async {
    if (_isDemoMode) {
      await _openAmapKeySettings();
      return;
    }
    final requestId = ++_locationRequestId;
    setState(() {
      _manualLocationOverride = false;
      _isLocating = true;
      _gpsStatusText = '正在搜索北斗/GPS 卫星...';
    });

    try {
      // 地图选站只需要坐标和片区，跳过耗时的完整逆地理编码。
      final result = await LocationService.getCurrentLocation(
        resolveAddress: false,
      );
      if (!mounted) return;
      if (requestId != _locationRequestId || _manualLocationOverride) return;

      if (result.isSuccess && result.location != null) {
        final loc = result.location!;
        final urbanDist = LocationService.distanceToCityCenter(
          loc.latitude,
          loc.longitude,
          loc.cityName,
        );
        final distText =
            urbanDist > 12 ? ' (距市中心 ${urbanDist.toStringAsFixed(1)}km)' : '';
        LocationService.saveCachedLocation(loc);

        setState(() {
          _isLocating = false;
          _currentGpsLocation = loc;
          _currentCity = loc.cityName;
          _gpsStatusText = '北斗定位成功 · ${loc.displayLocationName}$distText';
        });
        _refreshStationsForCurrentLocation();
      } else {
        setState(() {
          _isLocating = false;
          if (_currentGpsLocation == null) {
            _gpsStatusText = result.message;
          }
        });
      }
    } catch (e) {
      if (mounted &&
          requestId == _locationRequestId &&
          !_manualLocationOverride) {
        setState(() {
          _isLocating = false;
          if (_currentGpsLocation == null) {
            _gpsStatusText = '定位提示: $e';
          }
        });
      }
    }
  }

  /// 获取经过 GPS 测距计算、品牌、距离范围与关键字筛选后的加油站列表
  List<GasStationInfo> get _filteredStations {
    final baseList = _onlineStations ?? const <GasStationInfo>[];

    final query = _searchController.text.trim().toLowerCase();
    final maxDist = _distanceLimitKm;

    return baseList.where((station) {
      // 品牌过滤
      final matchesBrand = _selectedBrand == '全部' ||
          station.brand == _selectedBrand ||
          (_selectedBrand == '民营特惠' &&
              !['中国石化', '中国石油', '中国海油', '壳牌', '道达尔'].contains(station.brand));

      // 距离范围限定过滤
      final matchesDistance = maxDist == null || station.distanceKm <= maxDist;

      // 搜索词过滤
      final matchesQuery = query.isEmpty ||
          station.name.toLowerCase().contains(query) ||
          station.address.toLowerCase().contains(query) ||
          station.brand.toLowerCase().contains(query) ||
          station.availableFuels.any((f) => f.toLowerCase().contains(query));

      return matchesBrand && matchesDistance && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final bgColor = colors.surface;
    final filtered = _filteredStations;

    return Material(
      color: bgColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.88,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 顶部标题栏与城市定位切换
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(AppIcons.near_me,
                              color: colors.primary, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('选择加油站',
                              style: Theme.of(context).textTheme.titleLarge),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(AppIcons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 4),
                      child: Row(
                        children: [
                          Expanded(child: _buildCitySelector(isDark)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTownshipButton(isDark)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_isDemoMode)
                _buildStationStatusBanner(
                  isDark: isDark,
                  icon: AppIcons.warning_amber_rounded,
                  foreground: isDark
                      ? const Color(0xFFFFB74D)
                      : const Color(0xFFD9410F),
                  message: '当前未配置高德 Key，不显示示例站点。请配置 Key 后查询真实加油站。',
                  actionLabel: '去配置',
                  onAction: _openAmapKeySettings,
                )
              else if (_isFetchingStations)
                _buildStationStatusBanner(
                  isDark: isDark,
                  icon: AppIcons.sync,
                  foreground: isDark
                      ? const Color(0xFF90CAF9)
                      : const Color(0xFF1565C0),
                  message: '正在加载当前位置附近的高德加油站…',
                )
              else if (_stationError != null)
                _buildStationStatusBanner(
                  isDark: isDark,
                  icon: AppIcons.info_outline,
                  foreground: isDark
                      ? const Color(0xFFFFB74D)
                      : const Color(0xFFD9410F),
                  message: _stationError!,
                  actionLabel: '重试',
                  onAction: () {
                    if (_currentGpsLocation != null) {
                      _refreshStationsForCurrentLocation();
                    } else {
                      _triggerGpsLocation();
                    }
                  },
                ),

              // 2. 模拟可拖动探索的交互式电子卫星地图视图
              _buildVisualMapView(isDark, filtered),

              // 2.1 快捷片区一键直达横向栏
              _buildQuickTownshipBar(isDark),

              // 3. 搜索栏（UI优化 + 结果计数）
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: 14, color: colors.onSurface),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '搜索站名、路段或品牌（如 象山大道、中石化、95#）',
                    prefixIcon: Icon(
                      AppIcons.search,
                      color: _searchController.text.isNotEmpty
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            tooltip: '清除搜索',
                            icon: const Icon(AppIcons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              child: Text(
                                '${filtered.length}站',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 4. 双排筛选标签：范围限定（500m、1km、2km...）与品牌选择
              SizedBox(
                height: 32,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _distanceRanges.length,
                  itemBuilder: (context, index) {
                    final dist = _distanceRanges[index];
                    final isSel = dist == _selectedDistanceRange;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.social_distance,
                              size: 12,
                              color: isSel
                                  ? Colors.white
                                  : const Color(0xFF1E88E5),
                            ),
                            const SizedBox(width: 4),
                            Text(dist, style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                        selected: isSel,
                        selectedColor: colors.secondary,
                        labelStyle: TextStyle(
                          color: isSel ? colors.onPrimary : colors.onSurface,
                          fontWeight:
                              isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (val) {
                          if (val)
                            setState(() => _selectedDistanceRange = dist);
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),

              // 品牌横向滚动标签
              SizedBox(
                height: 32,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _brands.length,
                  itemBuilder: (context, index) {
                    final brand = _brands[index];
                    final isSel = brand == _selectedBrand;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label:
                            Text(brand, style: const TextStyle(fontSize: 11)),
                        selected: isSel,
                        selectedColor: colors.primary,
                        labelStyle: TextStyle(
                          color: isSel ? colors.onPrimary : colors.onSurface,
                          fontWeight:
                              isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (val) {
                          if (val) setState(() => _selectedBrand = brand);
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 4),
              const Divider(height: 1),

              // 5. 附近加油站列表（深度展示实时油价、优惠政策与营业时间）
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(AppIcons.location_off_outlined,
                                size: 48, color: colors.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              '在$_currentCity ${_selectedDistanceRange != "不限" ? "$_selectedDistanceRange内" : ""}未找到符合条件的加油站',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () {
                                if (_searchController.text.isNotEmpty) {
                                  Navigator.pop(
                                      context, _searchController.text.trim());
                                }
                              },
                              child: const Text('使用输入的站名'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isNearest = index == 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isNearest
                                    ? colors.primary.withValues(alpha: 0.4)
                                    : colors.outlineVariant,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () =>
                                  _showStationDetailSheet(context, item),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: colors.onSurface),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '${item.distanceKm} km',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: colors.primary,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.discountInfo != null
                                                ? item.discountInfo!
                                                : '设施: ${item.services.take(2).join(" · ")}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: item.discountInfo != null
                                                  ? Colors.red[700]
                                                  : colors.onSurfaceVariant,
                                              fontWeight:
                                                  item.discountInfo != null
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            HapticFeedback.selectionClick();
                                            Navigator.pop(context, item.name);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: colors.primary,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 6),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6)),
                                          ),
                                          child: const Text('选此站',
                                              style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationStatusBanner({
    required bool isDark,
    required IconData icon,
    required Color foreground,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final background = isDark
        ? Color.alphaBlend(
            foreground.withValues(alpha: 0.14), const Color(0xFF1E1E1E))
        : foreground.withValues(alpha: 0.08);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: background,
        border:
            Border.all(color: foreground.withValues(alpha: 0.65), width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 12, color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: foreground,
                side: BorderSide(color: foreground),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  /// 仿天气 App 的城市切换弹窗入口
  Widget _buildCitySelector(bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        if (_isDemoMode) {
          await _openAmapKeySettings();
          return;
        }
        final selectedCity = await CityPickerSheet.show(
          context,
          currentCity: _currentCity,
          currentGpsLocation: _currentGpsLocation,
        );
        if (selectedCity != null && selectedCity.isNotEmpty && mounted) {
          _locationRequestId++;
          _stationRequestId++;
          final cityCoords = LocationService.cityAnchors[selectedCity];
          setState(() {
            _currentCity = selectedCity;
            _manualLocationOverride = true;
            _isLocating = false;
            _currentGpsLocation = cityCoords == null
                ? null
                : UserLocation(
                    latitude: cityCoords[0],
                    longitude: cityCoords[1],
                    cityName: selectedCity,
                    accuracy: null,
                    source: LocationSource.manualPinpoint,
                  );
            _mapPanOffset = Offset.zero;
            _onlineStations = null;
            _gpsStatusText = '已切换至 $selectedCity 地图中心';
          });
          _refreshStationsForCurrentLocation();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5A24).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: const Color(0xFFFF5A24).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.location_on,
                size: 14, color: Color(0xFFFF5A24)),
            const SizedBox(width: 2),
            Text(
              _currentCity,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFFF5A24),
                  fontWeight: FontWeight.bold),
            ),
            const Icon(AppIcons.arrow_drop_down,
                size: 16, color: Color(0xFFFF5A24)),
          ],
        ),
      ),
    );
  }

  /// 片区快捷直达横向栏 (一键快速切换柴胡、胡集、纪山、沙洋、团林等)
  Widget _buildQuickTownshipBar(bool isDark) {
    if (_isDemoMode) return const SizedBox.shrink();

    const quickTowns = [
      '柴胡镇',
      '胡集镇',
      '纪山镇',
      '沙洋镇',
      '团林铺镇',
      '石牌镇',
      '洋梓镇',
      '冷水镇',
      '后港镇',
      '漳河镇',
      '掇刀石街道',
      '象山/龙泉街道',
    ];

    return SizedBox(
      height: 30,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: quickTowns.length + 1,
        itemBuilder: (context, index) {
          final colors = Theme.of(context).colorScheme;
          if (index == quickTowns.length) {
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                avatar: const Icon(AppIcons.more_horiz,
                    size: 13, color: Color(0xFF1E88E5)),
                label: const Text('更多片区',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF1E88E5),
                        fontWeight: FontWeight.bold)),
                backgroundColor: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                side: BorderSide(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.3)),
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: () => _showTownshipPicker(context),
              ),
            );
          }

          final townFullName = quickTowns[index];
          final anchor = LocationService.townshipDatabase.firstWhere(
            (t) => t.townName == townFullName,
            orElse: () => LocationService.townshipDatabase.first,
          );

          final shortName = townFullName
              .replaceAll('镇', '')
              .replaceAll('街道', '')
              .replaceAll('铺', '')
              .replaceAll('/龙泉', '');

          final isSelected = _currentGpsLocation?.township == townFullName ||
              (_currentGpsLocation != null &&
                  LocationService.calculateDistanceKm(
                        lat1: _currentGpsLocation!.latitude,
                        lon1: _currentGpsLocation!.longitude,
                        lat2: anchor.latitude,
                        lon2: anchor.longitude,
                      ) <
                      3.0);

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              avatar: isSelected
                  ? const Icon(AppIcons.check, size: 11, color: Colors.white)
                  : null,
              label: Text(shortName, style: const TextStyle(fontSize: 10.5)),
              selected: isSelected,
              selectedColor: const Color(0xFF1E88E5),
              backgroundColor:
                  isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF3F4F6),
              labelStyle: TextStyle(
                color: isSelected ? colors.onPrimary : colors.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              onSelected: (_) => _selectTownship(anchor),
            ),
          );
        },
      ),
    );
  }

  /// 选中指定片区基准点并即时重算距离与持久化
  void _selectTownship(TownshipAnchor t) {
    HapticFeedback.selectionClick();
    _locationRequestId++;
    final distToUrban = LocationService.distanceToCityCenter(
      t.latitude,
      t.longitude,
      t.cityName,
    );
    final newLoc = UserLocation(
      latitude: t.latitude,
      longitude: t.longitude,
      accuracy: 5.0,
      cityName: t.cityName,
      district: t.districtName,
      township: t.townName,
      fullAddress: '${t.cityName} ${t.districtName} ${t.townName}',
      source: LocationSource.townshipAnchor,
    );
    LocationService.saveCachedLocation(newLoc);
    setState(() {
      _manualLocationOverride = true;
      _isLocating = false;
      _currentGpsLocation = newLoc;
      _currentCity = t.cityName;
      _mapPanOffset = Offset.zero;
      _gpsStatusText =
          '已定位至 ${t.townName} (距市中心 ${distToUrban.toStringAsFixed(1)}km)';
    });
    _refreshStationsForCurrentLocation();
  }

  /// 片区/街道/镇快速切换入口
  Widget _buildTownshipButton(bool isDark) {
    if (_isDemoMode) return const SizedBox.shrink();

    final currentTown = _currentGpsLocation?.township
            ?.replaceAll('镇', '')
            .replaceAll('乡', '')
            .replaceAll('街道', '') ??
        '选片区/镇';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showTownshipPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.location_city,
                size: 14, color: Color(0xFF1E88E5)),
            const SizedBox(width: 2),
            Text(
              currentTown,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1E88E5),
                  fontWeight: FontWeight.bold),
            ),
            const Icon(AppIcons.arrow_drop_down,
                size: 16, color: Color(0xFF1E88E5)),
          ],
        ),
      ),
    );
  }

  /// 弹出片区/街道/镇快速点选弹窗
  void _showTownshipPicker(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchTown = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final towns = LocationService.townshipDatabase.where((t) {
              return searchTown.isEmpty ||
                  t.townName.contains(searchTown) ||
                  t.districtName.contains(searchTown);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(AppIcons.location_city,
                              color: Color(0xFF1E88E5)),
                          SizedBox(width: 8),
                          Text('选择所在片区 / 街道 / 镇',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(
                          icon: const Icon(AppIcons.close),
                          onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    textInputAction: TextInputAction.search,
                    style: TextStyle(fontSize: 14, color: colors.onSurface),
                    onChanged: (v) =>
                        setModalState(() => searchTown = v.trim()),
                    decoration: const InputDecoration(
                      hintText: '搜索片区或镇名（如 柴胡、胡集、纪山、沙洋、团林）',
                      prefixIcon: Icon(AppIcons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: towns.length,
                      itemBuilder: (ctx, i) {
                        final t = towns[i];
                        final distToUrban =
                            LocationService.distanceToCityCenter(
                          t.latitude,
                          t.longitude,
                          t.cityName,
                        );
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFF1E88E5).withValues(alpha: 0.12),
                            child: const Icon(AppIcons.location_on,
                                color: Color(0xFF1E88E5), size: 18),
                          ),
                          title: Text(t.townName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(
                              '${t.cityName} · ${t.districtName} (距市中心 ${distToUrban.toStringAsFixed(1)}km)',
                              style: const TextStyle(fontSize: 12)),
                          trailing: Icon(AppIcons.arrow_forward_ios,
                              size: 14, color: colors.onSurfaceVariant),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _locationRequestId++;
                            Navigator.pop(ctx);
                            final newLocation = UserLocation(
                              latitude: t.latitude,
                              longitude: t.longitude,
                              accuracy: 5.0,
                              cityName: t.cityName,
                              district: t.districtName,
                              township: t.townName,
                              fullAddress:
                                  '${t.cityName} ${t.districtName} ${t.townName}',
                              source: LocationSource.townshipAnchor,
                            );
                            LocationService.saveCachedLocation(newLocation);
                            setState(() {
                              _manualLocationOverride = true;
                              _isLocating = false;
                              _currentGpsLocation = newLocation;
                              _currentCity = t.cityName;
                              _mapPanOffset = Offset.zero;
                              _gpsStatusText =
                                  '已定位至 ${t.townName} (距市中心 ${distToUrban.toStringAsFixed(1)}km)';
                            });
                            _refreshStationsForCurrentLocation();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 绘制支持手势自由拖动平移探索的科技风电子卫星地图视图
  Widget _buildVisualMapView(
      bool isDark, List<GasStationInfo> visibleStations) {
    return Container(
      height: 140,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15191E) : const Color(0xFFE8EEF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.25)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _mapPanOffset += details.delta;
            });
          },
          onDoubleTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _mapPanOffset = Offset.zero;
            });
          },
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 1. 随拖拽平移的动态道路与街区网格
              CustomPaint(
                size: Size.infinite,
                painter:
                    _MapGridPainter(isDark: isDark, panOffset: _mapPanOffset),
              ),

              // 2. 随地图平移的周边加油站 POI 坐标图钉标记
              ..._buildMapStationMarkers(isDark, visibleStations),

              // 3. 用户当前 GPS 定位信标
              Center(
                child: Transform.translate(
                  offset: _mapPanOffset,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _IsolatedRadarPulseMarker(),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5A24),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '我的位置',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. 右上角「设为中心 / 复位 / 卫星高精校准」控制胶囊
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_mapPanOffset != Offset.zero) ...[
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _locationRequestId++;
                          // 将当前拖拽的十字中心转化为新的选站中心基准坐标
                          final center = LocalMapProjection.centerForPan(
                            centerLatitude: _mapCenterLatitude,
                            centerLongitude: _mapCenterLongitude,
                            panX: _mapPanOffset.dx,
                            panY: _mapPanOffset.dy,
                          );
                          final double newLat = center.latitude;
                          final double newLon = center.longitude;

                          final newLocation = UserLocation(
                            latitude: newLat,
                            longitude: newLon,
                            accuracy: null,
                            cityName: _currentCity,
                            district: _currentGpsLocation?.district,
                            street: _currentGpsLocation?.street,
                            fullAddress:
                                '地图手工选点 (${newLat.toStringAsFixed(4)}, ${newLon.toStringAsFixed(4)})',
                            source: LocationSource.manualPinpoint,
                          );
                          LocationService.saveCachedLocation(newLocation);
                          setState(() {
                            _manualLocationOverride = true;
                            _isLocating = false;
                            _currentGpsLocation = newLocation;
                            _mapPanOffset = Offset.zero;
                            _gpsStatusText =
                                '已设为当前中心 (${newLat.toStringAsFixed(4)}, ${newLon.toStringAsFixed(4)})';
                          });
                          _refreshStationsForCurrentLocation();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue[700],
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4)
                            ],
                          ),
                          child: const Row(
                            children: [
                              Icon(AppIcons.pin_drop,
                                  size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                '设为选站中心',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _mapPanOffset = Offset.zero);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5A24),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4)
                            ],
                          ),
                          child: const Row(
                            children: [
                              Icon(AppIcons.center_focus_strong,
                                  size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                '复位',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    InkWell(
                      onTap: _isLocating ? null : _triggerGpsLocation,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            if (_isLocating)
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: Color(0xFFFF5A24)),
                              )
                            else
                              const Icon(AppIcons.satellite_alt,
                                  size: 12, color: Colors.greenAccent),
                            const SizedBox(width: 4),
                            Text(
                              _isLocating ? '校准中' : '高精校准',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 5. 底部高精 GPS 状态与当前经纬度坐标
              Positioned(
                left: 8,
                bottom: 6,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _currentGpsLocation != null
                            ? AppIcons.gps_fixed
                            : AppIcons.satellite_alt,
                        size: 13,
                        color: _currentGpsLocation != null
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _currentGpsLocation != null
                              ? 'GPS 经度: ${_currentGpsLocation!.longitude.toStringAsFixed(4)}° 纬度: ${_currentGpsLocation!.latitude.toStringAsFixed(4)}° (${_currentGpsLocation!.accuracy == null ? "手动中心" : "精度 ±${_currentGpsLocation!.accuracy!.toStringAsFixed(0)}m"} · ${_currentGpsLocation!.district ?? _currentCity})'
                              : _gpsStatusText,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构造分布在可拖动地图上的加油站图钉组件
  List<Widget> _buildMapStationMarkers(
      bool isDark, List<GasStationInfo> visibleStations) {
    final colors = Theme.of(context).colorScheme;
    final List<Widget> markers = [];
    final centerLat = _mapCenterLatitude;
    final centerLon = _mapCenterLongitude;

    for (int i = 0; i < visibleStations.length && i < 10; i++) {
      final st = visibleStations[i];
      // Draw with the same local projection used when resolving a dragged
      // map center back to latitude/longitude.
      final double dx = LocalMapProjection.xForCoordinate(
            latitude: st.latitude,
            longitude: st.longitude,
            centerLatitude: centerLat,
            centerLongitude: centerLon,
          ) +
          _mapPanOffset.dx;
      final double dy = LocalMapProjection.yForCoordinate(
            latitude: st.latitude,
            centerLatitude: centerLat,
          ) +
          _mapPanOffset.dy;

      final brandColor = _getBrandColor(st.brand);

      markers.add(
        Center(
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: InkWell(
              onTap: () => _showStationDetailSheet(context, st),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF22272E) : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: brandColor, width: 1.2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 3)
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: brandColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          st.name
                              .replaceAll('中国石化', '')
                              .replaceAll('中国石油', '')
                              .replaceAll('中国海油', '')
                              .replaceAll('壳牌', '')
                              .replaceAll('道达尔', '')
                              .trim(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: colors.onSurface,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  Icon(AppIcons.location_pin, size: 18, color: brandColor),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Color _getBrandColor(String brand) {
    switch (brand) {
      case '中国石化':
        return Colors.red;
      case '中国石油':
        return Colors.orange[800]!;
      case '中国海油':
        return Colors.blue[800]!;
      case '壳牌':
        return Colors.amber[800]!;
      default:
        return Colors.teal;
    }
  }

  /// 点击弹出加油站详细档案底抽屉
  void _showStationDetailSheet(BuildContext context, GasStationInfo st) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶端把手
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      st.name,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5A24).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '距您 ${st.distanceKm} km',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFF5A24),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(st.address,
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              const Divider(height: 20),

              // 实时油价看板大字卡片
              const Text('今日各标号指导/特惠油价',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (st.fuelPrices.isEmpty)
                Text('暂无实时油价数据',
                    style:
                        TextStyle(fontSize: 12, color: colors.onSurfaceVariant))
              else
                Row(
                  children: [
                    ...st.fuelPrices.entries.map((e) {
                      final is92 = e.key.contains('92');
                      final is95 = e.key.contains('95');
                      final color = is92
                          ? const Color(0xFFFF5A24)
                          : (is95
                              ? const Color(0xFF1E88E5)
                              : const Color(0xFF00897B));
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 6),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: color.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            children: [
                              Text(e.key,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: color)),
                              const SizedBox(height: 2),
                              Text('¥${e.value.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: color)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              const SizedBox(height: 14),

              // 优惠与营业时间
              if (st.discountInfo != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(AppIcons.local_offer_outlined,
                          size: 16, color: Colors.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '优惠政策: ${st.discountInfo!}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.red[900],
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // 营业时间与服务设施
              Row(
                children: [
                  Icon(AppIcons.access_time,
                      size: 14, color: colors.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('营业时间: ${st.businessHours}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: st.services.map((srv) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(srv,
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceVariant)),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(ctx);
                  Navigator.pop(context, st.name);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5A24),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                ),
                child: Text('确认选择【${st.name}】'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 高性能低功耗的地图定位信标微组件
class _IsolatedRadarPulseMarker extends StatelessWidget {
  const _IsolatedRadarPulseMarker();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF5A24).withValues(alpha: 0.2),
          ),
        ),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF5A24).withValues(alpha: 0.35),
          ),
        ),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF5A24),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
      ],
    );
  }
}

/// 模拟地图道路网格绘制器（支持随手势平移无缝平铺循环道路）
class _MapGridPainter extends CustomPainter {
  final bool isDark;
  final Offset panOffset;

  _MapGridPainter({required this.isDark, required this.panOffset});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF13181F) : const Color(0xFFE4EBF2);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final roadPaint = Paint()
      ..color = isDark ? Colors.white.withValues(alpha: 0.14) : Colors.white
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    final secondaryRoadPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // 动态道路线（基于 panOffset 循环）
    const spacing = 70.0;
    final offsetX = panOffset.dx % spacing;
    final offsetY = panOffset.dy % spacing;

    for (double x = -spacing + offsetX;
        x <= size.width + spacing;
        x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), secondaryRoadPaint);
    }
    for (double y = -spacing + offsetY;
        y <= size.height + spacing;
        y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), secondaryRoadPaint);
    }

    // 主干道
    final mainY = (size.height * 0.5 + panOffset.dy) % (size.height * 2) -
        size.height * 0.5;
    final mainX =
        (size.width * 0.5 + panOffset.dx) % (size.width * 2) - size.width * 0.5;
    canvas.drawLine(Offset(0, mainY + size.height * 0.5),
        Offset(size.width, mainY + size.height * 0.5), roadPaint);
    canvas.drawLine(Offset(mainX + size.width * 0.5, 0),
        Offset(mainX + size.width * 0.5, size.height), roadPaint);
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) {
    return oldDelegate.panOffset != panOffset || oldDelegate.isDark != isDark;
  }
}
