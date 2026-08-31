import '../data/models/refuel_record_model.dart';
import 'fuel_cycle.dart';

/// 油耗计算结果概览
class FuelCalculationSummary {
  final double averageConsumption; // 加权综合平均油耗 (L/100km)
  final double averageCostPerKm; // 加权平均每公里成本 (¥/km)
  final double bestConsumption; // 历史最佳/最低油耗 (L/100km)
  final double worstConsumption; // 历史最高油耗 (L/100km)
  final double totalFuelAmount; // 累计加油总升数 (L)
  final double totalFuelCost; // 累计加油总金额 (¥)
  final double totalValidDistance; // 参与计算的有效总行驶里程 (km)
  final int validCalculatedCount; // 成功计算出百公里油耗的记录次数

  const FuelCalculationSummary({
    this.averageConsumption = 0.0,
    this.averageCostPerKm = 0.0,
    this.bestConsumption = 0.0,
    this.worstConsumption = 0.0,
    this.totalFuelAmount = 0.0,
    this.totalFuelCost = 0.0,
    this.totalValidDistance = 0.0,
    this.validCalculatedCount = 0,
  });
}

/// 小熊油耗核心计算引擎算法实现
class FuelCalculator {
  /// 是否为完成测量周期的记录（已算出百公里油耗）。
  ///
  /// 只有完成周期的记录携带权威区间里程；未加满记录的 distance
  /// 只是"距上次加满"的展示值，会与下一个完成周期的里程重叠，
  /// 因此聚合统计总里程时必须先按此条件过滤。
  static bool isCompletedCycleRecord(RefuelRecordModel r) =>
      r.fuelConsumption != null;

  /// 批量计算加油记录集，填充每条记录的百公里油耗、每公里花费及区间行驶里程
  ///
  /// [records]: 输入的原始记录（内部会自动按里程和日期升序排序后计算）
  /// 返回：计算并填充好油耗属性的记录列表副本
  static List<RefuelRecordModel> computeRecords(
    List<RefuelRecordModel> records,
  ) {
    if (records.isEmpty) return [];

    // 非法日期记录保留在账本中，便于用户导出/修复；仅从计算排序输入中隔离。
    final invalidRecords = records.where((r) => r.hasInvalidDate).toList();
    final sorted = List<RefuelRecordModel>.from(records)
      ..removeWhere((r) => r.hasInvalidDate)
      ..sort((a, b) {
        final cmp = a.refuelDate.compareTo(b.refuelDate);
        if (cmp != 0) return cmp;
        return a.mileage.compareTo(b.mileage);
      });

    int? lastFullIndex; // 上一次加满跳枪的记录索引
    double pendingFuelAmount = 0.0; // 两次加满之间累计的未加满油量
    double pendingCost = 0.0; // 两次加满之间累计的未加满金额

    for (int i = 0; i < sorted.length; i++) {
      final current = sorted[i];

      // 场景 1：用户标记了“漏记了前一次加油”，或确认“更换里程表/新基准”。
      // 两者都构成统计断点：此前未闭合的量无法归属，从本条重新起算。
      if (current.isForgotPrevious || current.isOdometerReset) {
        current.fuelConsumption = null;
        current.costPerKm = null;
        current.distance = null;

        // 清空之前的中间未加满累计
        pendingFuelAmount = 0.0;
        pendingCost = 0.0;

        // 如果本次是加满，则从本次开始作为新的计算起点
        if (current.isFullTank) {
          lastFullIndex = i;
        } else {
          lastFullIndex = null;
        }
        continue;
      }

      // 场景 1.5：检测到表显里程回拨 (P1-06)。
      // 回拨未经用户确认前，跨越断点的距离与油量不可对账：
      // 停止跨断点计算，后续记录从新基准开始。
      final isRollback = i > 0 && current.mileage < sorted[i - 1].mileage;
      if (isRollback) {
        current.fuelConsumption = null;
        current.costPerKm = null;
        current.distance = null;

        pendingFuelAmount = 0.0;
        pendingCost = 0.0;

        lastFullIndex = current.isFullTank ? i : null;
        continue;
      }

      // 场景 2：尚未找到第一个“加满”基准点
      if (lastFullIndex == null) {
        current.fuelConsumption = null;
        current.costPerKm = null;
        current.distance = null;

        if (current.isFullTank) {
          lastFullIndex = i; // 找到首个加满点，以此作为后续区间的计算基准
        }
        continue;
      }

      // 场景 3：已存在前序加满基准点
      final lastFullRecord = sorted[lastFullIndex];
      final deltaDistance = current.mileage - lastFullRecord.mileage;

      if (!current.isFullTank) {
        // 本次未加满：累计加油量和费用，留待下次加满时平摊
        pendingFuelAmount += current.fuelAmount;
        pendingCost += current.totalPrice;
        current.fuelConsumption = null;
        current.costPerKm = null;
        current.distance = deltaDistance > 0 ? deltaDistance : null;
      } else {
        // 本次加满：完成一个完整的加油周期计算！
        if (deltaDistance > 0) {
          final totalCycleFuel = pendingFuelAmount + current.fuelAmount;
          final totalCycleCost = pendingCost + current.totalPrice;

          // 计算百公里油耗 (L/100km) = (总升数 / 区间里程) * 100
          final consumption = (totalCycleFuel / deltaDistance) * 100;

          // 计算每公里成本 (¥/km) = 总费用 / 区间里程
          final costPerKm = totalCycleCost / deltaDistance;

          current.fuelConsumption = double.parse(
            consumption.toStringAsFixed(2),
          );
          current.costPerKm = double.parse(costPerKm.toStringAsFixed(2));
          current.distance = double.parse(deltaDistance.toStringAsFixed(1));
        } else {
          // 里程未增加或异常，无法计算
          current.fuelConsumption = null;
          current.costPerKm = null;
          current.distance = 0.0;
        }

        // 清空累计并更新加满基准点为当前记录
        pendingFuelAmount = 0.0;
        pendingCost = 0.0;
        lastFullIndex = i;
      }
    }

    return [...sorted, ...invalidRecords];
  }

