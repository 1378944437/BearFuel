import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../config/app_config.dart';
import '../../data/services/amap_location_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// 定位数据来源枚举
enum LocationSource {
  hardwareGnss, // 硬件北斗/GPS卫星芯片直连
  systemFusion, // 系统综合高精定位 (基站+WiFi+卫星)
  cachedLocation, // 本地持久化最后已知缓存
  townshipAnchor, // 片区/乡镇高精度基准网格
  manualPinpoint, // 用户地图手工轻触精准标定
}

/// 定位结果状态枚举
enum LocationFetchStatus {
  success, // 定位成功
  serviceDisabled, // 手机 GPS 定位服务未开启
  permissionDenied, // 用户拒绝了定位权限
  permissionDeniedForever, // 用户永久拒绝了定位权限
  timeout, // 定位获取超时
  error, // 其他异常
}

/// 用户当前物理位置模型
class UserLocation {
  final double latitude; // 纬度
  final double longitude; // 经度
  final double? accuracy; // 精度 (米)
  final String cityName; // 城市名称 (如 "荆门", "武汉", "北京")
  final String? district; // 区/县 (如 "东宝区", "沙洋县", "钟祥市")
  final String? township; // 乡镇/街道 (如 "胡集镇", "纪山镇", "柴胡镇", "团林铺镇")
  final String? street; // 街道路名/公路 (如 "G207国道", "S311省道", "象山大道")
  final String? fullAddress; // 完整地址字符串
  final LocationSource source; // 定位来源

  const UserLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.cityName,
    this.district,
    this.township,
    this.street,
    this.fullAddress,
    this.source = LocationSource.hardwareGnss,
  });

  /// 城市名称别名
  String get city => cityName;

  /// 生成易读的位置描述文本
  String get displayLocationName {
    if (township != null && township!.isNotEmpty) {
      final cleanTown = township!
          .replaceAll('街道', '')
          .replaceAll('管理区', '')
          .replaceAll('镇', '')
          .replaceAll('乡', '')
          .replaceAll('乡镇', '')
          .replaceAll('郊区', '')
          .trim();
      return '$cityName · $cleanTown';
    }
    if (district != null && district!.isNotEmpty) {
      return '$cityName · $district';
    }
    return cityName;
  }

  @override
  String toString() =>
      'UserLocation($latitude, $longitude, city: $cityName, town: $township, dist: $district, src: $source)';
}

/// 定位响应封装模型
class LocationResult {
  final LocationFetchStatus status;
  final UserLocation? location;
  final String message;

  const LocationResult({
    required this.status,
    this.location,
    required this.message,
  });

  bool get isSuccess =>
      status == LocationFetchStatus.success && location != null;
}

/// 彻底重构的高精卫星定位与乡镇空间计算服务
class LocationService {
  static const double _maxUsableAccuracyMeters = 300.0;
  static const String _prefKeyLat = 'user_last_location_lat';
  static const String _prefKeyLon = 'user_last_location_lon';
  static const String _prefKeyCity = 'user_last_location_city';
  static const String _prefKeyDistrict = 'user_last_location_district';
  static const String _prefKeyTown = 'user_last_location_town';
  static const String _prefKeyStreet = 'user_last_location_street';
  static const String _prefKeyAddress = 'user_last_location_address';

