import '../data/models/refuel_record_model.dart';
import '../data/models/expense_record_model.dart';
import '../data/models/weather_snapshot_model.dart';
import '../../core/utils/date_formatter.dart';
import 'fuel_cycle.dart';

/// 统计范围的完整周期口径统计 (P1-02)
class RangeCycleStats {
  /// 完整包含在范围内的可信周期数
  final int cycleCount;

  /// 与范围相交但起止点未完整落入范围的周期数（边界未闭合）
  final int boundaryCycleCount;

  /// 完整包含周期的里程之和 (km)
  final double distance;

  /// 完整包含周期的油量之和 (L)
  final double fuelAmount;

  /// 完整包含周期的费用之和 (¥)
  final double cost;

  const RangeCycleStats({
    this.cycleCount = 0,
    this.boundaryCycleCount = 0,
    this.distance = 0,
    this.fuelAmount = 0,
    this.cost = 0,
  });

  bool get hasCycles => cycleCount > 0;

  /// 范围平均油耗 (L/100km)。无完整周期时为 null，调用方不得显示为 0。
  double? get avgConsumption =>
      cycleCount > 0 && distance > 0 ? fuelAmount / distance * 100.0 : null;

  /// 范围每公里成本 (¥/km)，与平均油耗同源（完整周期口径）。
  double? get costPerKm =>
      cycleCount > 0 && distance > 0 ? cost / distance : null;
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
  final double totalDistance; // 该阶段行驶总里程（跨阶段周期按里程比例计入）

  /// 该阶段分摊消耗量：跨阶段周期按里程比例分配后的油量。
  /// 与 [transactionFuel] 不同，后者只是本阶段内的加油交易量。
  final double totalFuel;

  /// 该阶段发生的加油交易总量，仅作交易口径展示
  final double transactionFuel;

  final int recordCount; // 该阶段记录数
  final double? diffFromPrevious; // 较上一阶段油耗变化 (负数表示省油，正数表示上升)

  TenThousandKmStats({
    required this.stageLabel,
    required this.phaseTitle,
    required this.avgConsumption,
    required this.totalDistance,
    required this.totalFuel,
    double? transactionFuel,
    required this.recordCount,
    this.diffFromPrevious,
  }) : transactionFuel = transactionFuel ?? totalFuel;
}

/// 周期多粒度统计数据模型（年度/季度/月度/行程）
class PeriodStatsItem {
  final String label; // 周期标签 (如 "2026年", "2026-Q1", "2026-08月")

  /// 完整周期口径里程：归到本周期的完整油耗周期距离之和。
  ///
  /// 与 [avgConsumption]、[costPerKm] 共用同一分母，三者可以对账。
  /// 没有完整周期时返回"数据不足"而非看似精确的 0。
  final double mileage;

  /// 交易口径加油量：本周期内发生的加油笔数之和，与周期消耗量不同。
  final double fuelAmount;

  /// 交易口径燃油支出
  final double fuelCost;
  final double totalExpense; // 综合总开销 (含其他费用)
  final double avgConsumption; // 平均油耗
  final double costPerKm; // 每公里成本 (¥/km)

  /// 归入本周期的完整周期数
  final int cycleCount;

  /// 与边界相交但未完整落在周期内的周期数。
  ///
  /// 这些周期的距离未计入 [mileage]，界面应显示为"边界未闭合"。
  final int boundaryCycleCount;

  /// 是否具备可用的完整周期数据
  bool get hasCycleData => cycleCount > 0 && mileage > 0;