  /// 汇总计算整车的综合油耗、总花费、最佳/最差油耗指标
  static FuelCalculationSummary calculateSummary(
    List<RefuelRecordModel> computedRecords,
  ) {
    if (computedRecords.isEmpty) {
      return const FuelCalculationSummary();
    }

    // 交易口径总量保留全部有效账本记录（含未闭合尾笔）。
    var totalFuelAmount = 0.0;
    var totalFuelCost = 0.0;
    for (final record in computedRecords) {
      if (record.hasInvalidDate) continue;
      totalFuelAmount += record.fuelAmount;
      totalFuelCost += record.totalPrice;
    }

    // 以不可变完整周期作为汇总源，避免从已四舍五入的记录派生字段反推。
    final cycles = FuelCycleBuilder.build(
      computedRecords,
    ).where((cycle) => cycle.isReliable).toList();
    double totalValidDistance = 0.0;
    double totalValidFuelForConsumption = 0.0;
    double totalValidCost = 0.0;
    double totalValidCostDistance = 0.0;
    double? bestConsumption;
    double? worstConsumption;
    for (final cycle in cycles) {
      totalValidDistance += cycle.distance;
      totalValidFuelForConsumption += cycle.fuelAmount;
      final consumption = cycle.consumption!;
      if (bestConsumption == null || consumption < bestConsumption) {
        bestConsumption = consumption;
      }
      if (worstConsumption == null || consumption > worstConsumption) {
        worstConsumption = consumption;
      }
    }

    // 成本使用完整周期原始费用；正常计算时周期结束记录有成本投影。
    // 旧备份若缺少结束投影，则退回该周期中可用的记录级成本，但只按
    // 有效记录距离计入，绝不把缺失值当作 0。
    for (final cycle in cycles) {
      final members = cycle.memberIndices
          .where((index) => index >= 0 && index < computedRecords.length)
          .map((index) => computedRecords[index])
          .where(
            (record) =>
                !record.hasInvalidDate &&
                record.costPerKm != null &&
                record.costPerKm! > 0 &&
                record.distance != null &&
                record.distance! > 0,
          )
          .toList();
      final endHasCost = members.any(
        (record) =>
            record.refuelDate == cycle.endDate &&
            record.mileage == cycle.endMileage,
      );
      if (endHasCost) {
        totalValidCost += cycle.cost;
        totalValidCostDistance += cycle.distance;
      } else if (members.isNotEmpty) {
        for (final record in members) {
          totalValidCost += record.costPerKm! * record.distance!;
          totalValidCostDistance += record.distance!;
        }
      }
    }

    final avgConsumption = totalValidDistance > 0
        ? totalValidFuelForConsumption / totalValidDistance * 100.0
        : 0.0;
    final avgCostPerKm = totalValidCostDistance > 0
        ? totalValidCost / totalValidCostDistance
        : 0.0;

    return FuelCalculationSummary(
      averageConsumption: double.parse(avgConsumption.toStringAsFixed(2)),
      averageCostPerKm: double.parse(avgCostPerKm.toStringAsFixed(2)),
      bestConsumption: bestConsumption == null
          ? 0.0
          : double.parse(bestConsumption.toStringAsFixed(2)),
      worstConsumption: worstConsumption == null
          ? 0.0
          : double.parse(worstConsumption.toStringAsFixed(2)),
      totalFuelAmount: double.parse(totalFuelAmount.toStringAsFixed(2)),
      totalFuelCost: double.parse(totalFuelCost.toStringAsFixed(2)),
      totalValidDistance: double.parse(totalValidDistance.toStringAsFixed(1)),
      validCalculatedCount: cycles.length,
    );
  }
}
