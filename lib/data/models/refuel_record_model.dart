/// 导入源油耗的数据质量分级
class SourceDataQuality {
  /// 源文件明确给出了可用数值
  static const reported = 'reported';

  /// 源文件标注为估算（如"数据丢失，预估"）
  static const estimated = 'estimated';

  /// 源文件该字段不可用（如 -1.00、空值）
  static const unavailable = 'unavailable';

  /// 是否为不能用于对照的取值
  static bool isUnusable(String? quality) =>
      quality == null || quality == unavailable || quality == estimated;
}

/// 加油记录数据实体模型（对标小熊油耗记账标准）
class RefuelRecordModel {
  final String id; // 记录唯一主键 UUID
  final String vehicleId; // 所属车辆 ID
  final DateTime refuelDate; // 加油日期时间
  final double mileage; // 当前仪表盘总里程 (km)
  final double fuelAmount; // 本次加油升数 (L)
  final double unitPrice; // 燃油单价 (¥/L)
  final double totalPrice; // 本次实付总金额 (¥)
  final String fuelType; // 燃油标号类型 (92#, 95# 等)
  final String? gasStation; // 加油站名称/位置 (如 中石化朝阳站)
  final bool isFullTank; // 是否加满（小熊油耗计算基准：加满跳枪）
  final bool isForgotPrevious; // 是否漏记了前一次加油（漏记则作为新起点断点）

  /// 用户确认"更换里程表 / 里程新基准" (P1-06)。
  ///
  /// 表显回拨既可能是录入错误，也可能是换表；两者从数据本身无法区分，
  /// 因此检测到回拨时统计层先统一按断点隔断，由用户在此字段上显式
  /// 确认换表。已确认的记录作为新里程基准，其后周期可正常计算。
  final bool isOdometerReset;
  final double? discountAmount; // 优惠金额 (¥)：机显金额与实付金额的差额，仅作参考记录
  final bool? fuelWarningLightOn; // 加油时油量警告灯是否点亮（null = 未记录）
  final String? note; // 备注说明 (如：全程空调、高速占比80%)

  // 计算输出属性（由 FuelCalculator 动态计算并填充，不作为必填输入）
  double? fuelConsumption; // 本地重算的区间百公里油耗 (L/100km)
  double? costPerKm; // 本次区间每公里成本 (¥/km)
  double? distance; // 本次行驶区间里程 (km)

  /// 导入源文件自带的油耗值（L/100km），仅作参考。
  ///
  /// 小熊油耗的口径与本应用的周期算法可能不同，因此必须与本地重算值
  /// 分开保存，不得互相覆盖。
  final double? sourceFuelConsumption;

  /// 源油耗的数据质量，取值见 [SourceDataQuality]。
  final String? sourceDataQuality;

  final DateTime createdAt; // 记录创建时间

  /// 原始加油日期无法解析。
  ///
  /// 为保持 refuelDate 非空（排序、格式化等大量代码依赖它），解析失败时
  /// 仍回落到当前时间，但必须打上此标记：带标记的记录不得参与任何按日期
  /// 的统计，并应在恢复/导入报告中列出。
  final bool hasInvalidDate;

