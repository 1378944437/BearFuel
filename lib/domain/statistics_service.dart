import 'dart:math' as math;
import '../data/models/refuel_record_model.dart';
import '../data/models/expense_record_model.dart';
import '../data/models/weather_snapshot_model.dart';
import '../../core/utils/date_formatter.dart';
import 'fuel_calculator.dart';

/// 异常点智能诊断模型
class AnomalyDiagnosticItem {
  final String recordId;
  final DateTime date;
  final double consumption;
  final double baselineConsumption;
  final double deviation;
  final double deviationPercent;
  final bool isHigh;
  final String station;
  final String reason;
  final String suggestion;

  AnomalyDiagnosticItem({
    required this.recordId,
    required this.date,
    required this.consumption,
    required this.baselineConsumption,
    required this.deviation,
    required this.deviationPercent,
    required this.isHigh,
    required this.station,
    required this.reason,
    required this.suggestion,
  });
}

/// 365天行驶热力日历单日格子模型
class DailyActivityCell {
  final DateTime date;
  final int weekday; // 1 (Mon) to 7 (Sun)
  final double mileage;
  final double fuelAmount;
  final double totalExpense;
  final int intensityLevel; // 0 to 4

  DailyActivityCell({
    required this.date,
    required this.weekday,
    required this.mileage,
    required this.fuelAmount,
    required this.totalExpense,
    required this.intensityLevel,
  });
}

/// 全年出车热力日历统计汇总
class YearlyHeatmapSummary {
  final int year;
  final int activeDays;
  final int totalDays;
  final double activeRate;
  final double maxDailyMileage;
  final double totalYearMileage;
  final int maxConsecutiveActiveDays;
  final List<DailyActivityCell> cells;

  YearlyHeatmapSummary({
    required this.year,
    required this.activeDays,
    required this.totalDays,
    required this.activeRate,
    required this.maxDailyMileage,
    required this.totalYearMileage,
    required this.maxConsecutiveActiveDays,
    required this.cells,
  });
}

/// 图表点位数据模型
class ChartDataPoint {
  final String label; // X轴标签 (如 08-01)
  final double value; // Y轴数值
  final DateTime date; // 对应时间
  final String? extra; // 附加提示信息 (如油站名称、单价等)

  ChartDataPoint({
    required this.label,
    required this.value,
    required this.date,
    this.extra,
  });
}

/// 费用类别占比统计数据模型
class ExpenseCategoryShare {
  final String category; // 类别名称
  final double totalAmount; // 该类别总金额
  final double percentage; // 占比 (0~100)

  ExpenseCategoryShare({
    required this.category,
    required this.totalAmount,
    required this.percentage,
  });
}

/// 保养与重要事项到期预警模型
class ReminderItem {
  final String title; // 提醒标题 (如: 基础机油保养)
  final String category; // 类别
  final double? targetMileage; // 目标里程
  final double? remainingMileage; // 剩余里程
  final DateTime? targetDate; // 目标日期
  final int? remainingDays; // 剩余天数
  final bool isOverdue; // 是否已逾期
  final bool isUrgent; // 是否即将到期（<500km 或 <15天）

  ReminderItem({
    required this.title,
    required this.category,
    this.targetMileage,
    this.remainingMileage,
    this.targetDate,
    this.remainingDays,
    this.isOverdue = false,
    this.isUrgent = false,
  });
}

/// 每万公里阶段油耗统计模型（带阶段命名与较上阶段增减）
class TenThousandKmStats {
  final String stageLabel; // 如 "0~1万km"
  final String phaseTitle; // 如 "新车磨合阶段"
  final double avgConsumption; // 该阶段平均百公里油耗
  final double totalDistance; // 该阶段行驶总里程
  final double totalFuel; // 该阶段总耗油量
  final int recordCount; // 该阶段记录数
  final double? diffFromPrevious; // 较上一阶段油耗变化 (负数表示省油，正数表示上升)

