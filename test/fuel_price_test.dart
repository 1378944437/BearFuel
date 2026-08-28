import 'package:flutter_test/flutter_test.dart';

import 'package:bearfuel/data/services/apizero_oil_forecast_service.dart';
import 'package:bearfuel/data/services/apizero_fuel_price_service.dart';
import 'package:bearfuel/domain/fuel_price_service.dart';

void main() {
  group('油价领域服务测试', () {
    test('仅保留省份名称列表，不内置任何油价示例', () {
      final provinces = FuelPriceService.getAllProvinces();
      expect(provinces, contains('北京'));
      expect(provinces, contains('湖北'));

      final beijing = FuelPriceService.getProvincePrice('北京');
      expect(beijing.isAvailable, isFalse);
      expect(beijing.province, '北京');

      final shanghai = FuelPriceService.getProvincePrice('上海');
      expect(shanghai.isAvailable, isFalse);
      expect(shanghai.gas92, 0);
    });

    test('城市映射只用于生成 API 省份参数', () {
      expect(FuelPriceService.cityToProvince('荆门'), '湖北');
      expect(FuelPriceService.cityToProvince('深圳'), '广东');
      expect(FuelPriceService.cityToProvince('北京市'), '北京');
      expect(FuelPriceService.cityToProvince('长春'), '吉林');
      expect(FuelPriceService.cityToProvince('哈尔滨'), '黑龙江');
      expect(FuelPriceService.cityToProvince('青岛'), '山东');
      expect(FuelPriceService.cityToProvince('南宁'), '广西');
    });

    test('没有内置历史和预测示例数据', () {
      expect(FuelPriceService.getAdjustmentForecast().isAvailable, isFalse);
    });

    test('调价摘要将字面量换行转为真实换行', () {
      final item = ApiZeroAdjustmentScheduleItem.fromJson({
        'date': '2026-08-01',
        'status': '上调',
        'summary': r'汽油每吨上调685元\n柴油每吨上调655元',
      });

      expect(item?.summary, '汽油每吨上调685元\n柴油每吨上调655元');
    });

    test('油价缓存拒绝非正数', () {
      final snapshot = ApiZeroFuelPriceSnapshot.fromJson({
        'province': '北京',
        'sourceUrl': 'https://example.com',
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
        'gas92': 0,
        'gas95': 8.0,
        'gas98': 9.0,
        'diesel0': 7.0,
      });

      expect(snapshot, isNull);
    });
  });
}
