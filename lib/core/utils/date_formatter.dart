import 'package:intl/intl.dart';

/// 日期时间格式化工具类
class DateFormatter {
  static final DateFormat _ymdFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _ymdHmFormat = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _chineseYmdFormat = DateFormat('yyyy年MM月dd日');
  static final DateFormat _monthDayFormat = DateFormat('MM-dd');

  /// 格式化为 yyyy-MM-dd (例如 2026-08-25)
  static String formatYmd(DateTime date) {
    return _ymdFormat.format(date);
  }

  /// 格式化为 yyyy-MM-dd HH:mm (例如 2026-08-25 14:30)
  static String formatYmdHm(DateTime date) {
    return _ymdHmFormat.format(date);
  }

  /// 格式化为 yyyy年MM月dd日
  static String formatChineseYmd(DateTime date) {
    return _chineseYmdFormat.format(date);
  }

  /// 格式化为 MM-dd
  static String formatMonthDay(DateTime date) {
    return _monthDayFormat.format(date);
  }

  /// 解析字符串为 DateTime，失败返回 null
  static DateTime? tryParse(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    return DateTime.tryParse(dateStr.trim());
  }
}
