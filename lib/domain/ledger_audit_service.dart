import '../../data/models/refuel_record_model.dart';
import '../../data/services/apizero_fuel_price_service.dart';

/// 本地规则引擎产出的发现（尚未落库）
class RuleFinding {
  final String? recordId;
  final String findingType;
  final String severity;
  final String title;
  final String explanation;
  final String? suggestion;
  final Map<String, dynamic>? evidence;
  final List<Map<String, dynamic>> suggestedChanges;
  final String dataHash;

  const RuleFinding({
    required this.recordId,
    required this.findingType,
    required this.severity,
    required this.title,
    required this.explanation,
    this.suggestion,
    this.evidence,
    this.suggestedChanges = const [],
    required this.dataHash,
  });
}

/// 规则发现类型常量
class LedgerFindingType {
  static const String amountMismatch = 'amount_mismatch'; // 金额与量价不匹配
  static const String mileageDecrease = 'mileage_decrease'; // 里程回退
  static const String mileageDuplicate = 'mileage_duplicate'; // 重复里程
  static const String mileageJump = 'mileage_jump'; // 里程跳跃过大
  static const String duplicateRecord = 'duplicate_record'; // 高度相似记录
  static const String tankOverflow = 'tank_overflow'; // 超过油箱容量
  static const String unitPriceDifference = 'unit_price_difference'; // 与接口价差
  static const String consumptionAnomaly = 'consumption_anomaly'; // 油耗偏离
  static const String futureDate = 'future_date'; // 未来日期

  const LedgerFindingType._();
}

/// 账本本地确定性规则审查引擎。
///
/// 只做代码可以准确判断的硬校验；发现异常仅提示，不修改任何原始数据。
/// 复杂解释与修正建议交由 AI（见 AiAuditService），用户确认后才允许修改。
class LedgerAuditService {
  LedgerAuditService._();

  /// 金额与"量 × 价"允许的最大误差（处理两位小数四舍五入）
  static const double amountTolerance = 0.02;

  /// 与接口价格差异超过该值（元/升）时提示待确认
  static const double unitPriceDifferenceThreshold = 0.30;

  /// 油价对比窗口：加油日期与接口调价日期相差不超过该天数
  static const int priceCompareWindowDays = 16;

  /// 相邻记录里程跳跃提示阈值（km）
  static const double mileageJumpThreshold = 2000;

  /// 加油量超过油箱容量该倍数时提示
  static const double tankOverflowFactor = 1.1;

  /// 油耗偏离个人中位数的倍数阈值
  static const double consumptionHighFactor = 1.35;
  static const double consumptionLowFactor = 0.65;

