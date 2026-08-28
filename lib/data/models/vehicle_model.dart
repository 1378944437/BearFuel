/// 车辆数据实体模型
class VehicleModel {
  final String id; // 车辆唯一主键 UUID
  final String name; // 车辆昵称（如：我的高尔夫、家用Model 3）
  final String? plateNumber; // 车牌号
  final String? brand; // 品牌（如：大众、丰田、特斯拉）
  final String? model; // 具体车型（如：高尔夫 1.4T 舒适版）
  final double tankCapacity; // 油箱容积 / 电池容量（L 或 kWh）
  final String defaultFuelType; // 默认燃油类型（如 92#、95#）
  final double initialMileage; // 初始基准里程（km）
  final bool isDefault; // 是否为当前默认选中的车辆
  final DateTime createdAt; // 创建时间

  VehicleModel({
    required this.id,
    required this.name,
    this.plateNumber,
    this.brand,
    this.model,
    this.tankCapacity = 50.0,
    this.defaultFuelType = '92# 汽油',
    this.initialMileage = 0.0,
    this.isDefault = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 转换为 Map 存入 SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'plate_number': plateNumber,
      'brand': brand,
      'model': model,
      'tank_capacity': tankCapacity,
      'default_fuel_type': defaultFuelType,
      'initial_mileage': initialMileage,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 从 SQLite Map 映射还原
  factory VehicleModel.fromMap(Map<String, dynamic> map) {
    return VehicleModel(
      id: map['id'] as String,
      name: map['name'] as String,
      plateNumber: map['plate_number'] as String?,
      brand: map['brand'] as String?,
      model: map['model'] as String?,
      tankCapacity: (map['tank_capacity'] as num?)?.toDouble() ?? 50.0,
      defaultFuelType: map['default_fuel_type'] as String? ?? '92# 汽油',
      initialMileage: (map['initial_mileage'] as num?)?.toDouble() ?? 0.0,
      isDefault: (map['is_default'] as int?) == 1,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// 复制并更新部分属性
  VehicleModel copyWith({
    String? id,
    String? name,
    String? plateNumber,
    String? brand,
    String? model,
    double? tankCapacity,
    String? defaultFuelType,
    double? initialMileage,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return VehicleModel(
      id: id ?? this.id,
      name: name ?? this.name,
      plateNumber: plateNumber ?? this.plateNumber,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      tankCapacity: tankCapacity ?? this.tankCapacity,
      defaultFuelType: defaultFuelType ?? this.defaultFuelType,
      initialMileage: initialMileage ?? this.initialMileage,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
