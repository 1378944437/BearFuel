import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/domain/statistics_service.dart';

/// P1-02 回归：统计范围不得截断完整油耗周期。
///
/// 范围统计拆成两套口径——交易口径按过滤后记录求和（调用方职责），
/// 完整周期口径只有完整包含在范围内的可信周期才参与，
/// 边界相交周期仅计数提示"边界未闭合"。
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

  // 计划文档 8.3 的标准场景：
  // 1/31 加满（周期起点在 1 月），2/1 未加满，2/10 加满闭合。
  // 整个完整周期为 1/31 → 2/10，跨越了 1 月/2 月边界。
  final crossBoundaryRecords = [
    rec(DateTime(2026, 1, 31), 10000, 30),
    rec(DateTime(2026, 2, 1), 10200, 20, full: false),
    rec(DateTime(2026, 2, 10), 10700, 30),
  ];

  group('范围完整周期统计 (getRangeCycleStats)', () {
    test('2 月范围不得把 1/31 起始的跨月周期伪装成 2 月周期', () {
      final stats = StatisticsService.getRangeCycleStats(
        allRecords: crossBoundaryRecords,
        startInclusive: DateTime(2026, 2, 1),
        endExclusive: DateTime(2026, 3, 1),
      );

      // 周期 1/31→2/10 起点在 1 月：不算 2 月的完整周期
      expect(stats.cycleCount, equals(0));
      expect(stats.hasCycles, isFalse);
      // 但必须被识别为边界未闭合，而不是静默消失
      expect(stats.boundaryCycleCount, equals(1));
      expect(stats.distance, equals(0));
      expect(stats.avgConsumption, isNull);
      expect(stats.costPerKm, isNull);
    });

    test('包含完整周期的范围正常统计且可对账', () {
      final stats = StatisticsService.getRangeCycleStats(
        allRecords: crossBoundaryRecords,
        startInclusive: DateTime(2026, 1, 1),
        endExclusive: DateTime(2026, 3, 1),
      );

      expect(stats.cycleCount, equals(1));
      expect(stats.boundaryCycleCount, equals(0));
      expect(stats.distance, closeTo(700, 0.001));
      // 20 L（未加满）+ 30 L（结束加满）
      expect(stats.fuelAmount, closeTo(50, 0.001));
      // 50 L × ¥8 = ¥400
      expect(stats.cost, closeTo(400, 0.001));
      expect(stats.avgConsumption, closeTo(50 / 700 * 100, 0.001));
      expect(stats.costPerKm, closeTo(400 / 700, 0.001));
    });

    test('周期必须完整包含：结束点落在范围外时只算边界', () {
      // 范围 1/1 ~ 2/5：周期 1/31→2/10 结束点在范围外
      final stats = StatisticsService.getRangeCycleStats(
        allRecords: crossBoundaryRecords,
        startInclusive: DateTime(2026, 1, 1),
        endExclusive: DateTime(2026, 2, 6),
      );

      expect(stats.cycleCount, equals(0));
      expect(stats.boundaryCycleCount, equals(1));
      expect(stats.avgConsumption, isNull);
    });

    test('不传范围时统计全部可信周期', () {
      final stats = StatisticsService.getRangeCycleStats(
        allRecords: crossBoundaryRecords,
      );

      expect(stats.cycleCount, equals(1));
      expect(stats.boundaryCycleCount, equals(0));
      expect(stats.distance, closeTo(700, 0.001));
    });

    test('跨年周期归属：今年范围不包含去年起始的周期', () {
      final records = [
        rec(DateTime(2025, 12, 20), 20000, 40),
        rec(DateTime(2026, 1, 10), 20600, 42),
      ];

      final stats2026 = StatisticsService.getRangeCycleStats(
        allRecords: records,
        startInclusive: DateTime(2026, 1, 1),
        endExclusive: DateTime(2027, 1, 1),
      );

      expect(stats2026.cycleCount, equals(0));
      expect(stats2026.boundaryCycleCount, equals(1));
      expect(stats2026.avgConsumption, isNull);

      final statsAll = StatisticsService.getRangeCycleStats(
        allRecords: records,
      );
      expect(statsAll.cycleCount, equals(1));
      expect(statsAll.distance, closeTo(600, 0.001));
    });

    test('跨回拨周期不可信，回拨后新基准周期正常统计', () {
      final records = [
        rec(DateTime(2026, 2, 1), 10000, 40),
        // 2/20 表显从 10500 回拨到 9800：跨越该回拨点的周期不可信
        rec(DateTime(2026, 2, 10), 10500, 45),
        rec(DateTime(2026, 2, 20), 9800, 40),
        rec(DateTime(2026, 2, 28), 10400, 42),
      ];

      final stats = StatisticsService.getRangeCycleStats(
        allRecords: records,
        startInclusive: DateTime(2026, 2, 1),
        endExclusive: DateTime(2026, 3, 1),
      );

      // 可信周期只有 2/1→2/10 与 2/20→2/28（回拨后新基准）；
      // 跨回拨的 2/10→2/20 周期被排除，其负向里程差不得计入。
      expect(stats.cycleCount, equals(2));
      expect(stats.boundaryCycleCount, equals(0));
      expect(stats.distance, closeTo(500 + 600, 0.001));
      expect(stats.fuelAmount, closeTo(45 + 42, 0.001));
    });

    test('未闭合尾周期不参与范围统计', () {
      final records = [
        rec(DateTime(2026, 2, 1), 10000, 40),
        rec(DateTime(2026, 2, 15), 10500, 20, full: false),
      ];

      final stats = StatisticsService.getRangeCycleStats(
        allRecords: records,
        startInclusive: DateTime(2026, 2, 1),
        endExclusive: DateTime(2026, 3, 1),
      );

      expect(stats.cycleCount, equals(0));
      expect(stats.avgConsumption, isNull);
    });

    test('空记录返回零值且不给出平均油耗', () {
      final stats = StatisticsService.getRangeCycleStats(
        allRecords: const [],
        startInclusive: DateTime(2026, 2, 1),
        endExclusive: DateTime(2026, 3, 1),
      );

      expect(stats.cycleCount, equals(0));
      expect(stats.hasCycles, isFalse);
      expect(stats.avgConsumption, isNull);
      expect(stats.costPerKm, isNull);
    });
  });
}
