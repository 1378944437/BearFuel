/// 燃油标号类型定义（专注燃油车/混动车型）
class FuelType {
  static const String gas92 = '92# 汽油';
  static const String gas95 = '95# 汽油';
  static const String gas98 = '98# 汽油';
  static const String diesel = '0# 柴油';

  /// 全部支持的燃油类型列表
  static const List<String> allTypes = [
    gas92,
    gas95,
    gas98,
    diesel,
  ];
}

/// 车辆其他费用类型分类
class ExpenseCategory {
  static const String maintenance = '保养维护';
  static const String insurance = '车辆保险';
  static const String inspection = '年检验车';
  static const String parking = '停车费用';
  static const String carWash = '洗车美容';
  static const String toll = '过路路桥';
  static const String repair = '故障维修';
  static const String fine = '违章罚款';
  static const String decoration = '改装用品';
  static const String other = '其它杂费';

  /// 全部费用分类列表
  static const List<String> allCategories = [
    maintenance,
    insurance,
    inspection,
    parking,
    carWash,
    toll,
    repair,
    fine,
    decoration,
    other,
  ];
}