  RefuelRecordModel({
    required this.id,
    required this.vehicleId,
    required this.refuelDate,
    required this.mileage,
    required this.fuelAmount,
    required this.unitPrice,
    required this.totalPrice,
    required this.fuelType,
    this.gasStation,
    this.isFullTank = true,
    this.isForgotPrevious = false,
    this.isOdometerReset = false,
    this.discountAmount,
    this.fuelWarningLightOn,
    this.note,
    this.fuelConsumption,
    this.costPerKm,
    this.distance,
    DateTime? createdAt,
    this.hasInvalidDate = false,
    this.sourceFuelConsumption,
    this.sourceDataQuality,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 转换为 Map 存入 SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vehicle_id': vehicleId,
      'refuel_date': refuelDate.toIso8601String(),
      'mileage': mileage,
      'fuel_amount': fuelAmount,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'fuel_type': fuelType,
      'gas_station': gasStation,
      'is_full_tank': isFullTank ? 1 : 0,
      'is_forgot_previous': isForgotPrevious ? 1 : 0,
      'is_odometer_reset': isOdometerReset ? 1 : 0,
      'discount_amount': discountAmount,
      'fuel_warning_light': fuelWarningLightOn == null
          ? null
          : (fuelWarningLightOn! ? 1 : 0),
      'note': note,
      'fuel_consumption': fuelConsumption,
      'cost_per_km': costPerKm,
      'distance': distance,
      'source_fuel_consumption': sourceFuelConsumption,
      'source_data_quality': sourceDataQuality,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 从 SQLite Map 映射还原
  factory RefuelRecordModel.fromMap(Map<String, dynamic> map) {
    final parsedRefuelDate = DateTime.tryParse(
      map['refuel_date'] as String? ?? '',
    );
    final parsedCreatedAt = DateTime.tryParse(
      map['created_at'] as String? ?? '',
    );
    return RefuelRecordModel(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      // 非法日期不再静默变成"现在"，而是打上标记由调用方决定是否采用。
      refuelDate: parsedRefuelDate ?? DateTime.now(),
      hasInvalidDate: parsedRefuelDate == null,
      mileage: (map['mileage'] as num).toDouble(),
      fuelAmount: (map['fuel_amount'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      fuelType: map['fuel_type'] as String? ?? '92# 汽油',
      gasStation: map['gas_station'] as String?,
      isFullTank: (map['is_full_tank'] as int?) == 1,
      isForgotPrevious: (map['is_forgot_previous'] as int?) == 1,
      isOdometerReset: (map['is_odometer_reset'] as int?) == 1,
      discountAmount: (map['discount_amount'] as num?)?.toDouble(),
      fuelWarningLightOn: map['fuel_warning_light'] == null
          ? null
          : (map['fuel_warning_light'] as int) == 1,
      note: map['note'] as String?,
      fuelConsumption: (map['fuel_consumption'] as num?)?.toDouble(),
      costPerKm: (map['cost_per_km'] as num?)?.toDouble(),
      distance: (map['distance'] as num?)?.toDouble(),
      sourceFuelConsumption: (map['source_fuel_consumption'] as num?)
          ?.toDouble(),
      sourceDataQuality: map['source_data_quality'] as String?,
      createdAt: parsedCreatedAt ?? DateTime.now(),
    );
  }

  /// 复制并更新部分属性。
  ///
  /// 可空字段使用显式包装，允许调用方传入 null 清空旧值；未传参数则保留原值。
  RefuelRecordModel copyWith({
    String? id,
    String? vehicleId,
    DateTime? refuelDate,
    double? mileage,
    double? fuelAmount,
    double? unitPrice,
    double? totalPrice,
    String? fuelType,
    Object? gasStation = _copyWithUnset,
    bool? isFullTank,
    bool? isForgotPrevious,
    bool? isOdometerReset,
    Object? discountAmount = _copyWithUnset,
    Object? fuelWarningLightOn = _copyWithUnset,
    Object? note = _copyWithUnset,
    Object? fuelConsumption = _copyWithUnset,
    Object? costPerKm = _copyWithUnset,
    Object? distance = _copyWithUnset,
    DateTime? createdAt,
    bool? hasInvalidDate,
    Object? sourceFuelConsumption = _copyWithUnset,
    Object? sourceDataQuality = _copyWithUnset,
  }) {
    return RefuelRecordModel(
      id: id ?? this.id,
      vehicleId: vehicleId ?? this.vehicleId,
      refuelDate: refuelDate ?? this.refuelDate,
      mileage: mileage ?? this.mileage,
      fuelAmount: fuelAmount ?? this.fuelAmount,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      fuelType: fuelType ?? this.fuelType,
      gasStation: identical(gasStation, _copyWithUnset)
          ? this.gasStation
          : gasStation as String?,
      isFullTank: isFullTank ?? this.isFullTank,
      isForgotPrevious: isForgotPrevious ?? this.isForgotPrevious,
      isOdometerReset: isOdometerReset ?? this.isOdometerReset,
      discountAmount: identical(discountAmount, _copyWithUnset)
          ? this.discountAmount
          : (discountAmount as num?)?.toDouble(),
      fuelWarningLightOn: identical(fuelWarningLightOn, _copyWithUnset)
          ? this.fuelWarningLightOn
          : fuelWarningLightOn as bool?,
      note: identical(note, _copyWithUnset) ? this.note : note as String?,
      fuelConsumption: identical(fuelConsumption, _copyWithUnset)
          ? this.fuelConsumption
          : (fuelConsumption as num?)?.toDouble(),
      costPerKm: identical(costPerKm, _copyWithUnset)
          ? this.costPerKm
          : (costPerKm as num?)?.toDouble(),
      distance: identical(distance, _copyWithUnset)
          ? this.distance
          : (distance as num?)?.toDouble(),
      createdAt: createdAt ?? this.createdAt,
      hasInvalidDate: hasInvalidDate ?? this.hasInvalidDate,
      sourceFuelConsumption: identical(sourceFuelConsumption, _copyWithUnset)
          ? this.sourceFuelConsumption
          : (sourceFuelConsumption as num?)?.toDouble(),
      sourceDataQuality: identical(sourceDataQuality, _copyWithUnset)
          ? this.sourceDataQuality
          : sourceDataQuality as String?,
    );
  }
}

const Object _copyWithUnset = Object();