  TenThousandKmStats({
    required this.stageLabel,
    required this.phaseTitle,
    required this.avgConsumption,
    required this.totalDistance,
    required this.totalFuel,
    required this.recordCount,
    this.diffFromPrevious,
  });
}

/// 周期多粒度统计数据模型（年度/季度/月度/行程）
class PeriodStatsItem {
  final String label; // 周期标签 (如 "2026年", "2026-Q1", "2026-08月")
  final double mileage; // 行驶里程
  final double fuelAmount; // 消耗油量
  final double fuelCost; // 燃油支出
  final double totalExpense; // 综合总开销 (含其他费用)
  final double avgConsumption; // 平均油耗
  final double costPerKm; // 每公里成本 (¥/km)

  PeriodStatsItem({
    required this.label,
    required this.mileage,
    required this.fuelAmount,
    required this.fuelCost,
    required this.totalExpense,
    required this.avgConsumption,
    required this.costPerKm,
  });
}

/// 温度与能耗对比数据点
class TemperatureVsConsumptionPoint {
  final String monthLabel; // 如 "1月", "2月"
  final double avgConsumption; // 该月平均油耗 (L/100km)
  final double estimatedTemperature; // 该省市地区月均气温 (°C)
  final int refuelCount; // 样本数

  TemperatureVsConsumptionPoint({
    required this.monthLabel,
    required this.avgConsumption,
    required this.estimatedTemperature,
    required this.refuelCount,
  });
}

class _WeightedConsumption {
  double distance = 0;
  double fuel = 0;
  int recordCount = 0;
}

/// 数据统计与报表聚合领域服务
class StatisticsService {
  /// 1. 生成单次百公里油耗变动趋势点序列
  static List<ChartDataPoint> getConsumptionTrend(
    List<RefuelRecordModel> records,
  ) {
    final validRecords =
        records
            .where((r) => r.fuelConsumption != null && r.fuelConsumption! > 0)
            .toList()
          ..sort((a, b) => a.refuelDate.compareTo(b.refuelDate));

    return validRecords.map((r) {
      return ChartDataPoint(
        label: DateFormatter.formatMonthDay(r.refuelDate),
        value: r.fuelConsumption!,
        date: r.refuelDate,
        extra: '${r.gasStation ?? "加油站"} · ¥${r.unitPrice}/L',
      );
    }).toList();
  }

  /// 2. 生成累计平均油耗演进过程曲线 (Evolution Curve - 平滑收敛线)
  static List<ChartDataPoint> getMovingAverageEvolutionTrend(
    List<RefuelRecordModel> records,
  ) {
    final sorted = List<RefuelRecordModel>.from(records)
      ..sort((a, b) => a.refuelDate.compareTo(b.refuelDate));

    final List<ChartDataPoint> evolutionPoints = [];
    double cumulativeFuel = 0.0;
    double cumulativeDist = 0.0;

    for (final r in sorted) {
      if (r.fuelConsumption != null &&
          r.fuelConsumption! > 0 &&
          r.distance != null &&
          r.distance! > 0) {
        // A completed cycle may include partial fills from earlier records;
        // use the calculated cycle fuel rather than only the final fill.
        cumulativeFuel += (r.fuelConsumption! * r.distance!) / 100.0;
        cumulativeDist += r.distance!;

        final movingAvg = (cumulativeFuel / cumulativeDist) * 100.0;
        if (movingAvg > 0 && movingAvg < 30) {
          evolutionPoints.add(
            ChartDataPoint(
              label: DateFormatter.formatMonthDay(r.refuelDate),
              value: double.parse(movingAvg.toStringAsFixed(2)),
              date: r.refuelDate,
              extra:
                  '累计跑 ${cumulativeDist.toStringAsFixed(0)}km · 耗油 ${cumulativeFuel.toStringAsFixed(1)}L',
            ),
          );
        }
      }
    }

    return evolutionPoints;
  }

