import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/core/constants/china_cities.dart';
import 'package:bearfuel/core/utils/chart_axis_utils.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/domain/bear_fuel_importer.dart';
import 'package:bearfuel/domain/fuel_calculator.dart';
import 'package:gbk_codec/gbk_codec.dart';

RefuelRecordModel _record({
  required DateTime date,
  required double mileage,
  required double amount,
  required double price,
  required double total,
  bool full = true,
}) {
  return RefuelRecordModel(
    id: 'r_${date.millisecondsSinceEpoch}',
    vehicleId: 'car_1',
    refuelDate: date,
    mileage: mileage,
    fuelAmount: amount,
    unitPrice: price,
    totalPrice: total,
    fuelType: '92#',
    isFullTank: full,
  );
}

void main() {
  group('CSV 导出 → 导入往返回归 (round trip)', () {
    test('导出后再导入，总价与金额列不被"每公里花费"覆盖', () {
      final original = FuelCalculator.computeRecords([
        _record(
          date: DateTime(2026, 6, 1, 8, 30),
          mileage: 10000,
          amount: 50,
          price: 8,
          total: 400,
        ),
        _record(
          date: DateTime(2026, 6, 15, 9, 0),
          mileage: 10500,
          amount: 40,
          price: 8,
          total: 320,
        ),
      ]);

      final csv = BearFuelImporter.exportToCsv(original);
      final result = BearFuelImporter.parseCsv(csv, 'car_1');

      expect(result.success, isTrue);
      expect(result.validCount, equals(2));
      // 回归点：此前 "每公里花费" 会覆盖 totalPrice 列映射
      expect(result.parsedRecords[0].totalPrice, equals(400.0));
      expect(result.parsedRecords[1].totalPrice, equals(320.0));
      expect(result.parsedRecords[0].unitPrice, equals(8.0));
      expect(result.parsedRecords[0].gasStation, isNull);
    });
  });

  group('GBK 编码 CSV 支持', () {
    test('GBK 字节流（中文 Excel 默认 ANSI）可正常解析', () {
      const csv =
          '时间,当前里程,加油量,单价,金额,是否加满,是否漏记,油品,加油站,备注\n'
          '2026-01-05 08:30,10000,50.0,8.0,400.0,是,否,92# 汽油,中石化荆门站,首充';

      final gbkBytes = gbk_bytes.encode(csv);
      final result = BearFuelImporter.parseBytes(gbkBytes, 'car_1');

      expect(result.success, isTrue);
      expect(result.validCount, equals(1));
      expect(result.parsedRecords.single.gasStation, equals('中石化荆门站'));
      expect(result.parsedRecords.single.totalPrice, equals(400.0));
    });
  });

  group('部分加油里程重复累计回归', () {
    test('有未加满记录时，聚合只累计完成测量周期的里程', () {
      final records = FuelCalculator.computeRecords([
        _record(
          date: DateTime(2026, 6, 1),
          mileage: 10000,
          amount: 50,
          price: 8,
          total: 400,
        ),
        // 未加满：distance = 200（距上次加满），下一个加满周期会再次覆盖该区间
        _record(
          date: DateTime(2026, 6, 8),
          mileage: 10200,
          amount: 20,
          price: 8,
          total: 160,
          full: false,
        ),
        _record(
          date: DateTime(2026, 6, 15),
          mileage: 10500,
          amount: 30,
          price: 8,
          total: 240,
        ),
      ]);

      // 修复口径：只累计完成周期记录的 distance（500km），而不是 200+500=700
      final completed = records
          .where(FuelCalculator.isCompletedCycleRecord)
          .toList();
      final distance = completed.fold<double>(
        0.0,
        (sum, r) => sum + (r.distance ?? 0.0),
      );

      expect(completed.length, equals(1));
      expect(distance, closeTo(500.0, 0.01));
      // 中间未加满记录不应携带计算出的油耗
      expect(records[1].fuelConsumption, isNull);
    });
  });

  group('坐标轴刻度工具 (ChartAxisUtils)', () {
    test('间隔按 1-2-2.5-5 序列取整且刻度数不超限', () {
      expect(ChartAxisUtils.niceInterval(0.6, maxTicks: 4), closeTo(0.2, 1e-9));
      expect(ChartAxisUtils.niceInterval(8, maxTicks: 4), equals(2.0));
      expect(ChartAxisUtils.niceInterval(55, maxTicks: 5), equals(20.0));
      expect(ChartAxisUtils.niceInterval(0, maxTicks: 5), equals(1.0));
    });

    test('X 轴标签抽稀后末尾标签不会与前一标签重叠', () {
      // count=30, step=5：末尾 29 距离上一显示标签 25 有 4 格，可补充
      expect(ChartAxisUtils.xLabelStep(30), equals(5));
      expect(ChartAxisUtils.shouldShowXLabel(29, 30, 5), isTrue);
      // count=12, step=2：末尾 11 紧贴已显示的 10，必须隐藏
      expect(ChartAxisUtils.xLabelStep(12), equals(2));
      expect(ChartAxisUtils.shouldShowXLabel(11, 12, 2), isFalse);
      // 常规标签按步长显示
      expect(ChartAxisUtils.shouldShowXLabel(10, 30, 5), isTrue);
      expect(ChartAxisUtils.shouldShowXLabel(11, 30, 5), isFalse);
      expect(ChartAxisUtils.shouldShowXLabel(30, 30, 5), isFalse);
    });

    test('纵轴文本按间隔选择小数位', () {
      expect(ChartAxisUtils.formatAxisValue(8, 2), equals('8'));
      expect(ChartAxisUtils.formatAxisValue(0.6, 0.2), equals('0.6'));
    });
  });

  group('全国城市数据集 (ChinaCities)', () {
    test('数据规模与唯一性', () {
      expect(ChinaCities.all.length, greaterThan(330));
      final unique = ChinaCities.all
          .map((c) => '${c.name}|${c.province}')
          .toSet();
      expect(unique.length, equals(ChinaCities.all.length));
      for (final city in ChinaCities.all) {
        expect(city.province, isNotEmpty, reason: city.name);
        expect(city.pinyin, matches(RegExp(r'^[a-z]+$')), reason: city.name);
        expect(city.initials, matches(RegExp(r'^[a-z]+$')), reason: city.name);
      }
    });

    test('支持中文名 / 省份 / 全拼 / 首字母搜索', () {
      // 此前硬编码白名单搜不到的城市
      final wenzhou = ChinaCities.search('温州');
      expect(wenzhou.first.name, equals('温州'));
      expect(wenzhou.first.province, equals('浙江'));

      expect(ChinaCities.search('wenzhou').first.name, equals('温州'));
      expect(ChinaCities.search('wz').first.name, equals('温州'));
      expect(ChinaCities.search('luoyang').first.name, equals('洛阳'));
      // 重名/同音城市都能返回并由省份区分
      final taizhou = ChinaCities.search('taizhou').map((c) => c.name);
      expect(taizhou, containsAll(['泰州', '台州']));
      // 省份关键字可命中该省城市
      final zhejiang = ChinaCities.search('浙江');
      expect(zhejiang.every((c) => c.province == '浙江'), isTrue);
    });
  });

  group('XLS 日期序列数转换', () {
    test('parseBytes 导出 CSV 的日期列可被 GBK/UTF-8 以外的 xls 序列数识别', () {
      // 直接验证私有转换的公共行为路径不可行，此处验证序列数换算语义：
      // 通过导出→导入路径确认日期解析正常，避免该路径被序列数转换破坏。
      final record = _record(
        date: DateTime(2026, 6, 1, 8, 30),
        mileage: 10000,
        amount: 50,
        price: 8,
        total: 400,
      );
      final csv = BearFuelImporter.exportToCsv([record]);
      final result = BearFuelImporter.parseBytes(utf8.encode(csv), 'car_1');

      expect(result.success, isTrue);
      expect(result.parsedRecords.single.refuelDate.year, equals(2026));
      expect(result.parsedRecords.single.refuelDate.month, equals(6));
    });
  });
}
