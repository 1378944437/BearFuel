import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/providers/refuel_provider.dart';

/// P1-05 回归：当前表显必须取最新时间的记录，而不是全库最大值。
///
/// 补录历史记录、里程回拨、换表或误录高里程时，
/// 最大值不等于最新表显，会导致记账校验、仪表盘和保养提醒错误。
void main() {
  RefuelRecordModel rec(String id, DateTime date, double mileage) {
    return RefuelRecordModel(
      id: id,
      vehicleId: 'veh',
      refuelDate: date,
      mileage: mileage,
      fuelAmount: 40,
      unitPrice: 8.0,
      totalPrice: 320,
      fuelType: '92#',
      isFullTank: true,
    );
  }

  group('latestMileageOf（当前表显）', () {
    test('空记录返回 0', () {
      expect(RefuelProvider.latestMileageOf(const []), equals(0.0));
    });

    test('正常单调里程：取最新时间的记录', () {
      final records = [
        rec('a', DateTime(2026, 8, 1), 10000),
        rec('b', DateTime(2026, 8, 15), 10500),
      ];
      expect(RefuelProvider.latestMileageOf(records), equals(10500));
    });

    test('补录历史记录后：当前表显不受新插入的高里程历史记录影响', () {
      // 列表按加载顺序：8/10 高里程是最新时间，7 月记录是补录
      final records = [
        rec('a', DateTime(2026, 7, 1), 9000),
        rec('b', DateTime(2026, 8, 10), 12000),
        // 补录：发现 7 月漏记了一条
        rec('c', DateTime(2026, 7, 20), 9500),
      ];
      // 最新时间 8/10 → 12000；不是最大值也不是列表第一条
      expect(RefuelProvider.latestMileageOf(records), equals(12000));
    });

    test('里程回拨（换表）后：当前表显是回拨后的读数', () {
      final records = [
        rec('a', DateTime(2026, 1, 10), 10000),
        rec('b', DateTime(2026, 1, 20), 10500),
        // 换表：新表从 300 开始
        rec('c', DateTime(2026, 2, 1), 300),
        rec('d', DateTime(2026, 2, 15), 800),
      ];
      expect(RefuelProvider.latestMileageOf(records), equals(800));
      // 诊断值：历史最大表显仍是回拨前的 10500
      expect(RefuelProvider.maxMileageOf(records), equals(10500));
    });

    test('误录高里程后修正：当前表显取修正值', () {
      final records = [
        rec('a', DateTime(2026, 3, 1), 10000),
        // 误录
        rec('b', DateTime(2026, 3, 10), 15000),
        // 修正为正确值
        rec('c', DateTime(2026, 3, 10, 12), 10300),
      ];
      expect(RefuelProvider.latestMileageOf(records), equals(10300));
      expect(RefuelProvider.maxMileageOf(records), equals(15000));
    });

    test('同一时间多条记录：取列表中靠后的稳定顺序', () {
      final records = [
        rec('a', DateTime(2026, 4, 1), 10000),
        rec('b', DateTime(2026, 4, 10), 10200),
        rec('c', DateTime(2026, 4, 10), 10100),
      ];
      // 时间相同（4/10）时按列表顺序取最后一条，结果确定
      expect(RefuelProvider.latestMileageOf(records), equals(10100));
    });
  });

  group('maxMileageOf（历史最大表显）', () {
    test('空记录返回 0', () {
      expect(RefuelProvider.maxMileageOf(const []), equals(0.0));
    });

    test('返回全部记录中的最大值，与时间顺序无关', () {
      final records = [
        rec('a', DateTime(2026, 8, 20), 10500),
        rec('b', DateTime(2026, 8, 1), 12000),
      ];
      expect(RefuelProvider.maxMileageOf(records), equals(12000));
    });
  });
}