  /// 3. 生成燃油单价历史变动走势点序列
  static List<ChartDataPoint> getPriceTrend(List<RefuelRecordModel> records) {
    final sorted = List<RefuelRecordModel>.from(records)
      ..sort((a, b) => a.refuelDate.compareTo(b.refuelDate));

    return sorted.map((r) {
      return ChartDataPoint(
        label: DateFormatter.formatMonthDay(r.refuelDate),
        value: r.unitPrice,
        date: r.refuelDate,
        extra: '${r.fuelType} · ${r.gasStation ?? "油站"}',
      );
    }).toList();
  }

  /// 4. 每万公里阶段平均油耗阶梯统计 (带阶段诊断与上一阶段对比)
  static List<TenThousandKmStats> getTenThousandKmStats(
    List<RefuelRecordModel> records,
  ) {
    if (records.isEmpty) return [];

    final sorted = List<RefuelRecordModel>.from(records)
      ..sort((a, b) => a.mileage.compareTo(b.mileage));
    final minMileage = sorted.first.mileage;
    final maxMileage = sorted.last.mileage;

    final int startStage = (minMileage / 10000).floor();
    final int endStage = (maxMileage / 10000).floor();

    final List<TenThousandKmStats> stages = [];
    double? prevAvgCons;

    for (int s = startStage; s <= endStage; s++) {
      final double stageStartKm = s * 10000.0;
      final double stageEndKm = (s + 1) * 10000.0;
      final stageLabel = '$s万~${s + 1}万km';

      String phaseTitle;
      if (s == 0) {
        phaseTitle = '新车磨合阶段';
      } else if (s == 1) {
        phaseTitle = '首保黄金阶段';
      } else if (s == 2) {
        phaseTitle = '性能稳定阶段';
      } else if (s == 3) {
        phaseTitle = '平稳中程阶段';
      } else if (s == 4) {
        phaseTitle = '大保养前瞻阶段';
      } else {
        phaseTitle = '长效运营阶段';
      }

      final stageRecords = sorted
          .where((r) => r.mileage >= stageStartKm && r.mileage < stageEndKm)
          .toList();

      final validStageRecords = stageRecords.where(
        (r) =>
            r.fuelConsumption != null &&
            r.fuelConsumption! > 0 &&
            r.distance != null &&
            r.distance! > 0,
      );
      final validDistance = validStageRecords.fold(
        0.0,
        (sum, r) => sum + r.distance!,
      );
      final validFuel = validStageRecords.fold(
        0.0,
        (sum, r) => sum + (r.fuelConsumption! * r.distance!) / 100.0,
      );
      final avgCons = validDistance > 0
          ? (validFuel / validDistance) * 100.0
          : 0.0;

      final dist = stageRecords
          .where(FuelCalculator.isCompletedCycleRecord)
          .fold(0.0, (sum, r) => sum + (r.distance ?? 0.0));
      final fuel = stageRecords.fold(0.0, (sum, r) => sum + r.fuelAmount);

      double? diff;
      if (avgCons > 0 && prevAvgCons != null && prevAvgCons > 0) {
        diff = double.parse((avgCons - prevAvgCons).toStringAsFixed(2));
      }
      if (avgCons > 0) {
        prevAvgCons = avgCons;
      }

      stages.add(
        TenThousandKmStats(
          stageLabel: stageLabel,
          phaseTitle: phaseTitle,
          avgConsumption: double.parse(avgCons.toStringAsFixed(2)),
          totalDistance: double.parse(dist.toStringAsFixed(1)),
          totalFuel: double.parse(fuel.toStringAsFixed(1)),
          recordCount: stageRecords.length,
          diffFromPrevious: diff,
        ),
      );
    }

    return stages;
  }

