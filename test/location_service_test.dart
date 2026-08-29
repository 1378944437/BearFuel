import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/core/utils/location_service.dart';
import 'package:bearfuel/core/utils/map_coordinate_utils.dart';

void main() {
  group('GPS 定位与物理测距算法测试 (LocationService Tests)', () {
    test('1. Haversine 球面测距精度测试 (北京天安门至朝阳公园)', () {
      const lat1 = 39.9087;
      const lon1 = 116.3975;
      const lat2 = 39.9412;
      const lon2 = 116.4812;

      final distanceKm = LocationService.calculateDistanceKm(
        lat1: lat1,
        lon1: lon1,
        lat2: lat2,
        lon2: lon2,
      );

      expect(distanceKm, greaterThan(7.5));
      expect(distanceKm, lessThan(8.5));
    });

    test('2. 荆门实际坐标就近城市匹配测试 (坚决不误判为武汉)', () {
      // 湖北荆门象山大道附近坐标 (31.0354, 112.2043)
      final city = LocationService.detectCityFromCoordinates(31.0354, 112.2043);
      expect(city, equals('荆门')); // 必须精准识别为荆门，而非武汉
    });

    test('3. 全国其他地市坐标就近逆地理测试', () {
      // 广州塔坐标附近
      final city1 = LocationService.detectCityFromCoordinates(
        23.1064,
        113.3245,
      );
      expect(city1, equals('广州'));

      // 武汉中南路坐标附近
      final city2 = LocationService.detectCityFromCoordinates(
        30.5420,
        114.3350,
      );
      expect(city2, equals('武汉'));

      // 成都春熙路附近
      final city3 = LocationService.detectCityFromCoordinates(
        30.6574,
        104.0818,
      );
      expect(city3, equals('成都'));
    });

    test('4. 乡镇/农村高精度空间网格匹配测试 (柴胡/胡集/纪山/沙洋)', () {
      // 柴胡集镇附近坐标 (31.0820, 112.4580)，距城区 32km
      final town1 = LocationService.findNearestTownship(31.0820, 112.4580);
      expect(town1, isNotNull);
      expect(town1!.townName, equals('柴胡镇'));

      // 胡集镇附近坐标 (31.4250, 112.3150)，距城区 45km
      final town2 = LocationService.findNearestTownship(31.4250, 112.3150);
      expect(town2, isNotNull);
      expect(town2!.townName, equals('胡集镇'));

      // 纪山镇附近坐标 (30.6850, 112.2680)，距城区 40km
      final town3 = LocationService.findNearestTownship(30.6850, 112.2680);
      expect(town3, isNotNull);
      expect(town3!.townName, equals('纪山镇'));
    });

    test('5. 地图拖拽中心换算使用稳定坐标投影', () {
      const centerLat = 31.0354;
      const centerLon = 112.2043;
      final selected = LocalMapProjection.centerForPan(
        centerLatitude: centerLat,
        centerLongitude: centerLon,
        panX: 450,
        panY: 450,
      );

      expect(selected.latitude, closeTo(centerLat + 0.1, 0.000001));
      expect(selected.longitude, lessThan(centerLon));

      final x = LocalMapProjection.xForCoordinate(
        latitude: selected.latitude,
        longitude: selected.longitude,
        centerLatitude: centerLat,
        centerLongitude: centerLon,
      );
      final y = LocalMapProjection.yForCoordinate(
        latitude: selected.latitude,
        centerLatitude: centerLat,
      );
      expect(x, closeTo(-450, 0.001));
      expect(y, closeTo(-450, 0.001));
    });
  });
}