  /// 记录数据指纹（FNV-1a），用于同一记录变更后要求重新审查
  static String hashRecord(RefuelRecordModel r) {
    final basis =
        '${r.refuelDate.toIso8601String()}|${r.mileage}|${r.fuelAmount}'
        '|${r.unitPrice}|${r.totalPrice}|${r.fuelType}|${r.isFullTank}'
        '|${r.isForgotPrevious}|${r.gasStation ?? ''}';
    var hash = 0x811c9dc5;
    for (final code in basis.codeUnits) {
      hash ^= code & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
      hash ^= (code >> 8) & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// 对（按时间排序的）记录集合执行全部本地规则
  static List<RuleFinding> runLocalRules({
    required List<RefuelRecordModel> records,
    required String Function(RefuelRecordModel record) dataHashOf,
    double? tankCapacity,
    ApiZeroFuelPriceSnapshot? priceSnapshot,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final sorted = List<RefuelRecordModel>.from(records)
      ..sort((a, b) => a.refuelDate.compareTo(b.refuelDate));

    final findings = <RuleFinding>[
      ..._checkDates(sorted, dataHashOf, clock),
      ..._checkAmounts(sorted, dataHashOf),
      ..._checkMileages(sorted, dataHashOf),
      ..._checkDuplicates(sorted, dataHashOf),
      ..._checkTankOverflow(sorted, dataHashOf, tankCapacity),
      ..._checkPriceAgainstApi(sorted, dataHashOf, priceSnapshot),
      ..._checkConsumptionAnomaly(sorted, dataHashOf),
    ];
    return findings;
  }

  // ------------------------------------------------------------------
  // 规则 5.7 日期异常
  // ------------------------------------------------------------------
  static List<RuleFinding> _checkDates(
    List<RefuelRecordModel> sorted,
    String Function(RefuelRecordModel record) dataHashOf,
    DateTime now,
  ) {
    final findings = <RuleFinding>[];
    for (final r in sorted) {
      // 允许补录到明天（与账本页"允许明天"的口径一致）
      if (r.refuelDate.isAfter(now.add(const Duration(days: 2)))) {
        findings.add(
          RuleFinding(
            recordId: r.id,
            findingType: LedgerFindingType.futureDate,
            severity: 'warning',
            title: '加油日期来自未来',
            explanation:
                '该记录的加油时间（${r.refuelDate.toIso8601String().substring(0, 10)}）晚于当前时间，可能选错了日期。',
            suggestion: '请核对加油小票的日期后修正。',
            dataHash: dataHashOf(r),
          ),
        );
      }
    }
    return findings;
  }

  // ------------------------------------------------------------------
  // 规则 5.1 金额计算异常
  // ------------------------------------------------------------------
  static List<RuleFinding> _checkAmounts(
    List<RefuelRecordModel> sorted,
    String Function(RefuelRecordModel record) dataHashOf,
  ) {
    final findings = <RuleFinding>[];
    for (final r in sorted) {
      if (r.fuelAmount <= 0 || r.unitPrice <= 0 || r.totalPrice <= 0) continue;
      final expected = r.fuelAmount * r.unitPrice;
      final diff = (r.totalPrice - expected).abs();
      if (diff > amountTolerance) {
        findings.add(
          RuleFinding(
            recordId: r.id,
            findingType: LedgerFindingType.amountMismatch,
            severity: 'warning',
            title: '金额与油量、单价不匹配',
            explanation:
                '按 ${r.fuelAmount.toStringAsFixed(2)}L × ${r.unitPrice.toStringAsFixed(2)}元/升 '
                '计算应约 ${expected.toStringAsFixed(2)} 元，账单金额为 '
                '${r.totalPrice.toStringAsFixed(2)} 元，相差 ${diff.toStringAsFixed(2)} 元。',
            suggestion: '请核对机显金额与实付金额：若有优惠，请填写优惠金额后再保存。',
            evidence: {
              'field': 'total_price',
              'record_value': r.totalPrice,
              'reference_value': double.parse(expected.toStringAsFixed(2)),
              'source': '量价公式（加油量 × 单价）',
            },
            suggestedChanges: [
              {
                'field': 'total_price',
                'current': r.totalPrice,
                'suggested': double.parse(expected.toStringAsFixed(2)),
              },
            ],
            dataHash: dataHashOf(r),
          ),
        );
      }
    }
    return findings;
  }

  // ------------------------------------------------------------------
  // 规则 5.2 里程异常（回退 / 重复 / 跳跃）
  // ------------------------------------------------------------------
  static List<RuleFinding> _checkMileages(
    List<RefuelRecordModel> sorted,
    String Function(RefuelRecordModel record) dataHashOf,
  ) {
    final findings = <RuleFinding>[];
    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];
      final delta = curr.mileage - prev.mileage;
      if (delta < 0) {
        findings.add(
          RuleFinding(
            recordId: curr.id,
            findingType: LedgerFindingType.mileageDecrease,
            severity: 'warning',
            title: '里程数比上一条记录更小',
            explanation:
                '本条里程 ${curr.mileage.toStringAsFixed(1)}km 小于上一条 '
                '${prev.mileage.toStringAsFixed(1)}km（${prev.refuelDate.month}/${prev.refuelDate.day}），'
                '可能是录入错误或里程表回拨。',
            suggestion: '请核对两笔记录的里程表读数。',
            evidence: {
              'field': 'mileage',
              'record_value': curr.mileage,
              'reference_value': prev.mileage,
              'source': '上一条账单',
              'reference_date': prev.refuelDate.toIso8601String().substring(
                0,
                10,
              ),
            },
            dataHash: dataHashOf(curr),
          ),
        );
      } else if (delta == 0 && curr.mileage > 0) {
        findings.add(
          RuleFinding(
            recordId: curr.id,
            findingType: LedgerFindingType.mileageDuplicate,
            severity: 'info',
            title: '与上一条记录里程相同',
            explanation:
                '本条与上一条记录的里程均为 ${curr.mileage.toStringAsFixed(1)}km，'
                '同一里程加两次油通常意味着有记录漏项或重复。',
            suggestion: '请确认是否重复记录，或是否漏记了中间那次加油。',
            dataHash: dataHashOf(curr),
          ),
        );
      } else if (delta > mileageJumpThreshold) {
        findings.add(
          RuleFinding(
            recordId: curr.id,
            findingType: LedgerFindingType.mileageJump,
            severity: 'info',
            title: '与上一条记录间隔里程较大',
            explanation:
                '两条记录间隔 ${delta.toStringAsFixed(0)}km，若期间有未记录的加油，'
                '请补记并勾选"漏记了前一次加油"，以免区间油耗失真。',
            dataHash: dataHashOf(curr),
          ),
        );
      }
    }
    return findings;
  }

  // ------------------------------------------------------------------
  // 规则 5.5 高度相似的重复记录
  // ------------------------------------------------------------------
  static List<RuleFinding> _checkDuplicates(
    List<RefuelRecordModel> sorted,
    String Function(RefuelRecordModel record) dataHashOf,
  ) {
    final findings = <RuleFinding>[];
    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];
      final sameMinute =
          curr.refuelDate.difference(prev.refuelDate).abs() <
          const Duration(minutes: 1);
      final sameMileage = (curr.mileage - prev.mileage).abs() < 0.05;
      final sameAmount = (curr.fuelAmount - prev.fuelAmount).abs() < 0.01;
      final sameTotal = (curr.totalPrice - prev.totalPrice).abs() < 0.01;
      if (sameMinute && sameMileage && sameAmount && sameTotal) {
        findings.add(
          RuleFinding(
            recordId: curr.id,
            findingType: LedgerFindingType.duplicateRecord,
            severity: 'warning',
            title: '疑似重复记录',
            explanation:
                '本条与 ${prev.refuelDate.month}/${prev.refuelDate.day} '
                '${prev.refuelDate.hour.toString().padLeft(2, '0')}:'
                '${prev.refuelDate.minute.toString().padLeft(2, '0')} 的记录'
                '日期、里程、油量与金额完全一致，可能是重复保存。',
            suggestion: '确认重复后可删除其中一条（账本左滑删除）。',
            dataHash: dataHashOf(curr),
          ),
        );
      }
    }
    return findings;
  }

  // ------------------------------------------------------------------
  // 规则 5.6 油箱容量异常
  // ------------------------------------------------------------------
  static List<RuleFinding> _checkTankOverflow(
    List<RefuelRecordModel> sorted,
    String Function(RefuelRecordModel record) dataHashOf,
    double? tankCapacity,
  ) {
    if (tankCapacity == null || tankCapacity <= 0) return const [];
    final findings = <RuleFinding>[];
    for (final r in sorted) {
      if (r.fuelAmount > tankCapacity * tankOverflowFactor) {
        findings.add(
          RuleFinding(
            recordId: r.id,
            findingType: LedgerFindingType.tankOverflow,
            severity: 'warning',
            title: '加油量超过油箱容量',
            explanation:
                '本次加油 ${r.fuelAmount.toStringAsFixed(2)}L 超过车辆油箱容量 '
                '${tankCapacity.toStringAsFixed(1)}L 的 ${tankOverflowFactor.toStringAsFixed(1)} 倍，'
                '可能是跨次加油（如带油桶）或录入错误。',
            suggestion: '请核对加油量；若车辆油箱容量不准确，请在"爱车"档案中修正。',
            dataHash: dataHashOf(r),
          ),
        );
      }
    }
    return findings;
  }

  // ------------------------------------------------------------------
  // 规则 5.4 账单单价与接口价格差异
  // ------------------------------------------------------------------
  static List<RuleFinding> _checkPriceAgainstApi(
    List<RefuelRecordModel> sorted,
    String Function(RefuelRecordModel record) dataHashOf,
    ApiZeroFuelPriceSnapshot? priceSnapshot,
  ) {
    if (priceSnapshot == null || !priceSnapshot.price.isAvailable) {
      return const [];
    }
    final findings = <RuleFinding>[];
    final apiDate = priceSnapshot.price.lastChangeDate;

    double? gradePrice(String fuelType) {
      if (fuelType.contains('98')) return priceSnapshot.price.gas98;
      if (fuelType.contains('95')) return priceSnapshot.price.gas95;
      if (fuelType.contains('0#') || fuelType.contains('柴')) {
        return priceSnapshot.price.diesel0;
      }
      return priceSnapshot.price.gas92;
    }

    for (final r in sorted) {
      final reference = gradePrice(r.fuelType);
      if (reference == null || reference <= 0) continue;
      final diff = (r.unitPrice - reference).abs();
      if (diff <= unitPriceDifferenceThreshold) continue;
      // 仅对与接口调价日期相邻（±窗口）的账单做对比，避免跨调价周期的误报
      final dayGap = r.refuelDate.difference(apiDate).inDays.abs();
      if (dayGap > priceCompareWindowDays) continue;
      findings.add(
        RuleFinding(
          recordId: r.id,
          findingType: LedgerFindingType.unitPriceDifference,
          severity: 'info',
          title: '单价与同期接口价格存在较大差异',
          explanation:
              '账单单价 ${r.unitPrice.toStringAsFixed(2)}元/升，'
              '接口快照（${apiDate.month}/${apiDate.day}，${priceSnapshot.province}）为 '
              '${reference.toStringAsFixed(2)}元/升，相差 ${diff.toStringAsFixed(2)} 元/升。',
          suggestion: '可能是加油站优惠、会员折扣或录入错误，请结合小票确认；差异不自动修改账单。',
          evidence: {
            'field': 'unit_price',
            'record_value': r.unitPrice,
            'reference_value': reference,
            'source': 'ApiZero',
            'source_date': apiDate.toIso8601String().substring(0, 10),
            'province': priceSnapshot.province,
          },
          dataHash: dataHashOf(r),
        ),
      );
    }
    return findings;
  }

  // ------------------------------------------------------------------
  // 规则 5.3 油耗偏离个人中位数
  // ------------------------------------------------------------------
  static List<RuleFinding> _checkConsumptionAnomaly(
    List<RefuelRecordModel> sorted,
    String Function(RefuelRecordModel record) dataHashOf,
  ) {
    final valid = sorted
        .where(
          (r) =>
              r.fuelConsumption != null &&
              r.fuelConsumption! > 0 &&
              !r.isForgotPrevious,
        )
        .toList();
    if (valid.length < 2) return const [];

    final values = valid.map((r) => r.fuelConsumption!).toList()..sort();
    final middle = values.length ~/ 2;
    final median = values.length.isEven
        ? (values[middle - 1] + values[middle]) / 2
        : values[middle];
    if (median <= 0) return const [];

    final findings = <RuleFinding>[];
    for (final r in valid) {
      final cons = r.fuelConsumption!;
      if (cons > median * consumptionHighFactor) {
        findings.add(
          RuleFinding(
            recordId: r.id,
            findingType: LedgerFindingType.consumptionAnomaly,
            severity: 'info',
            title: '油耗明显高于个人中位数',
            explanation:
                '本条油耗 ${cons.toStringAsFixed(2)}L/100km 高于个人中位数 '
                '${median.toStringAsFixed(2)} 的 ${consumptionHighFactor.toStringAsFixed(2)} 倍，'
                '可能存在漏记里程、未加满误标或驾驶工况变化。',
            suggestion: '请核对该区间的里程与油量是否准确。',
            evidence: {
              'field': 'fuel_consumption',
              'record_value': cons,
              'reference_value': double.parse(median.toStringAsFixed(2)),
              'source': '个人历史中位数',
            },
            dataHash: dataHashOf(r),
          ),
        );
      } else if (cons < median * consumptionLowFactor) {
        findings.add(
          RuleFinding(
            recordId: r.id,
            findingType: LedgerFindingType.consumptionAnomaly,
            severity: 'info',
            title: '油耗明显低于个人中位数',
            explanation:
                '本条油耗 ${cons.toStringAsFixed(2)}L/100km 低于个人中位数 '
                '${median.toStringAsFixed(2)}，若与实际驾驶感受不符，'
                '可能是加油量少记或里程多记。',
            suggestion: '请核对该笔加油量与里程读数。',
            evidence: {
              'field': 'fuel_consumption',
              'record_value': cons,
              'reference_value': double.parse(median.toStringAsFixed(2)),
              'source': '个人历史中位数',
            },
            dataHash: dataHashOf(r),
          ),
        );
      }
    }
    return findings;
  }
}