  /// 使用本地天气快照与加油记录按月份关联，支持跨年度长期趋势。
  static List<TemperatureVsConsumptionPoint>
  getTemperatureVsConsumptionFromSnapshots(
    List<RefuelRecordModel> records,
    List<WeatherSnapshotModel> snapshots,
  ) {
    final temperatures = <int, List<double>>{};
    for (final snapshot in snapshots) {
      final temperature = snapshot.averageTemperature;
      if (temperature != null) {
        temperatures
            .putIfAbsent(
              snapshot.snapshotDate.year * 100 + snapshot.snapshotDate.month,
              () => [],
            )
            .add(temperature);
      }
    }

    final fuelByDistance = <int, _WeightedConsumption>{};
    for (final record in records) {
      final consumption = record.fuelConsumption;
      final distance = record.distance;
      if (consumption != null &&
          consumption > 0 &&
          distance != null &&
          distance > 0) {
        final key = record.refuelDate.year * 100 + record.refuelDate.month;
        final aggregate = fuelByDistance.putIfAbsent(
          key,
          () => _WeightedConsumption(),
        );
        aggregate.distance += distance;
        aggregate.fuel += consumption * distance / 100.0;
        aggregate.recordCount++;
      }
    }

    final result = <TemperatureVsConsumptionPoint>[];
    final keys = temperatures.keys.where(fuelByDistance.containsKey).toList()
      ..sort();
    final years = keys.map((key) => key ~/ 100).toSet();
    for (final key in keys) {
      final month = key % 100;
      final year = key ~/ 100;
      final monthTemps = temperatures[key];
      final consumption = fuelByDistance[key];
      if (monthTemps == null ||
          monthTemps.isEmpty ||
          consumption == null ||
          consumption.distance <= 0) {
        continue;
      }
      final averageTemp =
          monthTemps.reduce((a, b) => a + b) / monthTemps.length;
      final averageConsumption = consumption.fuel / consumption.distance * 100;
      result.add(
        TemperatureVsConsumptionPoint(
          monthLabel: years.length > 1 ? '$year年$month月' : '$month月',
          avgConsumption: double.parse(averageConsumption.toStringAsFixed(2)),
          estimatedTemperature: double.parse(averageTemp.toStringAsFixed(1)),
          refuelCount: consumption.recordCount,
        ),
      );
    }
    return result;
  }

  /// 7. 周期多粒度统计（年度 / 季度 / 月度 / 行程）
  static List<PeriodStatsItem> getPeriodStats({
    required List<RefuelRecordModel> records,
    required List<ExpenseRecordModel> expenses,
    required String periodType,
  }) {
    final Map<String, List<RefuelRecordModel>> groupedRefuel = {};
    final Map<String, List<ExpenseRecordModel>> groupedExpense = {};

    for (final r in records) {
      String key;
      if (periodType == '年度') {
        key = '${r.refuelDate.year}年';
      } else if (periodType == '季度') {
        final q = ((r.refuelDate.month - 1) / 3).floor() + 1;
        key = '${r.refuelDate.year}年Q$q';
      } else if (periodType == '月度') {
        key =
            '${r.refuelDate.year}-${r.refuelDate.month.toString().padLeft(2, '0')}';
      } else {
        // 行程粒度：按完整日期分组，避免不同年份的同月同日被错误合并
        key = DateFormatter.formatYmd(r.refuelDate);
      }
      groupedRefuel.putIfAbsent(key, () => []).add(r);
    }

    for (final e in expenses) {
      String key;
      if (periodType == '年度') {
        key = '${e.expenseDate.year}年';
      } else if (periodType == '季度') {
        final q = ((e.expenseDate.month - 1) / 3).floor() + 1;
        key = '${e.expenseDate.year}年Q$q';
      } else if (periodType == '月度') {
        key =
            '${e.expenseDate.year}-${e.expenseDate.month.toString().padLeft(2, '0')}';
      } else {
        key = DateFormatter.formatYmd(e.expenseDate);
      }
      groupedExpense.putIfAbsent(key, () => []).add(e);
    }

    final allKeys = {...groupedRefuel.keys, ...groupedExpense.keys}.toList()
      ..sort();

    final List<PeriodStatsItem> result = [];
    for (final k in allKeys) {
      final rList = groupedRefuel[k] ?? [];
      final eList = groupedExpense[k] ?? [];

      final dist = rList
          .where(FuelCalculator.isCompletedCycleRecord)
          .fold(0.0, (sum, r) => sum + (r.distance ?? 0.0));
      final fuel = rList.fold(0.0, (sum, r) => sum + r.fuelAmount);
      final fuelCost = rList.fold(0.0, (sum, r) => sum + r.totalPrice);
      final otherCost = eList.fold(0.0, (sum, e) => sum + e.amount);
      final totalCost = fuelCost + otherCost;

      final validRecords = rList.where(
        (r) =>
            r.fuelConsumption != null &&
            r.fuelConsumption! > 0 &&
            r.distance != null &&
            r.distance! > 0,
      );
      final validDistance = validRecords.fold(
        0.0,
        (sum, r) => sum + r.distance!,
      );
      final validFuel = validRecords.fold(
        0.0,
        (sum, r) => sum + (r.fuelConsumption! * r.distance!) / 100.0,
      );
      final avgCons = validDistance > 0
          ? validFuel / validDistance * 100.0
          : 0.0;
      final costPerKm = dist > 0 ? (totalCost / dist) : 0.0;

      result.add(
        PeriodStatsItem(
          label: k,
          mileage: double.parse(dist.toStringAsFixed(1)),
          fuelAmount: double.parse(fuel.toStringAsFixed(1)),
          fuelCost: double.parse(fuelCost.toStringAsFixed(1)),
          totalExpense: double.parse(totalCost.toStringAsFixed(1)),
          avgConsumption: double.parse(avgCons.toStringAsFixed(2)),
          costPerKm: double.parse(costPerKm.toStringAsFixed(2)),
        ),
      );
    }

    return result;
  }

