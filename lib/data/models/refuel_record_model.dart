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
  final double? discountAmount; // 优惠金额 (¥)：机显金额与实付金额的差额，仅作参考记录
  final bool? fuelWarningLightOn; // 加油时油量警告灯是否点亮（null = 未记录）
  final String? note; // 备注说明 (如：全程空调、高速占比80%)

  // 计算输出属性（由 FuelCalculator 动态计算并填充，不作为必填输入）
  double? fuelConsumption; // 本次区间百公里油耗 (L/100km)
  double? costPerKm; // 本次区间每公里成本 (¥/km)
  double? distance; // 本次行驶区间里程 (km)

  final DateTime createdAt; // 记录创建时间

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
    this.discountAmount,
    this.fuelWarningLightOn,
    this.note,
    this.fuelConsumption,
    this.costPerKm,
    this.distance,
    DateTime? createdAt,
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
      'discount_amount': discountAmount,
      'fuel_warning_light': fuelWarningLightOn == null
          ? null
          : (fuelWarningLightOn!
                ? 1
                : 0),
      'note': note,
      'fuel_consumption': fuelConsumption,
      'cost_per_km': costPerKm,
      'distance': distance,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 从 SQLite Map 映射还原
  factory RefuelRecordModel.fromMap(Map<String, dynamic> map) {
    return RefuelRecordModel(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      refuelDate:
          DateTime.tryParse(map['refuel_date'] as String? ?? '') ??
          DateTime.now(),
      mileage: (map['mileage'] as num).toDouble(),
      fuelAmount: (map['fuel_amount'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      fuelType: map['fuel_type'] as String? ?? '92# 汽油',
      gasStation: map['gas_station'] as String?,
      isFullTank: (map['is_full_tank'] as int?) == 1,
      isForgotPrevious: (map['is_forgot_previous'] as int?) == 1,
      discountAmount: (map['discount_amount'] as num?)?.toDouble(),
      fuelWarningLightOn: map['fuel_warning_light'] == null
          ? null
          : (map['fuel_warning_light'] as int) == 1,
      note: map['note'] as String?,
      fuelConsumption: (map['fuel_consumption'] as num?)?.toDouble(),
      costPerKm: (map['cost_per_km'] as num?)?.toDouble(),
      distance: (map['distance'] as num?)?.toDouble(),
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// 复制并更新部分属性
  RefuelRecordModel copyWith({
    String? id,
    String? vehicleId,
    DateTime? refuelDate,
    double? mileage,
    double? fuelAmount,
    double? unitPrice,
    double? totalPrice,
    String? fuelType,
    String? gasStation,
    bool? isFullTank,
    bool? isForgotPrevious,
    double? discountAmount,
    bool? fuelWarningLightOn,
    String? note,
    double? fuelConsumption,
    double? costPerKm,
    double? distance,
    DateTime? createdAt,
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
      gasStation: gasStation ?? this.gasStation,
      isFullTank: isFullTank ?? this.isFullTank,
      isForgotPrevious: isForgotPrevious ?? this.isForgotPrevious,
      discountAmount: discountAmount ?? this.discountAmount,
      fuelWarningLightOn: fuelWarningLightOn ?? this.fuelWarningLightOn,
      note: note ?? this.note,
      fuelConsumption: fuelConsumption ?? this.fuelConsumption,
      costPerKm: costPerKm ?? this.costPerKm,
      distance: distance ?? this.distance,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
