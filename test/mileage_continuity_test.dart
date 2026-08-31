import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/domain/fuel_calculator.dart';
import 'package:bearfuel/domain/fuel_cycle.dart';

/// P1-06 回归：里程回拨、换表与跨段正差的隔断。
///
/// - 未确认的回拨：分段累计、跨越回拨的周期不可信；
/// - 用户确认换表/新基准（isOdometerReset）：显式断点，其后周期正常；
/// - 漏记：里程差仍真实，不切断里程段。
void main() {
  RefuelRecordModel rec(
    DateTime date,
    double mileage,
    double liters, {
    bool full = true,
    bool forgot = false,
    bool odometerReset = false,
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
      isOdometerReset: odometerReset,
    );
  }

  group('analyzeMileageSegments（里程分段）', () {
    test('无回拨时只有一段，总量等于正差之和', () {
      final report = FuelCycleBuilder.analyzeMileageSegments([
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10500, 45),
        rec(DateTime(2026, 1, 20), 11100, 40),
      ]);

      expect(report.segments.length, equals(1));
      expect(report.hasBreaks, isFalse);
      expect(report.totalDistance, closeTo(1100, 0.001));
    });

    test('回拨处切段，后续记录从新基准开始，各段可对账', () {
      final report = FuelCycleBuilder.analyzeMileageSegments([
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10500, 45),
        // 换表：表显降到 300
        rec(DateTime(2026, 2, 1), 300, 40),
        rec(DateTime(2026, 2, 10), 800, 40),
      ]);

      expect(report.hasBreaks, isTrue);
      expect(report.breaks.single.kind, equals(MileageContinuity.rollback));
      expect(report.segments.length, equals(2));

      // 段 1：10000→10500 = 500；段 2：300→800 = 500（新基准）
      expect(report.segments[0].distance, closeTo(500, 0.001));
      expect(report.segments[1].distance, closeTo(500, 0.001));
      // 负差（10500→300）不计入
      expect(report.totalDistance, closeTo(1000, 0.001));
    });

    test('用户确认换表：显式断点且分段', () {
      final report = FuelCycleBuilder.analyzeMileageSegments([
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10500, 45),
        rec(DateTime(2026, 2, 1), 300, 40, odometerReset: true),
        rec(DateTime(2026, 2, 10), 800, 40),
      ]);

      expect(
        report.breaks.single.kind,
        equals(MileageContinuity.odometerReset),
      );
      expect(report.segments.length, equals(2));
      expect(report.totalDistance, closeTo(1000, 0.001));
    });

    test('漏记不切断里程段：两次已知表显之差仍真实', () {
      final report = FuelCycleBuilder.analyzeMileageSegments([
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10500, 45),
        rec(DateTime(2026, 1, 20), 11000, 40, forgot: true),
        rec(DateTime(2026, 1, 30), 11400, 40),
      ]);

      expect(report.hasBreaks, isFalse);
      expect(report.segments.length, equals(1));
      expect(report.totalDistance, closeTo(1400, 0.001));
    });

    test('空记录返回空报告', () {
      final report = FuelCycleBuilder.analyzeMileageSegments(const []);
      expect(report.segments, isEmpty);
      expect(report.breaks, isEmpty);
      expect(report.totalDistance, equals(0));
    });
  });

  group('周期构建对换表确认的处理', () {
    test('周期不跨越用户确认的换表点，其后周期可信', () {
      final cycles = FuelCycleBuilder.build([
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10500, 45),
        // 换表确认：此前的未闭合量不再归属，从本条重新起算
        rec(DateTime(2026, 2, 1), 300, 40, odometerReset: true),
        rec(DateTime(2026, 2, 10), 800, 42),
      ]);

      // 周期 1：10000→10500（正常）
      expect(cycles[0].isClosed, isTrue);
      expect(cycles[0].isReliable, isTrue);
      expect(cycles[0].distance, closeTo(500, 0.001));

      // 换表点 2/1 为未闭合尾周期（不可信），2/1→2/10 从新基准闭合
      final last = cycles.last;
      expect(last.startMileage, equals(300));
      expect(last.isClosed, isTrue);
      expect(last.isReliable, isTrue);
      expect(last.distance, closeTo(500, 0.001));
    });
  });

  group('FuelCalculator.computeRecords 的回拨隔断', () {
    test('跨越回拨的记录不计算油耗，后续从新基准计算', () {
      final records = [
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10500, 45),
        // 回拨：此条跨越断点，派生值必须为空
        rec(DateTime(2026, 1, 20), 10200, 42),
        rec(DateTime(2026, 1, 30), 10700, 40),
      ];

      FuelCalculator.computeRecords(records);

      // 1/10：正常周期 10000→10500
      expect(records[1].fuelConsumption, isNotNull);
      // 1/20：回拨点，不得给出看似精确的油耗
      expect(records[2].fuelConsumption, isNull);
      expect(records[2].costPerKm, isNull);
      // 1/30：从新基准 10200 起算 → 500km
      expect(records[3].distance, closeTo(500, 0.001));
      expect(records[3].fuelConsumption, isNotNull);
      // 新周期油量只有 40L（回拨前的 42L 不再归属）
      expect(records[3].fuelConsumption, closeTo(40 / 500 * 100, 0.01));
    });

    test('回拨发生在未加满记录时：待闭合累计被清空，下一次加满仅作为新起点', () {
      final records = [
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10500, 20, full: false),
        // 回拨到 10300（未加满）
        rec(DateTime(2026, 1, 15), 10300, 15, full: false),
        rec(DateTime(2026, 1, 25), 10900, 30),
      ];

      FuelCalculator.computeRecords(records);

      // 回拨点（未加满）自身无法归属
      expect(records[2].fuelConsumption, isNull);
      // 回拨后第一次加满只开启新基准周期，尚无闭合记录，
      // 不得把回拨前未闭合的 20L 混入任何计算
      expect(records[3].fuelConsumption, isNull);
      expect(records[3].costPerKm, isNull);

      // 再加满一次后才从新基准闭合：10300 → 11400，油量 25L
      records.add(rec(DateTime(2026, 2, 5), 11400, 25));
      FuelCalculator.computeRecords(records);
      expect(records[4].distance, closeTo(500, 0.001));
      expect(records[4].fuelConsumption, closeTo(25 / 500 * 100, 0.01));
    });

    test('用户确认换表的记录作为新基准', () {
      final records = [
        rec(DateTime(2026, 1, 1), 10000, 40),
        rec(DateTime(2026, 1, 10), 10500, 45),
        // 换表确认：表显 300
        rec(DateTime(2026, 2, 1), 300, 40, odometerReset: true),
        rec(DateTime(2026, 2, 10), 800, 42),
      ];

      FuelCalculator.computeRecords(records);

      // 换表记录本身是断点，不产生油耗
      expect(records[2].fuelConsumption, isNull);
      // 2/10 从新基准 300 起算
      expect(records[3].distance, closeTo(500, 0.001));
      expect(records[3].fuelConsumption, closeTo(42 / 500 * 100, 0.01));
    });
  });
}