  /// 9. 计算全车综合用车成本结构占比
  static List<ExpenseCategoryShare> getExpenseStructure({
    required List<RefuelRecordModel> refuelRecords,
    required List<ExpenseRecordModel> expenseRecords,
  }) {
    final Map<String, double> categorySums = {};

    double totalFuel = 0.0;
    for (final r in refuelRecords) {
      totalFuel += r.totalPrice;
    }
    if (totalFuel > 0) {
      categorySums['燃油支出'] = totalFuel;
    }

    for (final exp in expenseRecords) {
      categorySums[exp.category] =
          (categorySums[exp.category] ?? 0.0) + exp.amount;
    }

    final double totalAll = categorySums.values.fold(
      0.0,
      (sum, val) => sum + val,
    );
    if (totalAll <= 0) return [];

    final List<ExpenseCategoryShare> results = [];
    categorySums.forEach((category, amount) {
      final percent = (amount / totalAll) * 100.0;
      results.add(
        ExpenseCategoryShare(
          category: category,
          totalAmount: double.parse(amount.toStringAsFixed(2)),
          percentage: double.parse(percent.toStringAsFixed(1)),
        ),
      );
    });

    results.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return results;
  }

  /// 10. 扫描费用记录中的保养/保险提醒
  static List<ReminderItem> getActiveReminders({
    required double currentMaxMileage,
    required List<ExpenseRecordModel> expenseRecords,
  }) {
    final List<ReminderItem> reminders = [];
    final now = DateTime.now();

    for (final exp in expenseRecords) {
      double? remainKm;
      bool isKmOverdue = false;
      bool isKmUrgent = false;
      if (exp.nextReminderMileage != null && exp.nextReminderMileage! > 0) {
        remainKm = exp.nextReminderMileage! - currentMaxMileage;
        if (remainKm <= 0) {
          isKmOverdue = true;
        } else if (remainKm <= 500) {
          isKmUrgent = true;
        }
      }

      int? remainDays;
      bool isDateOverdue = false;
      bool isDateUrgent = false;
      if (exp.nextReminderDate != null) {
        remainDays = exp.nextReminderDate!.difference(now).inDays;
        if (remainDays <= 0) {
          isDateOverdue = true;
        } else if (remainDays <= 15) {
          isDateUrgent = true;
        }
      }

      if (remainKm != null || remainDays != null) {
        reminders.add(
          ReminderItem(
            title: '${exp.category}提醒',
            category: exp.category,
            targetMileage: exp.nextReminderMileage,
            remainingMileage: remainKm,
            targetDate: exp.nextReminderDate,
            remainingDays: remainDays,
            isOverdue: isKmOverdue || isDateOverdue,
            isUrgent: isKmUrgent || isDateUrgent,
          ),
        );
      }
    }

    return reminders;
  }

