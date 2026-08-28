import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/domain/fuel_calculator.dart';

void main() {
  group('小熊油耗核心计算引擎测试 (FuelCalculator Tests)', () {
    test('1. 连续加满场景：应精确计算每次百公里油耗与每公里花费', () {
      final records = [
        RefuelRecordModel(
          id: '1',
          vehicleId: 'v1',
          refuelDate: DateTime(2026, 1, 1),
          mileage: 10000.0,
          fuelAmount: 50.0,
          unitPrice: 8.0,
          totalPrice: 400.0,
          fuelType: '92# 汽油',
          isFullTank: true,
        ),
        RefuelRecordModel(
          id: '2',
          vehicleId: 'v1',
          refuelDate: DateTime(2026, 1, 10),
          mileage: 10500.0, // 行驶 500 km
          fuelAmount: 40.0, // 加满 40 L
          unitPrice: 8.0,
          totalPrice: 320.0,
          fuelType: '92# 汽油',
          isFullTank: true,
        ),
        RefuelRecordModel(
          id: '3',
          vehicleId: 'v1',
          refuelDate: DateTime(2026, 1, 20),
          mileage: 11100.0, // 行驶 600 km
          fuelAmount: 45.0, // 加满 45 L
          unitPrice: 8.0,
          totalPrice: 360.0,
          fuelType: '92# 汽油',
          isFullTank: true,
        ),
      ];

      final result = FuelCalculator.computeRecords(records);

      // 第一条作为基准首充，无前序油耗
      expect(result[0].fuelConsumption, isNull);
      expect(result[0].costPerKm, isNull);

      // 第二条：40 L / 500 km * 100 = 8.00 L/100km, 花费 320 / 500 = 0.64 ¥/km
      expect(result[1].fuelConsumption, equals(8.00));
      expect(result[1].costPerKm, equals(0.64));
      expect(result[1].distance, equals(500.0));

      // 第三条：45 L / 600 km * 100 = 7.50 L/100km, 花费 360 / 600 = 0.60 ¥/km
      expect(result[2].fuelConsumption, equals(7.50));
      expect(result[2].costPerKm, equals(0.60));
      expect(result[2].distance, equals(600.0));

      // 汇总统计测试
      final summary = FuelCalculator.calculateSummary(result);
      // 总有效里程 = 500 + 600 = 1100 km, 总耗油 = 40 + 45 = 85 L
      // 平均油耗 = (85 / 1100) * 100 ≈ 7.73 L/100km
      expect(summary.averageConsumption, equals(7.73));
      expect(summary.bestConsumption, equals(7.50));
      expect(summary.worstConsumption, equals(8.00));
      expect(summary.validCalculatedCount, equals(2));
    });

    test('2. 中间包含未加满场景：应自动累计油量并在下次加满时平摊计算', () {
      final records = [
        RefuelRecordModel(
          id: '1',
          vehicleId: 'v1',
          refuelDate: DateTime(2026, 2, 1),
          mileage: 20000.0,
          fuelAmount: 50.0,
          unitPrice: 8.0,
          totalPrice: 400.0,
          fuelType: '92# 汽油',
          isFullTank: true, // 基准加满
        ),
        RefuelRecordModel(
          id: '2',
          vehicleId: 'v1',
          refuelDate: DateTime(2026, 2, 5),
          mileage: 20300.0,
          fuelAmount: 20.0,
          unitPrice: 8.0,
          totalPrice: 160.0,
          fuelType: '92# 汽油',
          isFullTank: false, // 未加满
        ),
        RefuelRecordModel(
          id: '3',
          vehicleId: 'v1',
          refuelDate: DateTime(2026, 2, 12),
          mileage: 20700.0, // 距上次加满累计 700 km
          fuelAmount: 30.0, // 本次加满
          unitPrice: 8.0,
          totalPrice: 240.0,
          fuelType: '92# 汽油',
          isFullTank: true,
        ),
      ];

      final result = FuelCalculator.computeRecords(records);

      // 第一条：基准
      expect(result[0].fuelConsumption, isNull);

      // 第二条：未加满，不单独输出百公里油耗
      expect(result[1].fuelConsumption, isNull);

      // 第三条：加满，合并计算：(20 + 30) L / 700 km * 100 = 50 / 700 * 100 ≈ 7.14 L/100km
      // 总花费 = 160 + 240 = 400 元, 每公里花费 = 400 / 700 ≈ 0.57 ¥/km
      expect(result[2].fuelConsumption, equals(7.14));
      expect(result[2].costPerKm, equals(0.57));
      expect(result[2].distance, equals(700.0));
    });

    test('3. 漏记场景：开启漏记标记后应断开前序关联，作为新基准', () {
      final records = [
        RefuelRecordModel(
          id: '1',
          vehicleId: 'v1',
          refuelDate: DateTime(2026, 3, 1),
          mileage: 30000.0,
          fuelAmount: 50.0,
          unitPrice: 8.0,
          totalPrice: 400.0,
          fuelType: '92# 汽油',
          isFullTank: true,
        ),
        RefuelRecordModel(
          id: '2',
          vehicleId: 'v1',
          refuelDate: DateTime(2026, 3, 15),
          mileage: 31500.0,
          fuelAmount: 48.0,
          unitPrice: 8.0,
          totalPrice: 384.0,
          fuelType: '92# 汽油',
          isFullTank: true,
          isForgotPrevious: true, // 标记漏记了中间某次
        ),
        RefuelRecordModel(
          id: '3',
          vehicleId: 'v1',
          refuelDate: DateTime(2026, 3, 22),
          mileage: 32000.0, // 距上次 500 km
          fuelAmount: 35.0,
          unitPrice: 8.0,
          totalPrice: 280.0,
          fuelType: '92# 汽油',
          isFullTank: true,
        ),
      ];

      final result = FuelCalculator.computeRecords(records);

      // 第一条：基准
      expect(result[0].fuelConsumption, isNull);

      // 第二条：因为标记漏记，不与第 1 条计算油耗
      expect(result[1].fuelConsumption, isNull);

      // 第三条：以第 2 条为新基准计算：35 L / 500 km * 100 = 7.00 L/100km
      expect(result[2].fuelConsumption, equals(7.00));
      expect(result[2].costPerKm, equals(0.56));
      expect(result[2].distance, equals(500.0));
    });
  });
}
