// 账本审查规则库领域模型。
//
// 一套规则（AuditRuleSet）由若干条规则配置（AuditRuleConfig）组成；
// 每条规则有独立开关与阈值参数。内置一套默认规则，可编辑、可恢复默认，
// 也可新建多套规则并切换激活套件。审查引擎按激活套件执行。

/// 规则类型常量（与规则引擎的发现类型一一对应）
class AuditRuleType {
  static const String amountMismatch = 'amount_mismatch'; // 金额与量价不匹配
  static const String mileageDecrease = 'mileage_decrease'; // 里程回退
  static const String mileageDuplicate = 'mileage_duplicate'; // 重复里程
  static const String mileageJump = 'mileage_jump'; // 里程跳跃过大
  static const String duplicateRecord = 'duplicate_record'; // 高度相似记录
  static const String tankOverflow = 'tank_overflow'; // 超过油箱容量
  static const String unitPriceDifference = 'unit_price_difference'; // 与接口价差
  static const String consumptionAnomaly = 'consumption_anomaly'; // 油耗偏离
  static const String futureDate = 'future_date'; // 未来日期

  static const List<String> all = [
    amountMismatch,
    mileageDecrease,
    mileageDuplicate,
    mileageJump,
    duplicateRecord,
    tankOverflow,
    unitPriceDifference,
    consumptionAnomaly,
    futureDate,
  ];

  static String label(String type) {
    switch (type) {
      case amountMismatch:
        return '金额与量价不匹配';
      case mileageDecrease:
        return '里程回退';
      case mileageDuplicate:
        return '里程重复';
      case mileageJump:
        return '里程跳跃过大';
      case duplicateRecord:
        return '疑似重复记录';
      case tankOverflow:
        return '加油量超过油箱容量';
      case unitPriceDifference:
        return '与接口价格差异';
      case consumptionAnomaly:
        return '油耗偏离个人中位数';
      case futureDate:
        return '加油日期来自未来';
      default:
        return type;
    }
  }

  /// 规则检查内容的简短说明（设置页展示用）
  static String description(String type) {
    switch (type) {
      case amountMismatch:
        return '实付金额与"加油量 × 单价"的差异超过容差时提示';
      case mileageDecrease:
        return '本条里程表读数小于上一条记录时提示';
      case mileageDuplicate:
        return '相邻两条记录里程完全相同时提示';
      case mileageJump:
        return '相邻记录间隔里程超过阈值时提示可能漏记';
      case duplicateRecord:
        return '日期、里程、油量与金额完全一致的重复保存提示';
      case tankOverflow:
        return '单次加油量超过油箱容量一定倍数时提示';
      case unitPriceDifference:
        return '账单单价与接口同期价格差异超过阈值时提示（需在线油价）';
      case consumptionAnomaly:
        return '单次油耗高于/低于个人中位数一定倍数时提示';
      case futureDate:
        return '加油日期晚于当前时间一定天数时提示';
      default:
        return '';
    }
  }

  const AuditRuleType._();
}

/// 规则阈值参数的可编辑规格（设置页据此生成输入项）
class AuditRuleParamSpec {
  final String key;
  final String label;
  final double defaultValue;
  final double min;
  final double max;
  final int decimals;
  final String unit;

  const AuditRuleParamSpec({
    required this.key,
    required this.label,
    required this.defaultValue,
    required this.min,
    required this.max,
    this.decimals = 2,
    this.unit = '',
  });
}

/// 每类规则的可编辑参数规格
const Map<String, List<AuditRuleParamSpec>> auditRuleParamSpecs = {
  AuditRuleType.amountMismatch: [
    AuditRuleParamSpec(
      key: 'tolerance',
      label: '金额容差',
      defaultValue: 0.02,
      min: 0,
      max: 1,
      unit: '元',
    ),
  ],
  AuditRuleType.mileageJump: [
    AuditRuleParamSpec(
      key: 'threshold',
      label: '间隔里程阈值',
      defaultValue: 2000,
      min: 100,
      max: 10000,
      decimals: 0,
      unit: 'km',
    ),
  ],
  AuditRuleType.tankOverflow: [
    AuditRuleParamSpec(
      key: 'factor',
      label: '油箱容量倍数',
      defaultValue: 1.1,
      min: 1,
      max: 2,
    ),
  ],
  AuditRuleType.unitPriceDifference: [
    AuditRuleParamSpec(
      key: 'threshold',
      label: '价差阈值',
      defaultValue: 0.30,
      min: 0.05,
      max: 2,
      unit: '元/升',
    ),
  ],
  AuditRuleType.consumptionAnomaly: [
    AuditRuleParamSpec(
      key: 'highFactor',
      label: '高于中位数倍数',
      defaultValue: 1.35,
      min: 1.1,
      max: 3,
    ),
    AuditRuleParamSpec(
      key: 'lowFactor',
      label: '低于中位数倍数',
      defaultValue: 0.65,
      min: 0.1,
      max: 0.9,
    ),
  ],
  AuditRuleType.futureDate: [
    AuditRuleParamSpec(
      key: 'allowedDays',
      label: '允许补录天数',
      defaultValue: 2,
      min: 0,
      max: 7,
      decimals: 0,
      unit: '天',
    ),
  ],
};