  /// 11. 生成每公里花费历史走势折线图 (¥/km)
  static List<ChartDataPoint> getCostPerKmTrend(
    List<RefuelRecordModel> records,
  ) {
    final validRecords =
        records.where((r) => r.costPerKm != null && r.costPerKm! > 0).toList()
          ..sort((a, b) => a.refuelDate.compareTo(b.refuelDate));

    return validRecords.map((r) {
      return ChartDataPoint(
        label: DateFormatter.formatMonthDay(r.refuelDate),
        value: r.costPerKm!,
        date: r.refuelDate,
        extra:
            '油耗: ${r.fuelConsumption?.toStringAsFixed(1) ?? "--"}L · ¥${r.unitPrice}/L',
      );
    }).toList();
  }

  /// 12. 异常点智能诊断（仅基于有效实测油耗记录）
  static List<AnomalyDiagnosticItem> getAnomalyDiagnostics(
    List<RefuelRecordModel> records,
  ) {
    final validRecords =
        records
            .where(
              (r) =>
                  r.fuelConsumption != null &&
                  r.fuelConsumption! > 0 &&
                  r.distance != null &&
                  r.distance! > 0,
            )
            .toList()
          ..sort((a, b) => b.refuelDate.compareTo(a.refuelDate));

    if (validRecords.length < 5) return [];

    final consumptions = validRecords.map((r) => r.fuelConsumption!).toList();
    final mean = consumptions.reduce((a, b) => a + b) / consumptions.length;

    // 计算标准差与离群阈值 (约 1.1 倍标准差敏感度)
    final variance =
        consumptions.fold(
          0.0,
          (sum, val) => sum + (val - mean) * (val - mean),
        ) /
        consumptions.length;
    final stdDev = variance > 0 ? math.sqrt(variance) : 0.8;
    final highThreshold = mean + (stdDev * 1.15).clamp(0.7, 2.5);
    final lowThreshold = mean - (stdDev * 1.05).clamp(0.6, 2.2);

    final List<AnomalyDiagnosticItem> diagnostics = [];

    for (final r in validRecords) {
      final cons = r.fuelConsumption!;
      if (cons >= highThreshold) {
        final diff = cons - mean;
        final pct = (diff / mean) * 100.0;
        diagnostics.add(
          AnomalyDiagnosticItem(
            recordId: r.id,
            date: r.refuelDate,
            consumption: double.parse(cons.toStringAsFixed(2)),
            baselineConsumption: double.parse(mean.toStringAsFixed(2)),
            deviation: double.parse(diff.toStringAsFixed(2)),
            deviationPercent: double.parse(pct.toStringAsFixed(1)),
            isHigh: true,
            station: r.gasStation ?? '加油站',
            reason:
                '该次实测油耗高于 ${mean.toStringAsFixed(2)} L/100km 的个人基线，偏差 ${diff.toStringAsFixed(2)} L/100km。',
            suggestion: '请结合本次记录的备注、行驶距离和路况核对；若连续出现，再检查胎压、空调和车辆状态。',
          ),
        );
      } else if (cons <= lowThreshold && cons > 2.0) {
        final diff = mean - cons;
        final pct = (diff / mean) * 100.0;

        diagnostics.add(
          AnomalyDiagnosticItem(
            recordId: r.id,
            date: r.refuelDate,
            consumption: double.parse(cons.toStringAsFixed(2)),
            baselineConsumption: double.parse(mean.toStringAsFixed(2)),
            deviation: double.parse((-diff).toStringAsFixed(2)),
            deviationPercent: double.parse((-pct).toStringAsFixed(1)),
            isHigh: false,
            station: r.gasStation ?? '加油站',
            reason:
                '该次实测油耗低于 ${mean.toStringAsFixed(2)} L/100km 的个人基线，偏差 ${diff.toStringAsFixed(2)} L/100km。',
            suggestion: '这只是当前记录中的低油耗样本，不推断外部气候或油站因素；可继续积累同类完整记录。',
          ),
        );
      }
    }

    return diagnostics;
  }

