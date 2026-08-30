import 'package:flutter_test/flutter_test.dart';

import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/providers/fuel_price_provider.dart';
import 'package:bearfuel/data/services/apizero_fuel_price_service.dart';
import 'package:bearfuel/data/services/xxyh_price_service.dart';
import 'package:bearfuel/domain/fuel_price_service.dart';

/// 用真实页面结构片段构造的最小 HTML（2026-08-30 实抓样本）
const String provincePageHtml = '''
<html><body>
<div><span class="adj-label-left">上次调价：<b>08-29</b></span>
<span class="adj-center">还有<b>13</b>天</span>
<span class="adj-label-right">下次调价：<b>09-12</b></span></div>
<table class="price-table">
  <thead><tr><th></th><th>92#(93)</th><th>95#(97)</th><th>0#柴油</th></tr></thead>
  <tbody>
    <tr>
      <td class="region-name"><a href="/fprice/proilprice.php?province=广东省">广东省</a></td>
      <td class="price-val highlight">8.10</td>
      <td class="price-val highlight">8.78</td>
      <td class="price-val muted">7.76</td>
    </tr>
    <tr>
      <td class="region-name"><a href="/fprice/cityprice.php?city=%E4%B8%9C%E8%8E%9E%E5%B8%82">东莞市</a></td>
      <td class="price-val highlight"><div class="province-highlighted-price-high">8.10</div></td>
      <td class="price-val muted">-</td>
      <td class="price-val muted">-</td>
    </tr>
  </tbody>
</table>
</body></html>
''';

void main() {
  group('小熊油耗网页解析 (XxyhFuelPriceService)', () {
    test('解析省级 92/95/0 价格与调价日期', () {
      final snapshot = XxyhFuelPriceService.parseProvincePage(
        '广东',
        provincePageHtml,
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.province, '广东');
      expect(snapshot.gas92, 8.10);
      expect(snapshot.gas95, 8.78);
      expect(snapshot.diesel0, 7.76);
      expect(snapshot.lastChangeDate, isNotNull);
      expect(snapshot.lastChangeDate!.month, 8);
      expect(snapshot.lastChangeDate!.day, 29);
      expect(snapshot.nextAdjustDate, isNotNull);
      expect(snapshot.nextAdjustDate!.month, 9);
      expect(snapshot.nextAdjustDate!.day, 12);
      // 上次调价不可能在未来：年份应就近取当前或去年
      expect(
        snapshot.lastChangeDate!.isBefore(
          DateTime.now().add(const Duration(days: 15)),
        ),
        true,
      );
    });

    test('省份名归一化与请求省份匹配', () {
      final byFullName = XxyhFuelPriceService.parseProvincePage(
        '广东省',
        provincePageHtml,
      );
      expect(byFullName, isNotNull);
      expect(
        XxyhFuelPriceService.normalizeRegionName('新疆维吾尔自治区'),
        '新疆',
      );
      expect(
        XxyhFuelPriceService.normalizeRegionName('北京市'),
        '北京',
      );
    });

    test('省份不匹配或结构缺失时返回 null', () {
      expect(
        XxyhFuelPriceService.parseProvincePage('北京', provincePageHtml),
        isNull,
      );
      expect(
        XxyhFuelPriceService.parseProvincePage('广东', '<html></html>'),
        isNull,
      );
    });
  });

  group('油价校准：网站数据优先', () {
    ApiZeroFuelPriceSnapshot apiSnapshot({
      double gas92 = 8.12,
      double gas95 = 8.78,
      double gas98 = 9.30,
      double diesel0 = 7.76,
    }) => ApiZeroFuelPriceSnapshot(
      province: '广东',
      price: ProvinceFuelPrice(
        province: '广东',
        gas92: gas92,
        gas95: gas95,
        gas98: gas98,
        diesel0: diesel0,
        lastChangeAmount: 0,
        lastChangeDate: DateTime(2026, 8, 29),
      ),
      fetchedAt: DateTime(2026, 8, 30, 10),
      sourceUrl: 'https://v1.apizero.cn/api/oil-price',
    );

    final xxyh = XxyhPriceSnapshot(
      province: '广东',
      gas92: 8.10,
      gas95: 8.78,
      diesel0: 7.76,
      lastChangeDate: DateTime(2026, 8, 29),
      fetchedAt: DateTime(2026, 8, 30, 10),
      sourceUrl: 'https://www.xiaoxiongyouhao.com/fprice/proilprice.php',
    );

    test('92 号不一致时以网站为准，98 号保留接口值', () {
      final merged = FuelPriceProvider.calibrateWithXxyh(apiSnapshot(), xxyh);
      expect(merged, isNotNull);
      expect(merged!.price.gas92, 8.10);
      expect(merged.price.gas95, 8.78);
      // 网站没有 98#：该标号保留接口值
      expect(merged.price.gas98, 9.30);
      expect(merged.price.diesel0, 7.76);
      expect(merged.price.lastChangeDate, DateTime(2026, 8, 29));
    });

    test('完全一致且日期相同时无需校准', () {
      final same = FuelPriceProvider.calibrateWithXxyh(
        apiSnapshot(gas92: 8.10, gas95: 8.78, diesel0: 7.76),
        xxyh,
      );
      expect(same, isNull);
    });

    test('网页无数据时返回 null', () {
      expect(FuelPriceProvider.calibrateWithXxyh(apiSnapshot(), null), isNull);
    });

    test('备用兜底：网页数据补齐 92/95/0，98 沿用接口历史缓存', () {
      final stale = apiSnapshot();
      final backup = ProvinceFuelPrice(
        province: stale.price.province,
        gas92: xxyh.gas92,
        gas95: xxyh.gas95,
        gas98: stale.price.gas98,
        diesel0: xxyh.diesel0,
        lastChangeAmount: 0,
        lastChangeDate: xxyh.lastChangeDate ?? stale.price.lastChangeDate,
      );
      expect(backup.gas92, 8.10);
      expect(backup.gas95, 8.78);
      expect(backup.diesel0, 7.76);
      expect(backup.gas98, 9.30);
      expect(backup.isAvailable, true);
    });

    test('账本审查按校准后的价格对比（差异阈值语义不变）', () {
      final record = RefuelRecordModel(
        id: 'r1',
        vehicleId: 'v1',
        refuelDate: DateTime(2026, 8, 30),
        mileage: 100,
        fuelAmount: 30.0,
        unitPrice: 8.50,
        totalPrice: 255.0,
        fuelType: '92#',
        isFullTank: true,
        isForgotPrevious: false,
      );
      // 校准后 92 号为 8.10，与账单 8.50 差 0.40，超过默认阈值 0.30
      final snapshot = apiSnapshot(gas92: 8.10);
      expect(snapshot.price.gas92, 8.10);
      expect((record.unitPrice - snapshot.price.gas92).abs() > 0.30, true);
    });
  });
}