/// 单条规则配置：开关 + 阈值参数
class AuditRuleConfig {
  final String type;
  final bool enabled;
  final Map<String, double> params;

  const AuditRuleConfig({
    required this.type,
    this.enabled = true,
    this.params = const {},
  });

  /// 以内置默认参数生成一条规则
  factory AuditRuleConfig.defaultFor(String type, {bool enabled = true}) {
    final specs = auditRuleParamSpecs[type] ?? const [];
    return AuditRuleConfig(
      type: type,
      enabled: enabled,
      params: {for (final s in specs) s.key: s.defaultValue},
    );
  }

  double param(String key) => params[key] ?? _defaultParam(key);

  static double _defaultParam(String key) {
    for (final specs in auditRuleParamSpecs.values) {
      for (final s in specs) {
        if (s.key == key) return s.defaultValue;
      }
    }
    return 0;
  }

  AuditRuleConfig copyWith({bool? enabled, Map<String, double>? params}) =>
      AuditRuleConfig(
        type: type,
        enabled: enabled ?? this.enabled,
        params: params ?? Map<String, double>.from(this.params),
      );

  Map<String, dynamic> toJson() => {
    'type': type,
    'enabled': enabled,
    'params': params,
  };

  static AuditRuleConfig? fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String || !AuditRuleType.all.contains(type)) return null;
    final rawParams = json['params'];
    final params = <String, double>{};
    if (rawParams is Map) {
      rawParams.forEach((k, v) {
        if (v is num) params['$k'] = v.toDouble();
      });
    }
    return AuditRuleConfig(
      type: type,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      params: params,
    );
  }
}

/// 一套完整的审查规则
class AuditRuleSet {
  static const String builtinId = 'builtin_default';

  final String id;
  String name;
  final bool isBuiltin;
  List<AuditRuleConfig> rules;

  AuditRuleSet({
    required this.id,
    required this.name,
    this.isBuiltin = false,
    required this.rules,
  });

  /// 内置默认规则：全部开启、参数为引擎默认阈值
  factory AuditRuleSet.builtinDefault() => AuditRuleSet(
    id: builtinId,
    name: '默认规则',
    isBuiltin: true,
    rules: [
      for (final type in AuditRuleType.all) AuditRuleConfig.defaultFor(type),
    ],
  );

  /// 以某套规则为模板复制一套新规则
  factory AuditRuleSet.copyFrom(
    AuditRuleSet source, {
    required String id,
    required String name,
  }) => AuditRuleSet(
    id: id,
    name: name,
    rules: [
      for (final r in source.rules)
        AuditRuleConfig(
          type: r.type,
          enabled: r.enabled,
          params: Map.of(r.params),
        ),
    ],
  );

  AuditRuleConfig? ruleOf(String type) {
    for (final r in rules) {
      if (r.type == type) return r;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isBuiltin': isBuiltin,
    'rules': rules.map((r) => r.toJson()).toList(),
  };

  static AuditRuleSet? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    final rawRules = json['rules'];
    final rules = <AuditRuleConfig>[];
    if (rawRules is List) {
      for (final item in rawRules) {
        if (item is Map) {
          final config = AuditRuleConfig.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (config != null) rules.add(config);
        }
      }
    }
    // 补齐缺失的规则类型，保证升级后旧数据也能完整执行
    for (final type in AuditRuleType.all) {
      if (!rules.any((r) => r.type == type)) {
        rules.add(AuditRuleConfig.defaultFor(type));
      }
    }
    return AuditRuleSet(
      id: id,
      name: name,
      isBuiltin: json['isBuiltin'] is bool
          ? json['isBuiltin'] as bool
          : id == builtinId,
      rules: rules,
    );
  }
}
