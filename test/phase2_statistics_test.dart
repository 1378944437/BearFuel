import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/data/models/weather_snapshot_model.dart';
import 'package:bearfuel/domain/statistics_service.dart';
import 'package:bearfuel/core/utils/historical_data_policy.dart';

void main() {
  group('第二阶段高级分析与可视化测试 (Phase 2 Statistics Tests)', () {
    final sampleRecords = <RefuelRecordModel>[
      RefuelRecordModel(
        id: 'r1',
        vehicleId: 'v1',
        refuelDate: DateTime(2026, 4, 10), // 春季
        mileage: 10000,
        fuelAmount: 40.0,
        unitPrice: 7.5,
        totalPrice: 300.0,
        gasStation: '中石化阳光站',
        fuelType: '92#',
        isFullTank: true,
        distance: 600.0,
        fuelConsumption: 6.67,
        costPerKm: 0.50,
      ),
      RefuelRecordModel(
        id: 'r2',
        vehicleId: 'v1',
        refuelDate: DateTime(2026, 7, 20), // 夏季 (偏高异常)
        mileage: 10500,
        fuelAmount: 48.0,
        unitPrice: 7.6,
        totalPrice: 364.8,
        gasStation: '中石油示范站',
        fuelType: '92#',
        isFullTank: true,
        distance: 500.0,
        fuelConsumption: 9.60,
        costPerKm: 0.73,
      ),
      RefuelRecordModel(
        id: 'r3',
        vehicleId: 'v1',
        refuelDate: DateTime(2026, 10, 5), // 秋季 (黄金节油)
        mileage: 11200,
        fuelAmount: 35.0,
        unitPrice: 7.4,
        totalPrice: 259.0,
        gasStation: '壳牌高新站',
        fuelType: '92#',
        isFullTank: true,
        distance: 700.0,
        fuelConsumption: 5.00,
        costPerKm: 0.37,
      ),
      RefuelRecordModel(
        id: 'r4',
        vehicleId: 'v1',
        refuelDate: DateTime(2026, 10, 25), // 秋季
        mileage: 11800,
        fuelAmount: 38.0,
        unitPrice: 7.4,
        totalPrice: 281.2,
        gasStation: '中石化阳光站',
        fuelType: '92#',
        isFullTank: true,
        distance: 600.0,
        fuelConsumption: 6.33,
        costPerKm: 0.47,
      ),
    ];

    test('1. 365天热力日历数据构造测试 (get365DayActivityHeatmap)', () {
      final summary = StatisticsService.get365DayActivityHeatmap(
        sampleRecords,
        [],
        year: 2026,
      );

      expect(summary.year, 2026);
      expect(summary.cells.length, 365);
      expect(summary.activeDays, greaterThanOrEqualTo(3));
      // 相邻差口径：首条记录无前序基准不计入，总计 = 500+700+600
      expect(summary.totalYearMileage, 1800.0);
      expect(summary.maxDailyMileage, 700.0);
      expect(summary.activeRate, greaterThan(0.0));
    });

    test('2. 每公里花费走势图测试 (getCostPerKmTrend)', () {
      final trend = StatisticsService.getCostPerKmTrend(sampleRecords);
      expect(trend.length, 4);
      expect(trend.first.value, 0.50);
      expect(trend[1].value, 0.73);
    });

    test('3. 气温与能耗只使用真实天气快照测试', () {
      final snapshots = [
        WeatherSnapshotModel(
          cityKey: '1007',
          cityName: '荆门市',
          snapshotDate: DateTime(2026, 4, 10),
          tempHigh: 25,
          tempLow: 15,
          source: 'test',
          fetchedAt: DateTime(2026, 4, 11),
        ),
        WeatherSnapshotModel(
          cityKey: '1007',
          cityName: '荆门市',
          snapshotDate: DateTime(2026, 7, 20),
          tempHigh: 36,
          tempLow: 26,
          source: 'test',
          fetchedAt: DateTime(2026, 7, 21),
        ),
        WeatherSnapshotModel(
          cityKey: '1007',
          cityName: '荆门市',
          snapshotDate: DateTime(2026, 7, 21),
          temperature: 33,
          tempHigh: 38,
          tempLow: 28,
          source: 'test',
          fetchedAt: DateTime(2026, 7, 22),
        ),
      ];

      final points = StatisticsService.getTemperatureVsConsumptionFromSnapshots(
        sampleRecords,
        snapshots,
      );

      expect(points.length, 2);
      expect(points.first.monthLabel, '4月');
      expect(points.first.estimatedTemperature, 20.0);
      expect(points.first.avgConsumption, 6.67);
      expect(points.last.monthLabel, '7月');
      expect(points.last.estimatedTemperature, 32.0);
      expect(points.last.avgConsumption, 9.60);
    });

    test('5. 历史数据窗口根据样本量选择粒度测试', () {
      final sparse = HistoricalDataWindow.fromDates([
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 20),
      ]);
      expect(sparse.granularity, HistoryGranularity.day);

      final dense = HistoricalDataWindow.fromDates(
        List.generate(200, (index) => DateTime(2025, 1, 1 + index)),
      );
      expect(dense.granularity, HistoryGranularity.month);
    });
  });
}
