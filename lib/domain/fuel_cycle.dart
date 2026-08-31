import '../data/models/refuel_record_model.dart';

/// 相邻两条记录之间的里程连续性。
///
/// 表显里程下降既可能是录入错误，也可能是更换里程表。两者无法从数据本身
/// 区分，因此统一记为断点并让相关周期退出统计，由用户在审查中确认。
enum MileageContinuity {
  /// 里程单调递增，差值可用
  normal,

  /// 表显里程回拨（录入错误、误录高里程后修正、更换仪表），
  /// 未经用户确认前一律按断点隔断统计
  rollback,

  /// 用户确认"更换里程表 / 里程新基准"。
  /// 与 [rollback] 的区别：用户已确认新表读数可信，其后周期可正常计算。
  odometerReset,

  /// 用户标记漏记，主动断开周期
  manualBreak,
}

extension MileageContinuityX on MileageContinuity {
  /// 该状态是否构成统计断点
  bool get isBreak => this != MileageContinuity.normal;
}

/// 里程断点的位置与类型，供审查与诊断列表使用
class MileageBreak {
  /// 断点发生在 sorted[previousIndex] 与 sorted[currentIndex] 之间
  final int previousIndex;
  final int currentIndex;
  final MileageContinuity kind;

  const MileageBreak({
    required this.previousIndex,
    required this.currentIndex,
    required this.kind,
  });
}

/// 周期在里程碑区间内的份额。
///
/// 里程、油量与费用按同一比例切分，保证三者始终可以对账。
class FuelCycleSlice {
  final double distance;
  final double fuelAmount;
  final double cost;

  const FuelCycleSlice({this.distance = 0, this.fuelAmount = 0, this.cost = 0});

  FuelCycleSlice operator +(FuelCycleSlice other) => FuelCycleSlice(
    distance: distance + other.distance,
    fuelAmount: fuelAmount + other.fuelAmount,
    cost: cost + other.cost,
  );
}

/// 按里程连续性切分后的累计段 (P1-06)。
///
/// 检测到表显回拨（未确认）或用户确认换表/新基准时，累计在此断开：
/// 当前段到此为止，后续记录从新基准开始累计。漏记不断开里程段——
/// 两次已知表显之间的差值仍是真实行驶里程。
class MileageSegment {
  /// 段内首条记录在排序后列表中的索引
  final int startIndex;

  /// 段内末条记录在排序后列表中的索引（含）
  final int endIndex;

  /// 段内表显读数的实际增量之和
  final double distance;

  const MileageSegment({
    required this.startIndex,
    required this.endIndex,
    required this.distance,
  });
}

/// 里程连续性分段报告：段列表、断点列表与可对账的总量
class MileageSegmentReport {
  final List<MileageSegment> segments;

  /// 触发分段或被标记的断点（含用户确认的换表）
  final List<MileageBreak> breaks;

  const MileageSegmentReport({required this.segments, required this.breaks});

  bool get hasBreaks => breaks.isNotEmpty;

  /// 全部段的里程之和。与逐条累加正差等价，但可按段追溯到断点。
  double get totalDistance => segments.fold(0.0, (sum, s) => sum + s.distance);
}

/// 一个完整的加油周期：从上一次加满到本次加满。
///
/// 这是所有统计的基本单位。周期内的未加满记录只是"预支油量和费用"，
/// 不单独构成周期；周期未闭合（末尾只有未加满记录）时不得给出平均油耗。
class FuelCycle {
  /// 周期起始（加满）记录在排序后列表中的索引
  final int startIndex;

  /// 周期结束（加满）记录索引；未闭合时为 null
  final int? endIndex;

  /// 周期内全部记录索引，含中间的未加满记录
  final List<int> memberIndices;

  final DateTime startDate;

  /// 未闭合时为周期内最后一条记录的日期
  final DateTime? endDate;

  final double startMileage;
  final double? endMileage;

  /// 周期净行驶里程
  final double distance;

  /// 周期内消耗的油量：起始加满之后的所有加油量（含中间未加满记录）
  /// 再加上结束加满的加油量。
  final double fuelAmount;

  /// 与 [fuelAmount] 同源的周期费用
  final double cost;

  final bool isClosed;

  /// 周期内是否出现过里程断点
  final MileageContinuity continuity;

  const FuelCycle({
    required this.startIndex,
    required this.endIndex,
    required this.memberIndices,
    required this.startDate,
    required this.endDate,
    required this.startMileage,
    required this.endMileage,
    required this.distance,
    required this.fuelAmount,
    required this.cost,
    required this.isClosed,
    required this.continuity,
  });

  /// 周期平均油耗 (L/100km)。未闭合或里程不可用时返回 null，
  /// 由调用方决定如何展示，绝不能退化成看似精确的 0。
  double? get consumption {
    if (!isClosed || distance <= 0) return null;
    return fuelAmount / distance * 100.0;
  }

  /// 周期每公里成本 (¥/km)
  double? get costPerKm {
    if (!isClosed || distance <= 0) return null;
    return cost / distance;
  }

  /// 数据是否可用于统计。含断点或未闭合的周期不得进入平均油耗。
  bool get isReliable => isClosed && distance > 0 && !continuity.isBreak;