  PeriodStatsItem({
    required this.label,
    required this.mileage,
    required this.fuelAmount,
    required this.fuelCost,
    required this.totalExpense,
    required this.avgConsumption,
    required this.costPerKm,
    this.cycleCount = 0,
    this.boundaryCycleCount = 0,
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

/// 未闭合加油记录的诊断分组类型
enum UnclosedCycleKind {
  /// 有加满基准点、之后只有未加满记录的开放周期：
  /// 待下次加满后即可闭合并计入统计
  openCycle,

  /// 不属于任何周期的记录（账本开头的未加满记录、断点后无法归属的
  /// 未加满记录）：除非补录加满基准，其油量无法归属到完整周期
  orphanRecords,
}

/// 一组未闭合的加油记录 (P2-09)。
///
/// 交易口径（加油量、实付金额）照常统计，但这些记录的油量尚未归属到
/// 任何完整周期，不参与平均油耗与每公里成本，由诊断列表明确列出，
/// 避免"未闭合"被伪装成 0 或凭空消失。
class UnclosedCycleDiagnostic {
  final UnclosedCycleKind kind;

  /// 开放周期的起始加满记录；孤行记录组为 null
  final RefuelRecordModel? anchorRecord;

  /// 组内全部记录（开放周期含起始加满记录；孤行组仅未归属记录）
  final List<RefuelRecordModel> records;

  /// 待归属的加油量 (L)：开放周期为起始加满之后的记录之和；
  /// 孤行组为全部记录之和
  final double pendingFuel;

  /// 待归属的实付金额 (¥)，口径与 [pendingFuel] 一致
  final double pendingCost;

  const UnclosedCycleDiagnostic({
    required this.kind,
    this.anchorRecord,
    required this.records,
    this.pendingFuel = 0,
    this.pendingCost = 0,
  });

  DateTime? get startDate => records.isEmpty ? null : records.first.refuelDate;

  DateTime? get lastDate => records.isEmpty ? null : records.last.refuelDate;
}

/// 按时间排序后累加相邻记录的正里程差。
///
/// 统一委托给 [FuelCycleBuilder.sumConsecutiveMileage]（分段实现，
/// 见 [FuelCycleBuilder.analyzeMileageSegments]），保证全应用只有
/// 一个里程累计口径。
double sumConsecutiveMileage(List<RefuelRecordModel> records) =>
    FuelCycleBuilder.sumConsecutiveMileage(records);

/// 数据统计与报表聚合领域服务
class StatisticsService {
  /// 统计范围的完整周期口径结果 (P1-02)。
  ///
  /// 范围统计必须拆成两套数据：
  /// - 交易口径（加油笔数、加油量、实付金额）：由调用方对过滤后的记录求和；
  /// - 完整周期口径（平均油耗、完整周期里程、每公里成本）：只有**完整包含**
  ///   在范围内的可信周期才参与，与边界相交但不完整的周期仅计数提示
  ///   "边界未闭合"，不得伪装成范围内的独立周期。
  static RangeCycleStats getRangeCycleStats({
    required List<RefuelRecordModel> allRecords,
    DateTime? startInclusive,
    DateTime? endExclusive,
  }) {
    if (allRecords.isEmpty) {
      return const RangeCycleStats();
    }

    // 周期必须建立在全量记录上，而不是范围切片后的记录上，
    // 否则起止点落在范围外的周期会被截断或丢失。
    final cycles = FuelCycleBuilder.build(allRecords);

    var cycleCount = 0;
    var boundaryCount = 0;
    var distance = 0.0;
    var fuel = 0.0;
    var cost = 0.0;

    for (final cycle in cycles) {
      if (!cycle.isReliable) continue;
      if (startInclusive == null || endExclusive == null) {
        cycleCount++;
        distance += cycle.distance;
        fuel += cycle.fuelAmount;
        cost += cycle.cost;
        continue;
      }
      if (cycle.isContainedIn(startInclusive, endExclusive)) {
        cycleCount++;
        distance += cycle.distance;
        fuel += cycle.fuelAmount;
        cost += cycle.cost;
      } else if (cycle.intersectsRange(startInclusive, endExclusive)) {
        boundaryCount++;
      }
    }

    return RangeCycleStats(
      cycleCount: cycleCount,
      boundaryCycleCount: boundaryCount,
      distance: distance,
      fuelAmount: fuel,
      cost: cost,
    );
  }

  /// 未闭合加油记录诊断列表 (P2-09)。
  ///
  /// 基于全量记录建立的周期，找出尚未闭合到完整周期的记录分组：
  /// - 开放周期：起始加满之后只有未加满记录，待下次加满即闭合；
  /// - 孤行记录：不属于任何周期（账本开头、断点后），其油量暂无法归属。
  ///
  /// 这些记录的加油量与金额在交易口径照常统计，但不参与平均油耗、
  /// 每公里成本等完整周期指标。诊断列表让"未闭合"可见、可解释，
  /// 而不是静默消失或显示为 0。
  static List<UnclosedCycleDiagnostic> getUnclosedCycleDiagnostics(
    List<RefuelRecordModel> records,
  ) {
    if (records.isEmpty) return const [];

    final sorted = List<RefuelRecordModel>.from(records)
      ..removeWhere((r) => r.hasInvalidDate)
      ..sort((a, b) {
        final cmp = a.refuelDate.compareTo(b.refuelDate);
        if (cmp != 0) return cmp;
        return a.mileage.compareTo(b.mileage);
      });

    final cycles = FuelCycleBuilder.build(sorted);

    // 已归属到某个周期的记录索引（无论周期是否闭合）
    final assigned = <int>{};
    for (final cycle in cycles) {
      assigned.addAll(cycle.memberIndices);
    }

    final diagnostics = <UnclosedCycleDiagnostic>[];

    // 1. 开放周期：起始加满之后只有未加满记录
    for (final cycle in cycles) {
      if (cycle.isClosed) continue;
      diagnostics.add(
        UnclosedCycleDiagnostic(
          kind: UnclosedCycleKind.openCycle,
          anchorRecord: sorted[cycle.startIndex],
          records: cycle.memberIndices.map((i) => sorted[i]).toList(),
          pendingFuel: cycle.fuelAmount,
          pendingCost: cycle.cost,
        ),
      );
    }

    // 2. 孤行记录：不在任何周期中，连续的未归属记录合为一组
    final orphanIndices = <int>[
      for (int i = 0; i < sorted.length; i++)
        if (!assigned.contains(i)) i,
    ];
    for (var i = 0; i < orphanIndices.length; i++) {
      final startIdx = orphanIndices[i];
      var endIdx = startIdx;
      // 把时间上连续的未归属记录合为一组，便于用户在账本中定位
      while (i + 1 < orphanIndices.length &&
          orphanIndices[i + 1] == endIdx + 1) {
        i++;
        endIdx = orphanIndices[i];
      }
      final group = <RefuelRecordModel>[
        for (var j = startIdx; j <= endIdx; j++) sorted[j],
      ];
      // 一条孤立的加满记录（无后续记录）没有待归属油量，仍列出
      // 让用户知道"只有一次加满基准，尚不构成周期"
      diagnostics.add(
        UnclosedCycleDiagnostic(
          kind: UnclosedCycleKind.orphanRecords,
          records: group,
          pendingFuel: group.fold(0.0, (s, r) => s + r.fuelAmount),
          pendingCost: group.fold(0.0, (s, r) => s + r.totalPrice),
        ),
      );
    }

    // 按起始日期升序输出
    diagnostics.sort(
      (a, b) =>
          (a.startDate ?? DateTime(0)).compareTo(b.startDate ?? DateTime(0)),
    );
    return diagnostics;
  }

  /// 1. 生成单次百公里油耗变动趋势点序列
  static List<ChartDataPoint> getConsumptionTrend(
    List<RefuelRecordModel> records,
  ) {
    final validRecords =
        records
            .where(
              (r) =>
                  !r.hasInvalidDate &&
                  r.fuelConsumption != null &&
                  r.fuelConsumption! > 0 &&
                  r.distance != null &&
                  r.distance! > 0,
            )
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
  ///
  /// P2-11：单条记录油耗异常（≥ [anomalyConsumptionLimit] L/100km，如
  /// 派生字段损坏、旧备份脏数据）在进入累计分子/分母**之前**被排除，
  /// 不得先污染累计值再在展示层丢弃。
  static const double anomalyConsumptionLimit = 30.0;

  static List<ChartDataPoint> getMovingAverageEvolutionTrend(
    List<RefuelRecordModel> records,
  ) {
    final sorted = List<RefuelRecordModel>.from(records)
      ..removeWhere((r) => r.hasInvalidDate)
      ..sort((a, b) => a.refuelDate.compareTo(b.refuelDate));

    final List<ChartDataPoint> evolutionPoints = [];
    double cumulativeFuel = 0.0;
    double cumulativeDist = 0.0;

    for (final r in sorted) {
      if (r.fuelConsumption != null &&
          r.fuelConsumption! > 0 &&
          r.fuelConsumption! < anomalyConsumptionLimit &&
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
      ..removeWhere((r) => r.hasInvalidDate)
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
  ///
  /// 跨阶段的完整周期按里程比例切分，里程、油量、费用同步分配，
  /// 因此跨阶段的距离不再丢失，各阶段之和等于周期总量。
  static List<TenThousandKmStats> getTenThousandKmStats(
    List<RefuelRecordModel> records, {
    List<RefuelRecordModel>? allRecords,
  }) {
    final cycleSource = allRecords ?? records;
    if (cycleSource.isEmpty) return [];

    final sorted = List<RefuelRecordModel>.from(cycleSource)
      ..removeWhere((r) => r.hasInvalidDate)
      ..sort((a, b) => a.mileage.compareTo(b.mileage));
    if (sorted.isEmpty) return [];
    final minMileage = sorted.first.mileage;
    final maxMileage = sorted.last.mileage;

    final int startStage = (minMileage / 10000).floor();
    final int endStage = (maxMileage / 10000).floor();

    // 周期在全量记录上建立，再按里程区间切分
    final cycles = FuelCycleBuilder.build(
      cycleSource,
    ).where((c) => c.isReliable).toList();

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

      // 跨阶段周期按比例切分，里程/油量/费用同步分配
      var slice = const FuelCycleSlice();
      for (final cycle in cycles) {
        slice = slice + cycle.sliceByMileage(stageStartKm, stageEndKm);
      }

      final dist = slice.distance;
      final avgCons = dist > 0 ? slice.fuelAmount / dist * 100.0 : 0.0;

      // 交易口径：本阶段内发生的加油笔数与加油量，与分摊消耗量区分
      final transactionFuel = stageRecords.fold(
        0.0,
        (sum, r) => sum + r.fuelAmount,
      );

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
          totalFuel: double.parse(slice.fuelAmount.toStringAsFixed(1)),
          transactionFuel: double.parse(transactionFuel.toStringAsFixed(1)),
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
      if (record.hasInvalidDate) continue;
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

  /// 某个统计粒度下，日期所属分组的键与左闭右开时间范围。
  static ({String key, DateTime start, DateTime end}) _periodRange(
    DateTime d,
    String periodType,
  ) {
    switch (periodType) {
      case '年度':
        return (
          key: '${d.year}年',
          start: DateTime(d.year),
          end: DateTime(d.year + 1),
        );
      case '季度':
        final q = ((d.month - 1) / 3).floor() + 1;
        final startMonth = (q - 1) * 3 + 1;
        return (
          key: '${d.year}年Q$q',
          start: DateTime(d.year, startMonth),
          end: DateTime(d.year, startMonth + 3),
        );
      case '月度':
        return (
          key: '${d.year}-${d.month.toString().padLeft(2, '0')}',
          start: DateTime(d.year, d.month),
          end: DateTime(d.year, d.month + 1),
        );
      default:
        return (
          key: DateFormatter.formatYmd(d),
          start: DateTime(d.year, d.month, d.day),
          end: DateTime(d.year, d.month, d.day + 1),
        );
    }
  }

  /// 7. 周期多粒度统计（年度 / 季度 / 月度 / 行程）
  ///
  /// 口径说明：
  /// - 加油量、油费、其他费用为**交易口径**，按发生日期归属；
  /// - 里程、平均油耗、每公里成本为**完整周期口径**，由完整油耗周期
  ///   按"结束加满记录所在周期"归属。
  ///
  /// 完整周期先在全量记录上建立，再分配到各分组，因此不再出现"每组
  /// 第一条记录缺少组外前序记录导致里程差被丢弃"的问题。
  static List<PeriodStatsItem> getPeriodStats({
    required List<RefuelRecordModel> records,
    List<RefuelRecordModel>? allRecords,
    required List<ExpenseRecordModel> expenses,
    required String periodType,
  }) {
    final cycleSource = allRecords ?? records;
    final Map<String, List<RefuelRecordModel>> groupedRefuel = {};
    final Map<String, List<ExpenseRecordModel>> groupedExpense = {};
    final Map<String, ({DateTime start, DateTime end})> ranges = {};

    void remember(String key, DateTime start, DateTime end) {
      ranges.putIfAbsent(key, () => (start: start, end: end));
    }

    for (final r in records) {
      if (r.hasInvalidDate) continue;
      final range = _periodRange(r.refuelDate, periodType);
      remember(range.key, range.start, range.end);
      groupedRefuel.putIfAbsent(range.key, () => []).add(r);
    }

    for (final e in expenses) {
      final range = _periodRange(e.expenseDate, periodType);
      remember(range.key, range.start, range.end);
      groupedExpense.putIfAbsent(range.key, () => []).add(e);
    }

    // 完整周期在全量记录上一次性建立，不按分组切片
    final cycles = FuelCycleBuilder.build(cycleSource);

    final allKeys = {...groupedRefuel.keys, ...groupedExpense.keys}.toList()
      ..sort();

    final List<PeriodStatsItem> result = [];
    for (final k in allKeys) {
      final rList = groupedRefuel[k] ?? [];
      final eList = groupedExpense[k] ?? [];
      final range = ranges[k];

      // 交易口径
      final fuel = rList.fold(0.0, (sum, r) => sum + r.fuelAmount);
      final fuelCost = rList.fold(0.0, (sum, r) => sum + r.totalPrice);
      final otherCost = eList.fold(0.0, (sum, e) => sum + e.amount);
      final totalCost = fuelCost + otherCost;

      // 完整周期口径
      var cycleDistance = 0.0;
      var cycleFuel = 0.0;
      var cycleCost = 0.0;
      var cycleCount = 0;
      var boundaryCount = 0;

      if (range != null) {
        for (final cycle in cycles) {
          if (!cycle.isReliable) continue;
          // 归属策略：结束加满记录落在哪个周期，整个周期就归入哪个周期
          if (cycle.isContainedIn(range.start, range.end)) {
            cycleCount++;
            cycleDistance += cycle.distance;
            cycleFuel += cycle.fuelAmount;
            cycleCost += cycle.cost;
          } else if (cycle.intersectsRange(range.start, range.end)) {
            boundaryCount++;
          }
        }
      }

      // 从原始周期值汇总，不从两位小数的油耗反推油量
      final avgCons = cycleDistance > 0
          ? cycleFuel / cycleDistance * 100.0
          : 0.0;
      final costPerKm = cycleDistance > 0 ? cycleCost / cycleDistance : 0.0;

      result.add(
        PeriodStatsItem(
          label: k,
          mileage: double.parse(cycleDistance.toStringAsFixed(1)),
          fuelAmount: double.parse(fuel.toStringAsFixed(1)),
          fuelCost: double.parse(fuelCost.toStringAsFixed(1)),
          totalExpense: double.parse(totalCost.toStringAsFixed(1)),
          avgConsumption: double.parse(avgCons.toStringAsFixed(2)),
          costPerKm: double.parse(costPerKm.toStringAsFixed(2)),
          cycleCount: cycleCount,
          boundaryCycleCount: boundaryCount,
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
      if (r.hasInvalidDate) continue;
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
        records
            .where(
              (r) =>
                  !r.hasInvalidDate &&
                  r.costPerKm != null &&
                  r.costPerKm! > 0 &&
                  r.distance != null &&
                  r.distance! > 0,
            )
            .toList()
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
}
