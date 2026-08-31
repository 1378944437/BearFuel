import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/domain/bear_fuel_importer.dart';
import 'package:bearfuel/domain/fuel_calculator.dart';
import 'package:bearfuel/domain/statistics_service.dart';

/// P2 阶段四整改回归：
/// - P2-07 成本分母不稀释；
/// - P2-11 累计平均油耗先过滤异常值；
/// - P2-05 布尔告警文案与实际默认值一致。
void main() {
  RefuelRecordModel rec({
    required String id,
    required DateTime date,
    required double mileage,
    required double distance,
    double? fuelConsumption,
    double? costPerKm,
    double fuelAmount = 40,
    double totalPrice = 300,
  }) {
    return RefuelRecordModel(
      id: id,
      vehicleId: 'veh',
      refuelDate: date,
      mileage: mileage,
      fuelAmount: fuelAmount,
      unitPrice: 7.5,
      totalPrice: totalPrice,
      fuelType: '92#',
      isFullTank: true,
      fuelConsumption: fuelConsumption,
      costPerKm: costPerKm,
      distance: distance,
    );
  }

  group('P2-07 派生字段缺失时不得按 0 成本计算', () {
    test('缺少 costPerKm 的距离不进入成本分母', () {
      // 300 km 成本 0.50/km；400 km 缺失成本
      final summary = FuelCalculator.calculateSummary([
        rec(
          id: 'a',
          date: DateTime(2026, 1, 1),
          mileage: 10000,
          distance: 300,
          fuelConsumption: 8.0,
          costPerKm: 0.50,
        ),
        rec(
          id: 'b',
          date: DateTime(2026, 1, 10),
          mileage: 10700,
          distance: 400,
          fuelConsumption: 8.0,
          // costPerKm 缺失（旧备份/损坏数据）
        ),
      ]);

      // 分母只有 300 km，而不是 700 km
      expect(summary.averageCostPerKm, closeTo(0.50, 0.001));
    });

    test('全部缺失时每公里成本为 0 而不是 NaN', () {
      final summary = FuelCalculator.calculateSummary([
        rec(
          id: 'a',
          date: DateTime(2026, 1, 1),
          mileage: 10000,
          distance: 300,
          fuelConsumption: 8.0,
        ),
      ]);
      expect(summary.averageCostPerKm, equals(0.0));
    });
  });

  group('P2-11 累计平均油耗图异常值处理', () {
    test('单条异常油耗在进入累计前被排除', () {
      final points = StatisticsService.getMovingAverageEvolutionTrend([
        rec(
          id: 'a',
          date: DateTime(2026, 1, 1),
          mileage: 10000,
          distance: 500,
          fuelConsumption: 8.0,
        ),
        // 异常：50 L/100km（派生字段损坏），不得污染累计值
        rec(
          id: 'b',
          date: DateTime(2026, 1, 10),
          mileage: 10500,
          distance: 500,
          fuelConsumption: 50.0,
        ),
        rec(
          id: 'c',
          date: DateTime(2026, 1, 20),
          mileage: 11000,
          distance: 500,
          fuelConsumption: 8.0,
        ),
      ]);

      // 若异常值混入累计：最后一点约为 (500*8 + 500*50 + 500*8)/1500 = 22
      // 排除异常后：最后一点应为 8.0
      expect(points, isNotEmpty);
      expect(points.last.value, closeTo(8.0, 0.01));
    });

    test('异常阈值常量已定义且与展示过滤一致', () {
      expect(StatisticsService.anomalyConsumptionLimit, equals(30.0));
    });
  });

  group('P2-05 布尔告警文案与实际默认值一致', () {
    test('加满字段无法识别时文案应说明按"是"处理', () {
      const warning = ImportWarning(
        line: 3,
        kind: ImportWarningKind.unknownBoolean,
        field: '是否加满',
        rawValue: 'maybe',
        defaultValue: '是',
      );
      expect(warning.description, contains('已按"是"处理'));
    });

    test('漏记字段无法识别时文案应说明按"否"处理', () {
      const warning = ImportWarning(
        line: 4,
        kind: ImportWarningKind.unknownBoolean,
        field: '是否漏记',
        rawValue: '???',
        defaultValue: '否',
      );
      expect(warning.description, contains('已按"否"处理'));
    });
  });
}
