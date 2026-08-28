/// 严格边界值校验与输入防错类
class Validators {
  /// 校验非空字符串
  static String? requiredText(String? value, {String message = '此项不能为空'}) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  /// 校验正浮点数（如金额、加油升数、单价，必须 > 0）
  static String? positiveNumber(String? value, {String fieldName = '数值'}) {
    if (value == null || value.trim().isEmpty) {
      return '请输入$fieldName';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return '请输入合法的数字';
    }
    if (parsed <= 0) {
      return '$fieldName必须大于 0';
    }
    return null;
  }

  /// 校验非负浮点数（允许 >= 0，如初始里程）
  static String? nonNegativeNumber(String? value, {String fieldName = '数值'}) {
    if (value == null || value.trim().isEmpty) {
      return '请输入$fieldName';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return '请输入合法的数字';
    }
    if (parsed < 0) {
      return '$fieldName不能小于 0';
    }
    return null;
  }

  /// 校验里程数（必须为正整数或浮点数，且可设定是否必须大于上一笔里程）
  static String? mileage(String? value, {double? lastMileage}) {
    if (value == null || value.trim().isEmpty) {
      return '请输入当前总里程';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return '请输入合法的里程读数';
    }
    if (parsed <= 0) {
      return '里程必须大于 0';
    }
    if (lastMileage != null && parsed <= lastMileage) {
      return '当前里程($parsed km)必须大于上一笔里程($lastMileage km)';
    }
    return null;
  }

  /// 校验车牌号（简易规则校验）
  static String? plateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入车牌号';
    }
    final trimmed = value.trim();
    if (trimmed.length < 5 || trimmed.length > 10) {
      return '请输入有效的车牌号码';
    }
    return null;
  }
}
