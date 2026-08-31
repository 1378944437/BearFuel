import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/domain/fuel_cycle.dart';

/// 阶段二：完整周期模型的基础回归。
///
/// 统计口径正确性的前提是先有可追溯的周期，这些用例固定周期的行为。
void main() {
  RefuelRecordModel rec(
    DateTime date,
    double mileage,
    double liters, {
    bool full = true,
    bool forgot = false,
    double unitPrice = 8.0,
  }) {
    return RefuelRecordModel(
      id: 'r_${date.millisecondsSinceEpoch}_$mileage',
      vehicleId: 'veh',
      refuelDate: date,
      mileage: mileage,
      fuelAmount: liters,
      unitPrice: unitPrice,
      totalPrice: liters * unitPrice,
      fuelType: '92#',
      isFullTank: full,
      isForgotPrevious: forgot,
    );
  }

  group('周期构建', () {
    test('连续两次加满构成一个完整周期', () {
      final cycles = FuelCycleBuilder.build([
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 20), 10500, 45),
      ]);

      expect(cycles.length, equals(1));
      final c = cycles.single;
      expect(c.isClosed, isTrue);
      expect(c.distance, equals(500));
      expect(c.fuelAmount, equals(45));
      expect(c.cost, equals(360));
      expect(c.consumption, closeTo(9.0, 0.001));
      expect(c.costPerKm, closeTo(0.72, 0.001));
      expect(c.isReliable, isTrue);
    });

    test('未加满记录的油量归入下一个加满周期', () {
      final cycles = FuelCycleBuilder.build([
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10200, 20, full: false),
        rec(DateTime(2026, 1, 20), 10500, 25),
      ]);

      expect(cycles.length, equals(1));
      final c = cycles.single;
      expect(c.distance, equals(500));
      // 20 L（未加满）+ 25 L（结束加满）
      expect(c.fuelAmount, equals(45));
      expect(c.consumption, closeTo(9.0, 0.001));
    });

    test('未闭合尾周期不给出平均油耗', () {
      final cycles = FuelCycleBuilder.build([
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10200, 20, full: false),
      ]);

      expect(cycles.length, equals(1));
      final c = cycles.single;
      expect(c.isClosed, isFalse);
      expect(c.consumption, isNull);
      expect(c.costPerKm, isNull);
      expect(c.isReliable, isFalse);
    });

    test('漏记记录作为断点，之前未闭合的量不归属新周期', () {
      final cycles = FuelCycleBuilder.build([
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10200, 30, forgot: true),
        rec(DateTime(2026, 1, 20), 10500, 45),
      ]);

      expect(cycles.length, equals(1));
      final c = cycles.single;
      // 周期从漏记记录重新开始
      expect(c.startMileage, equals(10200));
      expect(c.distance, equals(300));
      expect(c.fuelAmount, equals(45));
    });
  });

  group('里程回拨 (P1-06)', () {
    List<FuelCycle> rollbackCycles() => FuelCycleBuilder.build([
      rec(DateTime(2026, 1, 1), 10000, 40),
      rec(DateTime(2026, 1, 10), 10500, 45),
      rec(DateTime(2026, 1, 20), 9000, 40),
      rec(DateTime(2026, 1, 30), 9500, 45),
    ]);

    test('回拨段被标记为不可信且距离归零', () {
      final cycles = rollbackCycles();
      final broken = cycles.where(
        (c) => c.continuity == MileageContinuity.rollback,
      );
      expect(broken.length, equals(1));
      expect(broken.single.isReliable, isFalse);
      expect(broken.single.distance, equals(0));
      expect(broken.single.consumption, isNull);
    });

    test('回拨之后的周期从新基准重新开始', () {
      final cycles = rollbackCycles();
      final healthy = cycles.where((c) => c.isReliable).toList();
      expect(healthy.length, equals(2));
      expect(healthy[0].startMileage, equals(10000));
      expect(healthy[0].endMileage, equals(10500));
      expect(healthy[1].startMileage, equals(9000));
      expect(healthy[1].endMileage, equals(9500));
      expect(healthy[1].distance, equals(500));
    });

    test('回拨不影响未受影响的周期油耗', () {
      final cycles = rollbackCycles();
      final healthy = cycles.where((c) => c.isReliable).toList();
      expect(healthy[0].consumption, closeTo(9.0, 0.001));
      expect(healthy[1].consumption, closeTo(9.0, 0.001));
    });

    test('findMileageBreaks 定位回拨位置', () {
      final records = [
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10500, 45),
        rec(DateTime(2026, 1, 20), 9000, 40),
      ];
      final breaks = FuelCycleBuilder.findMileageBreaks(records);
      expect(breaks.length, equals(1));
      expect(breaks.single.currentIndex, equals(2));
    });
  });

  group('按里程切分 (P1-03 基础)', () {
    FuelCycle spanningCycle() => FuelCycleBuilder.build([
      rec(DateTime(2026, 1, 1), 9500, 40),
      rec(DateTime(2026, 1, 20), 10500, 50),
    ]).single;

    test('跨万公里边界的周期按比例切分且总量守恒', () {
      final cycle = spanningCycle();
      expect(cycle.distance, equals(1000));
      expect(cycle.fuelAmount, equals(50));

      final lower = cycle.sliceByMileage(0, 10000);
      final upper = cycle.sliceByMileage(10000, 20000);

      expect(lower.distance, closeTo(500, 0.001));
      expect(upper.distance, closeTo(500, 0.001));
      expect(lower.fuelAmount, closeTo(25, 0.001));
      expect(upper.fuelAmount, closeTo(25, 0.001));

      final total = lower + upper;
      expect(total.distance, closeTo(cycle.distance, 0.001));
      expect(total.fuelAmount, closeTo(cycle.fuelAmount, 0.001));
      expect(total.cost, closeTo(cycle.cost, 0.001));
    });

    test('不相交的区间返回空份额', () {
      final cycle = spanningCycle();
      final slice = cycle.sliceByMileage(30000, 40000);
      expect(slice.distance, equals(0));
      expect(slice.fuelAmount, equals(0));
    });
  });

  group('周期与统计范围的关系 (P1-01/P1-02 基础)', () {
    FuelCycle cycle() => FuelCycleBuilder.build([
      rec(DateTime(2026, 1, 31), 10000, 40),
      rec(DateTime(2026, 2, 10), 10500, 45),
    ]).single;

    test('完整落在范围内才算包含', () {
      final c = cycle();
      // 周期跨越 1 月末到 2 月 10 日
      expect(
        c.isContainedIn(DateTime(2026, 2, 1), DateTime(2026, 3, 1)),
        isFalse,
      );
      expect(
        c.isContainedIn(DateTime(2026, 1, 1), DateTime(2026, 3, 1)),
        isTrue,
      );
    });

    test('与范围相交但不完整时 intersects 为真', () {
      final c = cycle();
      expect(
        c.intersectsRange(DateTime(2026, 2, 1), DateTime(2026, 3, 1)),
        isTrue,
      );
      expect(
        c.intersectsRange(DateTime(2026, 3, 1), DateTime(2026, 4, 1)),
        isFalse,
      );
    });
  });
}