  /// 按里程区间切分周期。
  ///
  /// 用于每万公里阶段统计：跨阶段的周期按里程比例同时切分里程、油量与
  /// 费用，而不是把整个周期塞进结束点所在的阶段。
  FuelCycleSlice sliceByMileage(double fromKm, double toKm) {
    final from = startMileage < endMileage! ? startMileage : endMileage!;
    final to = startMileage < endMileage! ? endMileage! : startMileage;
    final overlapStart = from > fromKm ? from : fromKm;
    final overlapEnd = to < toKm ? to : toKm;
    if (overlapEnd <= overlapStart || distance <= 0) {
      return const FuelCycleSlice();
    }
    final ratio = (overlapEnd - overlapStart) / distance;
    return FuelCycleSlice(
      distance: overlapEnd - overlapStart,
      fuelAmount: fuelAmount * ratio,
      cost: cost * ratio,
    );
  }

  /// 周期是否与给定日期范围相交（[startInclusive, endExclusive)）
  bool intersectsRange(DateTime startInclusive, DateTime endExclusive) {
    final effectiveEnd = endDate;
    if (effectiveEnd == null) return false;
    return effectiveEnd.isAfter(startInclusive) &&
        startDate.isBefore(endExclusive);
  }

  /// 周期是否完整落在给定日期范围内。
  ///
  /// 只有完整包含的周期才应进入范围平均油耗，避免把一个跨越区间边界的
  /// 完整周期伪装成只属于该区间的独立周期。
  bool isContainedIn(DateTime startInclusive, DateTime endExclusive) {
    final effectiveEnd = endDate;
    if (effectiveEnd == null) return false;
    return !startDate.isBefore(startInclusive) &&
        effectiveEnd.isBefore(endExclusive);
  }
}

/// 由加油记录构建完整周期序列。
///
/// 与 [RefuelRecordModel] 上的派生字段不同，本类不修改任何记录，只输出
/// 可追溯的周期明细，供统计层按周期分配而不是按记录切片。
class FuelCycleBuilder {
  /// 构建一个车辆的完整周期列表。
  ///
  /// [records] 可为任意顺序，内部按加油时间升序排序。
  static List<FuelCycle> build(List<RefuelRecordModel> records) {
    if (records.isEmpty) return const [];

    final sorted = List<RefuelRecordModel>.from(records)
      ..removeWhere((r) => r.hasInvalidDate)
      ..sort((a, b) {
        final cmp = a.refuelDate.compareTo(b.refuelDate);
        if (cmp != 0) return cmp;
        return a.mileage.compareTo(b.mileage);
      });

    final cycles = <FuelCycle>[];
    int? openIndex;
    final pending = <int>[];
    double pendingFuel = 0.0;
    double pendingCost = 0.0;

    void emit({
      required int start,
      required int? end,
      required double fuel,
      required double cost,
      required bool closed,
      required MileageContinuity continuity,
      required List<int> members,
    }) {
      final startRecord = sorted[start];
      final endRecord = end == null ? sorted[members.last] : sorted[end];
      final distance = endRecord.mileage - startRecord.mileage;
      cycles.add(
        FuelCycle(
          startIndex: start,
          endIndex: end,
          memberIndices: members,
          startDate: startRecord.refuelDate,
          endDate: endRecord.refuelDate,
          startMileage: startRecord.mileage,
          endMileage: endRecord.mileage,
          distance: distance > 0 ? distance : 0,
          fuelAmount: fuel,
          cost: cost,
          isClosed: closed,
          continuity: continuity,
        ),
      );
    }

    void resetPending() {
      pending.clear();
      pendingFuel = 0.0;
      pendingCost = 0.0;
    }

    for (int i = 0; i < sorted.length; i++) {
      final current = sorted[i];
      final isRollback = i > 0 && current.mileage < sorted[i - 1].mileage;

      // 用户标记漏记：主动断开，此前未闭合的量无法归属。
      // 用户确认换表/新基准：同样在此断开，但新基准后的周期正常可信。
      if (current.isForgotPrevious || current.isOdometerReset) {
        openIndex = null;
        resetPending();
        if (current.isFullTank) {
          openIndex = i;
        }
        continue;
      }

      if (openIndex == null) {
        // 尚未找到第一个加满基准点
        if (current.isFullTank) {
          openIndex = i;
        }
        continue;
      }

      if (isRollback) {
        // 周期跨越里程回拨点：输出为不可信周期（isReliable 为 false），
        // 之后从当前记录重开，不继续用旧基准计算。
        if (current.isFullTank) {
          emit(
            start: openIndex,
            end: i,
            fuel: pendingFuel + current.fuelAmount,
            cost: pendingCost + current.totalPrice,
            closed: true,
            continuity: MileageContinuity.rollback,
            members: [openIndex, ...pending, i],
          );
          resetPending();
          openIndex = i;
        } else {
          // 断点后是未加满记录，无法可靠归属，丢弃待闭合周期等待下一个加满
          resetPending();
          openIndex = null;
        }
        continue;
      }

      if (!current.isFullTank) {
        pending.add(i);
        pendingFuel += current.fuelAmount;
        pendingCost += current.totalPrice;
        continue;
      }

      // 本次加满：闭合一个完整周期
      emit(
        start: openIndex,
        end: i,
        fuel: pendingFuel + current.fuelAmount,
        cost: pendingCost + current.totalPrice,
        closed: true,
        continuity: MileageContinuity.normal,
        members: [openIndex, ...pending, i],
      );
      resetPending();
      openIndex = i;
    }

    // 尾周期：有加满基准点但之后只有未加满记录，尚未闭合。
    if (openIndex != null && pending.isNotEmpty) {
      emit(
        start: openIndex,
        end: null,
        fuel: pendingFuel,
        cost: pendingCost,
        closed: false,
        continuity: MileageContinuity.normal,
        members: [openIndex, ...pending],
      );
    }

    return cycles;
  }

