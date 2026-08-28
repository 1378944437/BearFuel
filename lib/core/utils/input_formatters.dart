import 'package:flutter/services.dart';

/// 全局输入框格式限制器与文本转换工具
class AppInputFormatters {
  /// 限制仅允许非负数值，且最多保留 2 位小数
  static final TextInputFormatter decimal2 = FilteringTextInputFormatter.allow(
    RegExp(r'^\d+\.?\d{0,2}'),
  );

  /// 限制仅允许正整数
  static final TextInputFormatter integerOnly =
      FilteringTextInputFormatter.digitsOnly;

  /// 限制最大字符长度
  static TextInputFormatter maxChars(int maxLength) =>
      LengthLimitingTextInputFormatter(maxLength);

  /// 加油站名称限制（最多 40 字符）
  static final TextInputFormatter stationName =
      LengthLimitingTextInputFormatter(40);

  /// 备注说明限制（最多 100 字符）
  static final TextInputFormatter note = LengthLimitingTextInputFormatter(100);

  /// 车牌序号限制（仅限数字与大写英文字母，最多 8 位）
  static final List<TextInputFormatter> plateNumber = [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
    LengthLimitingTextInputFormatter(8),
    UpperCaseTextFormatter(),
  ];
}

/// 自动将输入英文字母转换为大写的格式化器
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
