import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'amap_key_store.dart';

class AmapCoordinate {
  final double latitude;
  final double longitude;

  const AmapCoordinate({required this.latitude, required this.longitude});
}

class AmapAddress {
  final String? province;
  final String? city;
  final String? district;
  final String? township;
  final String? street;
  final String fullAddress;

  const AmapAddress({
    this.province,
    this.city,
    this.district,
    this.township,
    this.street,
    required this.fullAddress,
  });
}

class AmapPoi {
  final String name;
  final String address;
  final String? brand;
  final String? phone;
  final double distanceKm;
  final double latitude;
  final double longitude;

  const AmapPoi({
    required this.name,
    required this.address,
    this.brand,
    this.phone,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
  });
}

class AmapConnectionTestResult {
  final bool success;
  final String message;

  const AmapConnectionTestResult({
    required this.success,
    required this.message,
  });
}

/// AMap Web Service adapter.
///
/// AMap's domestic APIs use GCJ-02 while the device location is WGS-84. The
/// adapter converts the request before calling AMap and converts POI results
/// back to WGS-84 so the rest of the application uses one coordinate system.
class AmapLocationService {
  static const double _axis = 6378245.0;
  static const double _eccentricity = 0.00669342162296594323;

  static bool get isConfigured => AmapKeyStore.currentKey.isNotEmpty;

  static Future<AmapConnectionTestResult> testConnection({
    required String key,
  }) async {
    final trimmedKey = key.trim();
    if (trimmedKey.isEmpty) {
      return const AmapConnectionTestResult(
        success: false,
        message: '请先输入高德 Web 服务 Key',
      );
    }

    final data = await _getJson('/v3/geocode/regeo', {
      'key': trimmedKey,
      'location': '116.4074,39.9042',
      'extensions': 'base',
      'output': 'json',
    });
    if (data == null) {
      return const AmapConnectionTestResult(
        success: false,
        message: '无法连接高德服务或返回内容不是有效 JSON',
      );
    }
    if (data['status'] == '1') {
      return const AmapConnectionTestResult(
        success: true,
        message: '高德连接成功，Key 可正常调用逆地理编码',
      );
    }

    final info = _stringValue(data['info']) ?? '未知错误';
    final infocode = _stringValue(data['infocode']);
    return AmapConnectionTestResult(
      success: false,
      message: '高德返回失败：$info${infocode == null ? '' : '（$infocode）'}',
    );
  }

  static Future<AmapAddress?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    if (!isConfigured) return null;
    final amap = _wgs84ToGcj02(latitude, longitude);
    final data = await _getJson('/v3/geocode/regeo', {
      'key': AmapKeyStore.currentKey,
      'location': '${amap.longitude},${amap.latitude}',
      'extensions': 'base',
      'output': 'json',
    });
    if (data?['status'] != '1') return null;

    final regeo = data?['regeocode'] as Map<String, dynamic>?;
    final component = regeo?['addressComponent'] as Map<String, dynamic>?;
    if (regeo == null || component == null) return null;

    final province = _stringValue(component['province']);
    final city = _stringValue(component['city']);
    final district = _stringValue(component['district']);
    final township = _stringValue(component['township']);
    final streetInfo = component['streetNumber'] as Map<String, dynamic>?;
    final street = _stringValue(streetInfo?['street']);