  /// 找出所有里程断点，供审查与诊断列表使用。
  static List<MileageBreak> findMileageBreaks(List<RefuelRecordModel> records) {
    if (records.length < 2) return const [];
    final sorted = List<RefuelRecordModel>.from(records)
      ..removeWhere((r) => r.hasInvalidDate)
      ..sort((a, b) {
        final c = a.refuelDate.compareTo(b.refuelDate);
        if (c != 0) return c;
        return a.mileage.compareTo(b.mileage);
      });

    final breaks = <MileageBreak>[];
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].mileage < sorted[i - 1].mileage) {
        breaks.add(
          MileageBreak(
            previousIndex: i - 1,
            currentIndex: i,
            kind: MileageContinuity.rollback,
          ),
        );
      }
    }
    return breaks;
  }

  /// 按时间排序后累加相邻记录的正里程差。
  ///
  /// 这是"累计行驶里程"的权威口径，返回的是表显读数的实际增量之和。
  /// 回拨段本身不计入（负差），但回拨之后重新行驶的里程仍会计入——
  /// 若那是一次真实的换表，这段里程确实存在；若后来被确认是误录修正，
  /// 相关周期已通过 [FuelCycle.isReliable] 退出统计，不会污染油耗。
  ///
  /// 本方法等价于 [analyzeMileageSegments] 各段距离之和；如需知道
  /// 累计被哪些断点分隔、每段各走了多少，请直接使用分段报告。
  static double sumConsecutiveMileage(List<RefuelRecordModel> records) {
    return analyzeMileageSegments(records).totalDistance;
  }

  /// 按里程连续性把排序后的记录切段 (P1-06)。
  ///
  /// - 未确认的表显回拨：段在此断开，后续记录从新基准开始累计；
  /// - 用户确认的换表/新基准（[RefuelRecordModel.isOdometerReset]）：
  ///   同样断开，断点进入 [MileageSegmentReport.breaks]；
  /// - 用户标记漏记：不断开，两次已知表显之差仍是真实里程。
  ///
  /// 涉及回拨的周期在 [FuelCycle.isReliable] 中会被标记为不可信，
  /// 不参与油耗与成本统计；审查提示由账本规则引擎的 mileageDecrease
  /// 规则单独给出。
  static MileageSegmentReport analyzeMileageSegments(
    List<RefuelRecordModel> records,
  ) {
    if (records.isEmpty) {
      return const MileageSegmentReport(segments: [], breaks: []);
    }

    final sorted = List<RefuelRecordModel>.from(records)
      ..removeWhere((r) => r.hasInvalidDate)
      ..sort((a, b) {
        final c = a.refuelDate.compareTo(b.refuelDate);
        if (c != 0) return c;
        return a.mileage.compareTo(b.mileage);
      });

    final segments = <MileageSegment>[];
    final breaks = <MileageBreak>[];
    var segmentStart = 0;
    var segmentDistance = 0.0;

    void closeSegment(int endIndex) {
      segments.add(
        MileageSegment(
          startIndex: segmentStart,
          endIndex: endIndex,
          distance: segmentDistance,
        ),
      );
      segmentStart = endIndex + 1;
      segmentDistance = 0.0;
    }

    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];
      final delta = curr.mileage - prev.mileage;

      // 用户确认换表/新基准：显式断点
      if (curr.isOdometerReset) {
        closeSegment(i - 1);
        breaks.add(
          MileageBreak(
            previousIndex: i - 1,
            currentIndex: i,
            kind: MileageContinuity.odometerReset,
          ),
        );
        continue;
      }

      if (delta < 0) {
        // 未确认的回拨：停止跨断点累计，后续记录从新基准开始
        closeSegment(i - 1);
        breaks.add(
          MileageBreak(
            previousIndex: i - 1,
            currentIndex: i,
            kind: MileageContinuity.rollback,
          ),
        );
        continue;
      }

      // 漏记记录：里程差仍真实，不切段，只照常累计
      if (delta > 0) segmentDistance += delta;
    }

    // 收尾段
    segments.add(
      MileageSegment(
        startIndex: segmentStart,
        endIndex: sorted.length - 1,
        distance: segmentDistance,
      ),
    );

    return MileageSegmentReport(segments: segments, breaks: breaks);
  }
}