  /// 14. 构造 365 天出车热力矩阵数据 (GitHub-style 52周 x 7天)
  static YearlyHeatmapSummary get365DayActivityHeatmap(
    List<RefuelRecordModel> records,
    List<ExpenseRecordModel> expenses, {
    int? year,
  }) {
    final now = DateTime.now();
    final targetYear = year ?? now.year;
    final startDate = DateTime(targetYear, 1, 1);
    final endDate = DateTime(targetYear, 12, 31);
    final totalDays = endDate.difference(startDate).inDays + 1;

    // 按日期汇总里程、加油量和支出
    final Map<String, double> dayDistMap = {};
    final Map<String, double> dayFuelMap = {};
    final Map<String, double> dayExpMap = {};

    for (final r in records) {
      if (r.refuelDate.year == targetYear) {
        final key = DateFormatter.formatYmd(r.refuelDate);
        dayDistMap[key] =
            (dayDistMap[key] ?? 0.0) +
            (FuelCalculator.isCompletedCycleRecord(r)
                ? (r.distance ?? 0.0)
                : 0.0);
        dayFuelMap[key] = (dayFuelMap[key] ?? 0.0) + r.fuelAmount;
        dayExpMap[key] = (dayExpMap[key] ?? 0.0) + r.totalPrice;
      }
    }

    for (final e in expenses) {
      if (e.expenseDate.year == targetYear) {
        final key = DateFormatter.formatYmd(e.expenseDate);
        dayExpMap[key] = (dayExpMap[key] ?? 0.0) + e.amount;
      }
    }

    final List<DailyActivityCell> cells = [];
    int activeDays = 0;
    double maxDailyDist = 0.0;
    double totalYearDist = 0.0;
    int currentConsecutive = 0;
    int maxConsecutive = 0;

    for (int i = 0; i < totalDays; i++) {
      final curDate = startDate.add(Duration(days: i));
      final key = DateFormatter.formatYmd(curDate);
      final dist = dayDistMap[key] ?? 0.0;
      final fuel = dayFuelMap[key] ?? 0.0;
      final exp = dayExpMap[key] ?? 0.0;

      int level = 0;
      if (dist > 0 || exp > 0 || fuel > 0) {
        if (dist > 150) {
          level = 4;
        } else if (dist > 70) {
          level = 3;
        } else if (dist > 25) {
          level = 2;
        } else {
          level = 1;
        }
      }

      if (level > 0) {
        activeDays++;
        currentConsecutive++;
        if (currentConsecutive > maxConsecutive) {
          maxConsecutive = currentConsecutive;
        }
      } else {
        currentConsecutive = 0;
      }

      if (dist > maxDailyDist) maxDailyDist = dist;
      totalYearDist += dist;

      cells.add(
        DailyActivityCell(
          date: curDate,
          weekday: curDate.weekday,
          mileage: dist,
          fuelAmount: fuel,
          totalExpense: exp,
          intensityLevel: level,
        ),
      );
    }

    final double activeRate = totalDays > 0
        ? (activeDays / totalDays) * 100.0
        : 0.0;

    return YearlyHeatmapSummary(
      year: targetYear,
      activeDays: activeDays,
      totalDays: totalDays,
      activeRate: double.parse(activeRate.toStringAsFixed(1)),
      maxDailyMileage: double.parse(maxDailyDist.toStringAsFixed(1)),
      totalYearMileage: double.parse(totalYearDist.toStringAsFixed(1)),
      maxConsecutiveActiveDays: maxConsecutive,
      cells: cells,
    );
  }
}