  /// 持久化缓存用户最后确认的位置
  static Future<void> saveCachedLocation(UserLocation loc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKeyLat, loc.latitude);
      await prefs.setDouble(_prefKeyLon, loc.longitude);
      await prefs.setString(_prefKeyCity, loc.cityName);
      if (loc.district != null && loc.district!.isNotEmpty) {
        await prefs.setString(_prefKeyDistrict, loc.district!);
      } else {
        await prefs.remove(_prefKeyDistrict);
      }
      if (loc.township != null && loc.township!.isNotEmpty) {
        await prefs.setString(_prefKeyTown, loc.township!);
      } else {
        await prefs.remove(_prefKeyTown);
      }
      if (loc.street != null && loc.street!.isNotEmpty) {
        await prefs.setString(_prefKeyStreet, loc.street!);
      } else {
        await prefs.remove(_prefKeyStreet);
      }
      if (loc.fullAddress != null && loc.fullAddress!.isNotEmpty) {
        await prefs.setString(_prefKeyAddress, loc.fullAddress!);
      } else {
        await prefs.remove(_prefKeyAddress);
      }
    } catch (_) {}
  }

  /// 获取持久化缓存的位置
  static Future<UserLocation?> getCachedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_prefKeyLat);
      final lon = prefs.getDouble(_prefKeyLon);
      final city = prefs.getString(_prefKeyCity);
      if (lat != null && lon != null && city != null) {
        return UserLocation(
          latitude: lat,
          longitude: lon,
          cityName: city,
          district: prefs.getString(_prefKeyDistrict),
          township: prefs.getString(_prefKeyTown),
          street: prefs.getString(_prefKeyStreet),
          fullAddress: prefs.getString(_prefKeyAddress),
          source: LocationSource.cachedLocation,
        );
      }
    } catch (_) {}
    return null;
  }

  /// 获取当前真实 GPS 物理经纬度（多通道混合定位 + 硬件卫星流 + 本地持久缓存）
  static Future<LocationResult> getCurrentLocation({
    Duration timeout = const Duration(seconds: 10),
    bool resolveAddress = true,
  }) async {
    try {
      // 1. 检查手机系统定位总开关
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppConfig.log('手机系统 GPS 定位服务未开启');
        final cached = await getCachedLocation();
        if (cached != null) {
          return LocationResult(
            status: LocationFetchStatus.success,
            location: cached,
            message: 'GPS已关闭，使用缓存位置 · ${cached.displayLocationName}',
          );
        }
        return const LocationResult(
          status: LocationFetchStatus.serviceDisabled,
          message: '手机 GPS 定位服务未开启，请在系统下拉栏或设置中开启定位',
        );
      }

      // 2. 检查并请求定位权限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          AppConfig.log('用户拒绝了定位权限');
          final cached = await getCachedLocation();
          if (cached != null) {
            return LocationResult(
              status: LocationFetchStatus.success,
              location: cached,
              message: '使用缓存位置 · ${cached.displayLocationName}',
            );
          }
          return const LocationResult(
            status: LocationFetchStatus.permissionDenied,
            message: '定位权限未授予，请允许应用使用“精确位置”权限',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        AppConfig.log('定位权限被永久拒绝');
        final cached = await getCachedLocation();
        if (cached != null) {
          return LocationResult(
            status: LocationFetchStatus.success,
            location: cached,
            message: '使用缓存位置 · ${cached.displayLocationName}',
          );
        }
        return const LocationResult(
          status: LocationFetchStatus.permissionDeniedForever,
          message: '定位权限已被永久拒绝，请在手机“应用权限”中开启精确定位',
        );
      }

      // 3. 多通道混合高精搜星管线
      Position? position;

      // 3.1 首选：系统综合高精定位（基站+WiFi+卫星混合，国内Android通常200ms即可返回真实物理位置）
      try {
        final candidate = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          ),
          timeLimit: const Duration(seconds: 4),
        );
        if (isUsablePosition(candidate)) {
          position = candidate;
        } else {
          AppConfig.log(
              '忽略低精度系统定位: ±${candidate.accuracy.toStringAsFixed(0)}米');
        }
      } catch (e) {
        AppConfig.log('系统综合定位等待中: $e');
      }

      // 3.2 次选：强制底层硬件 GNSS/北斗卫星驱动芯片
      if (position == null) {
        try {
          final candidate = await Geolocator.getCurrentPosition(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              forceLocationManager: true, // 直连硬件 GPS/北斗芯片
              intervalDuration: const Duration(milliseconds: 500),
            ),
            timeLimit: timeout,
          );
          if (isUsablePosition(candidate)) {
            position = candidate;
          } else {
            AppConfig.log(
                '忽略低精度硬件定位: ±${candidate.accuracy.toStringAsFixed(0)}米');
          }
        } catch (e) {
          AppConfig.log('硬件卫星定位超时: $e');
        }
      }

      // 3.3 兜底：读取硬件最后一次已知坐标
      if (position == null) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && isUsablePosition(lastKnown)) {
          position = lastKnown;
        }
      }

      // 3.4 最终兜底：读取持久化缓存
      if (position == null) {
        final cached = await getCachedLocation();
        if (cached != null) {
          return LocationResult(
            status: LocationFetchStatus.success,
            location: cached,
            message: '使用上次位置 · ${cached.displayLocationName}',
          );
        }
        return const LocationResult(
          status: LocationFetchStatus.timeout,
          message: '正在搜星中，请点击下方片区直接选定位置',
        );
      }

      // 4. 解析具体城市、区县、乡镇与街道
      final double realLat = position.latitude;
      final double realLon = position.longitude;

      String cityName = '';
      String? district;
      String? township;
      String? street;
      String? fullAddress;

      if (resolveAddress) {
        // 4.1 Prefer AMap when configured. It returns Chinese administrative
        // divisions and road names from the same POI database as station search.
        if (AmapLocationService.isConfigured) {
          try {
            final amap = await AmapLocationService.reverseGeocode(
              latitude: realLat,
              longitude: realLon,
            );
            if (amap != null) {
              cityName = (amap.city ?? amap.province ?? '')
                  .replaceAll('市', '')
                  .replaceAll('地区', '')
                  .replaceAll('省', '')
                  .trim();
              district = amap.district;
              township = amap.township;
              street = amap.street;
              fullAddress = amap.fullAddress;
            }
          } catch (_) {}
        }

        // 4.2 Fallback to platform geocoding when AMap is unavailable.
        try {
          if (cityName.isEmpty || district == null || street == null) {
            final placemarks = await placemarkFromCoordinates(realLat, realLon);
            if (placemarks.isNotEmpty) {
              final place = placemarks.first;
              cityName = cityName.isEmpty
                  ? place.locality ??
                      place.subAdministrativeArea ??
                      place.administrativeArea ??
                      ''
                  : cityName;
              cityName = cityName
                  .replaceAll('市', '')
                  .replaceAll('地区', '')
                  .replaceAll('省', '')
                  .trim();
              district ??= place.subLocality;
              township ??= place.subLocality ?? place.thoroughfare;
              street ??= place.street ?? place.thoroughfare;
              fullAddress ??=
                  '${place.administrativeArea ?? ""}${place.locality ?? ""}${place.subLocality ?? ""}${place.street ?? ""}';
            }
          }
        } catch (_) {}

        // 4.3 OpenStreetMap is only a last-resort fallback.
        if (cityName.isEmpty || district == null || street == null) {
          try {
            final online = await _reverseGeocodeOnline(realLat, realLon);
            if (online != null) {
              if (cityName.isEmpty && online['city'] != null) {
                cityName = online['city']!;
              }
              district ??= online['district'];
              township ??= online['township'] ?? online['district'];
              street ??= online['road'];
              fullAddress ??= online['fullAddress'];
            }
          } catch (_) {}
        }
      }

      // 4.3 智能识别就近乡镇与地级市
      final nearestTown = findNearestTownship(realLat, realLon);
      if (nearestTown != null) {
        township ??= nearestTown.townName;
        district ??= nearestTown.districtName;
        cityName = cityName.isEmpty ? nearestTown.cityName : cityName;
      }

      if (cityName.isEmpty) {
        final detectedCity = detectCityFromCoordinates(realLat, realLon);
        final anchor = cityAnchors[detectedCity];
        if (anchor != null &&
            calculateDistanceKm(
                  lat1: realLat,
                  lon1: realLon,
                  lat2: anchor[0],
                  lon2: anchor[1],
                ) <=
                150) {
          cityName = detectedCity;
        }
      }

      if (cityName.isEmpty) {
        return const LocationResult(
          status: LocationFetchStatus.error,
          message: '已获取定位坐标，但无法可靠识别所在城市，请手动选择城市',
        );
      }
      final resolvedCity = cityName;
      final accStr = position.accuracy.toStringAsFixed(0);

      // 计算与主城区的物理距离
      final urbanDist = distanceToCityCenter(realLat, realLon, resolvedCity);

      final isRural = urbanDist > 12.0;
      final cleanTown = (township ?? district ?? cityName)
          .replaceAll('市', '')
          .replaceAll('区', '')
          .replaceAll('县', '')
          .replaceAll('镇', '')
          .replaceAll('乡', '')
          .replaceAll('街道', '')
          .replaceAll('乡镇', '')
          .replaceAll('郊区', '')
          .replaceAll('便民', '')
          .trim();
      final areaTag = isRural
          ? '$cleanTown(距市中心${urbanDist.toStringAsFixed(1)}km)'
          : cleanTown;

      AppConfig.log(
          'GPS 定位完成: lat=$realLat, lon=$realLon, city=$resolvedCity, town=$township, urbanDist=${urbanDist.toStringAsFixed(1)}km');

      final finalLoc = UserLocation(
        latitude: realLat,
        longitude: realLon,
        accuracy: position.accuracy,
        cityName: resolvedCity,
        district: district,
        township: township,
        street: street,
        fullAddress: fullAddress ?? '$resolvedCity $areaTag ${street ?? ""}',
        source: LocationSource.hardwareGnss,
      );

      // 异步保存到本地持久化缓存
      saveCachedLocation(finalLoc);

      return LocationResult(
        status: LocationFetchStatus.success,
        location: finalLoc,
        message: '北斗/GPS定位成功 · $resolvedCity $areaTag (精度 ±$accStr米)',
      );
    } catch (e) {
      AppConfig.log('定位异常: $e');
      return LocationResult(
        status: LocationFetchStatus.error,
        message: '定位遇到问题: $e',
      );
    }
  }

  /// 网络轻量快速逆地理编码
  static Future<Map<String, String>?> _reverseGeocodeOnline(
      double lat, double lon) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lon&accept-language=zh-CN',
      );
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'BearFuel/0.2.5 (support@bearfuel.app)');
      final res = await req.close().timeout(const Duration(seconds: 2));

      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          String city = (address['city'] ??
                  address['county'] ??
                  address['state_district'] ??
                  '')
              .toString();
          city = city.replaceAll('市', '').replaceAll('地区', '').trim();
          final district = (address['suburb'] ??
                  address['district'] ??
                  address['county'] ??
                  '')
              .toString();
          final township = (address['town'] ??
                  address['village'] ??
                  address['hamlet'] ??
                  address['suburb'] ??
                  '')
              .toString();
          final road =
              (address['road'] ?? address['neighbourhood'] ?? '').toString();
          final displayName = data['display_name']?.toString();

          return {
            'city': city,
            'district': district,
            'township': township,
            'road': road,
            'fullAddress': displayName ?? '$city $district $township $road',
          };
        }
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
    return null;
  }

  /// 标准地球球面大圆（Haversine）算法计算两点间真实物理距离 (返回公里数 km)
  static double calculateDistanceKm({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const double earthRadiusKm = 6371.0;

    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final double distance = earthRadiusKm * c;

    return double.parse(distance.toStringAsFixed(2));
  }

  /// 计算当前位置到指定城市中心的距离。没有城市锚点时不虚构距离。
  static double distanceToCityCenter(double lat, double lon, String cityName) {
    final anchor = cityAnchors[cityName];
    if (anchor == null) return 0.0;
    return calculateDistanceKm(
      lat1: lat,
      lon1: lon,
      lat2: anchor[0],
      lon2: anchor[1],
    );
  }

  /// 乡镇/区县基准数据模型
  static final List<TownshipAnchor> townshipDatabase = [
    // 荆门市核心城区
    TownshipAnchor(
        cityName: '荆门',
        districtName: '东宝区',
        townName: '象山/龙泉街道',
        latitude: 31.0450,
        longitude: 112.2010),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '东宝区',
        townName: '泉口街道',
        latitude: 31.0550,
        longitude: 112.1950),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '掇刀区',
        townName: '掇刀石街道',
        latitude: 31.0120,
        longitude: 112.2180),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '掇刀区',
        townName: '白庙街道',
        latitude: 31.0310,
        longitude: 112.2350),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '漳河新区',
        townName: '漳河镇',
        latitude: 31.0020,
        longitude: 112.1650),

    // 荆门市各乡镇/郊区（离城区 15km~70km）
    TownshipAnchor(
        cityName: '荆门',
        districtName: '东宝区',
        townName: '牌楼镇',
        latitude: 31.1120,
        longitude: 112.2450),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '东宝区',
        townName: '子陵铺镇',
        latitude: 31.1560,
        longitude: 112.1780),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '东宝区',
        townName: '石桥驿镇',
        latitude: 31.2450,
        longitude: 112.1520),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '东宝区',
        townName: '栗溪镇',
        latitude: 31.3120,
        longitude: 111.9850),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '东宝区',
        townName: '仙居乡',
        latitude: 31.3650,
        longitude: 112.0820),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '掇刀区',
        townName: '团林铺镇',
        latitude: 30.9120,
        longitude: 112.2280),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '掇刀区',
        townName: '麻城镇',
        latitude: 30.9380,
        longitude: 112.3520),

    // 钟祥市各乡镇（距城区 35km~80km）
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '郢中街道',
        latitude: 31.1680,
        longitude: 112.5850),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '胡集镇',
        latitude: 31.4250,
        longitude: 112.3150),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '柴胡镇',
        latitude: 31.0820,
        longitude: 112.4580),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '石牌镇',
        latitude: 31.0250,
        longitude: 112.4120),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '洋梓镇',
        latitude: 31.2580,
        longitude: 112.6320),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '冷水镇',
        latitude: 31.3250,
        longitude: 112.4850),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '旧口镇',
        latitude: 30.9250,
        longitude: 112.6450),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '丰乐镇',
        latitude: 31.3850,
        longitude: 112.4120),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '磷矿镇',
        latitude: 31.2850,
        longitude: 112.4280),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '钟祥市',
        townName: '双路/长滩',
        latitude: 31.1850,
        longitude: 112.7520),

    // 沙洋县各乡镇（距城区 25km~65km）
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '沙洋镇',
        latitude: 30.7050,
        longitude: 112.5880),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '五里铺镇',
        latitude: 30.8520,
        longitude: 112.2150),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '十里铺镇',
        latitude: 30.7650,
        longitude: 112.2450),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '纪山镇',
        latitude: 30.6850,
        longitude: 112.2680),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '拾回桥镇',
        latitude: 30.7120,
        longitude: 112.3850),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '后港镇',
        latitude: 30.6050,
        longitude: 112.3850),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '毛李镇',
        latitude: 30.5980,
        longitude: 112.5520),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '官当镇',
        latitude: 30.6350,
        longitude: 112.6450),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '高阳镇',
        latitude: 30.8250,
        longitude: 112.4580),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '沙洋县',
        townName: '马良镇',
        latitude: 30.6950,
        longitude: 112.7250),

    // 京山市各乡镇（距城区 50km~90km）
    TownshipAnchor(
        cityName: '荆门',
        districtName: '京山市',
        townName: '新市街道',
        latitude: 31.0250,
        longitude: 113.0150),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '京山市',
        townName: '宋河镇',
        latitude: 31.2580,
        longitude: 113.0650),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '京山市',
        townName: '永漋镇',
        latitude: 30.8520,
        longitude: 113.0850),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '京山市',
        townName: '曹武镇',
        latitude: 30.9350,
        longitude: 113.1950),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '京山市',
        townName: '罗店镇',
        latitude: 31.1520,
        longitude: 113.2150),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '京山市',
        townName: '钱场镇',
        latitude: 30.9150,
        longitude: 113.0250),
    TownshipAnchor(
        cityName: '荆门',
        districtName: '京山市',
        townName: '雁门口镇',
        latitude: 31.0520,
        longitude: 112.8250),

    // 屈家岭管理区
    TownshipAnchor(
        cityName: '荆门',
        districtName: '屈家岭',
        townName: '易家岭街道/屈家岭镇',
        latitude: 30.8420,
        longitude: 112.8950),
  ];

  /// 寻找最近的乡镇基准点 (用于农村/乡下环境的精准路网识别)
  static TownshipAnchor? findNearestTownship(double lat, double lon) {
    TownshipAnchor? closest;
    double minDistance = 25.0; // 25公里范围内的乡镇

    for (final anchor in townshipDatabase) {
      final d = calculateDistanceKm(
        lat1: lat,
        lon1: lon,
        lat2: anchor.latitude,
        lon2: anchor.longitude,
      );
      if (d < minDistance) {
        minDistance = d;
        closest = anchor;
      }
    }
    return closest;
  }

  /// 全国重点地市级及区县级高精坐标基准锚点
  static final Map<String, List<double>> cityAnchors = {
    // 湖北省
    '荆门': [31.0354, 112.2043],
    '武汉': [30.5928, 114.3055],
    '襄阳': [32.0086, 112.1224],
    '宜昌': [30.6919, 111.2864],
    '荆州': [30.3351, 112.2418],
    '黄石': [30.2200, 115.0385],
    '十堰': [32.6293, 110.7984],
    '黄冈': [30.4534, 114.8722],
    '孝感': [30.9179, 113.9178],
    '咸宁': [29.8415, 114.3224],
    '随州': [31.6905, 113.3825],
    '鄂州': [30.3965, 114.8906],
    '恩施': [30.2728, 109.4880],
    '仙桃': [30.3644, 113.4539],
    '潜江': [30.4212, 112.8968],
    '天门': [30.6531, 113.1658],
    '神农架': [31.7445, 110.6758],

    // 直辖市及全国主要地市
    '北京': [39.9042, 116.4074],
    '上海': [31.2304, 121.4737],
    '广州': [23.1291, 113.2644],
    '深圳': [22.5431, 114.0579],
    '天津': [39.0842, 117.2009],
    '重庆': [29.5630, 106.5516],
    '成都': [30.5728, 104.0668],
    '杭州': [30.2741, 120.1551],
    '南京': [32.0603, 118.7969],
    '苏州': [31.2990, 120.5853],
    '西安': [34.3416, 108.9398],
    '郑州': [34.7466, 113.6253],
    '长沙': [28.2282, 112.9388],
    '合肥': [31.8206, 117.2272],
    '南昌': [28.6829, 115.8582],
    '福州': [26.0745, 119.2965],
    '厦门': [24.4798, 118.0894],
    '济南': [36.6512, 117.1201],
    '青岛': [36.0671, 120.3826],
    '石家庄': [38.0428, 114.5149],
    '太原': [37.8706, 112.5489],
    '沈阳': [41.8057, 123.4315],
    '大连': [38.9140, 121.6147],
    '长春': [43.8171, 125.3235],
    '哈尔滨': [45.8038, 126.5350],
    '南宁': [22.8170, 108.3665],
    '海口': [20.0440, 110.1999],
    '三亚': [18.2528, 109.5120],
    '贵阳': [26.6477, 106.6302],
    '昆明': [24.8801, 102.8329],
    '兰州': [36.0611, 103.8343],
    '西宁': [36.6171, 101.7782],
    '银川': [38.4872, 106.2309],
    '乌鲁木齐': [43.8256, 87.6168],
    '呼和浩特': [40.8427, 111.7510],
    '拉萨': [29.6525, 91.1721],
    '无锡': [31.4912, 120.3119],
    '常州': [31.8112, 119.9741],
    '宁波': [29.8683, 121.5440],
    '温州': [28.0006, 120.6994],
    '佛山': [23.0215, 113.1214],
    '东莞': [23.0207, 113.7518],
    '烟台': [37.4638, 121.4479],
    '洛阳': [34.6181, 112.4540],
  };

  /// 根据经纬度识别最近的地级市
  static String detectCityFromCoordinates(double lat, double lon) {
    String closestCity = '北京';
    double minDistance = double.infinity;

    cityAnchors.forEach((city, coords) {
      final d = calculateDistanceKm(
        lat1: lat,
        lon1: lon,
        lat2: coords[0],
        lon2: coords[1],
      );
      if (d < minDistance) {
        minDistance = d;
        closestCity = city;
      }
    });

    return closestCity;
  }

  static double _degToRad(double deg) {
    return deg * (pi / 180.0);
  }

  static bool isUsablePosition(Position position) {
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude >= -90 &&
        position.latitude <= 90 &&
        position.longitude >= -180 &&
        position.longitude <= 180 &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= _maxUsableAccuracyMeters;
  }
}

/// 乡镇/区县网格锚点
class TownshipAnchor {
  final String cityName;
  final String districtName;
  final String townName;
  final double latitude;
  final double longitude;

  const TownshipAnchor({
    required this.cityName,
    required this.districtName,
    required this.townName,
    required this.latitude,
    required this.longitude,
  });
}