    return AmapAddress(
      province: province,
      city: city,
      district: district,
      township: township,
      street: street,
      fullAddress: _stringValue(regeo['formatted_address']) ??
          [
            province,
            city,
            district,
            township,
            street,
            _stringValue(streetInfo?['number'])
          ].whereType<String>().where((part) => part.isNotEmpty).join(),
    );
  }

  static Future<List<AmapPoi>?> searchGasStations({
    required double latitude,
    required double longitude,
    int radiusMeters = 10000,
  }) async {
    if (!isConfigured) return null;
    final amap = _wgs84ToGcj02(latitude, longitude);
    final data = await _getJson('/v3/place/around', {
      'key': AmapKeyStore.currentKey,
      'location': '${amap.longitude},${amap.latitude}',
      'types': '010100',
      'radius': radiusMeters.toString(),
      'sortrule': 'distance',
      'offset': '15',
      'page': '1',
      // 站点列表只需要名称、地址和电话，避免请求详情字段拖慢首屏。
      'extensions': 'base',
      'output': 'json',
    });
    if (data?['status'] != '1') return null;

    final pois = data?['pois'];
    if (pois is! List) return <AmapPoi>[];

    final result = <AmapPoi>[];
    for (final raw in pois) {
      if (raw is! Map<String, dynamic>) continue;
      final point = _parseCoordinate(raw['location']);
      if (point == null) continue;
      final wgs = _gcj02ToWgs84(point.latitude, point.longitude);
      final distanceMeters =
          double.tryParse(_stringValue(raw['distance']) ?? '');
      final address = _stringValue(raw['address']) ?? '地址暂无';
      result.add(
        AmapPoi(
          name: _stringValue(raw['name']) ?? '未命名加油站',
          address: address,
          brand: _inferBrand(_stringValue(raw['name'])),
          phone: _stringValue(raw['tel']),
          distanceKm: distanceMeters == null
              ? _distanceKm(latitude, longitude, wgs.latitude, wgs.longitude)
              : double.parse((distanceMeters / 1000).toStringAsFixed(2)),
          latitude: wgs.latitude,
          longitude: wgs.longitude,
        ),
      );
    }
    return result;
  }

  static Future<Map<String, dynamic>?> _getJson(
    String path,
    Map<String, String> parameters,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final uri = Uri.https('restapi.amap.com', path, parameters);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static String? _stringValue(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is num) return value.toString();
    if (value is List && value.isNotEmpty) return _stringValue(value.first);
    return null;
  }

  static AmapCoordinate? _parseCoordinate(dynamic value) {
    final text = _stringValue(value);
    if (text == null) return null;
    final parts = text.split(',');
    if (parts.length != 2) return null;
    final longitude = double.tryParse(parts[0]);
    final latitude = double.tryParse(parts[1]);
    if (latitude == null || longitude == null) return null;
    return AmapCoordinate(latitude: latitude, longitude: longitude);
  }

  static String? _inferBrand(String? name) {
    if (name == null) return null;
    if (name.contains('中国石化') ||
        name.contains('中石化') ||
        name.toLowerCase().contains('sinopec')) {
      return '中国石化';
    }
    if (name.contains('中国石油') ||
        name.contains('中石油') ||
        name.toLowerCase().contains('petrochina')) {
      return '中国石油';
    }
    if (name.contains('中国海油') ||
        name.contains('中海油') ||
        name.toLowerCase().contains('cnooc')) {
      return '中国海油';
    }
    if (name.contains('壳牌') || name.toLowerCase().contains('shell'))
      return '壳牌';
    if (name.contains('道达尔') || name.toLowerCase().contains('total'))
      return '道达尔';
    return '其他';
  }

  static double _distanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    const radius = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return double.parse(
        (radius * 2 * atan2(sqrt(a), sqrt(1 - a))).toStringAsFixed(2));
  }

  static AmapCoordinate _wgs84ToGcj02(double latitude, double longitude) {
    if (_outOfChina(latitude, longitude)) {
      return AmapCoordinate(latitude: latitude, longitude: longitude);
    }
    final dLat = _transformLatitude(longitude - 105.0, latitude - 35.0);
    final dLon = _transformLongitude(longitude - 105.0, latitude - 35.0);
    final radLat = latitude / 180.0 * pi;
    var magic = sin(radLat);
    magic = 1 - _eccentricity * magic * magic;
    final sqrtMagic = sqrt(magic);
    return AmapCoordinate(
      latitude: latitude +
          (dLat * 180.0) /
              ((_axis * (1 - _eccentricity)) / (magic * sqrtMagic) * pi),
      longitude:
          longitude + (dLon * 180.0) / (_axis / sqrtMagic * cos(radLat) * pi),
    );
  }

  static AmapCoordinate _gcj02ToWgs84(double latitude, double longitude) {
    if (_outOfChina(latitude, longitude)) {
      return AmapCoordinate(latitude: latitude, longitude: longitude);
    }
    var result = AmapCoordinate(latitude: latitude, longitude: longitude);
    for (var i = 0; i < 3; i++) {
      final converted = _wgs84ToGcj02(result.latitude, result.longitude);
      result = AmapCoordinate(
        latitude: result.latitude + latitude - converted.latitude,
        longitude: result.longitude + longitude - converted.longitude,
      );
    }
    return result;
  }

  static bool _outOfChina(double latitude, double longitude) {
    return longitude < 72.004 ||
        longitude > 137.8347 ||
        latitude < 0.8293 ||
        latitude > 55.8271;
  }

  static double _transformLatitude(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * pi) + 320 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLongitude(double x, double y) {
    var ret =
        300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret +=
        (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }
}
