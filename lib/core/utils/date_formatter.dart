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

  /// 解析小熊油耗/Excel 常见日期格式，失败返回 null。
  /// 支持 ISO、yyyy/MM/dd、yyyy年MM月dd日和 Excel 序列日期文本。
  static DateTime? tryParse(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    final text = dateStr.trim();
    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(.*)$').firstMatch(text);
    if (isoMatch != null) {
      final year = int.parse(isoMatch.group(1)!);
      final month = int.parse(isoMatch.group(2)!);
      final day = int.parse(isoMatch.group(3)!);
      final parsed = DateTime.tryParse(text);
      if (parsed == null ||
          parsed.year != year ||
          parsed.month != month ||
          parsed.day != day) {
        return null;
      }
      return parsed;
    }
    final normalized = text
        .replaceAll('年', '-')
        .replaceAll('月', '-')
        .replaceAll('日', '')
        .replaceAll('/', '-')
        .replaceAll('.', '-');
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?)?$',
    ).firstMatch(normalized);
    if (match != null) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final hour = int.tryParse(match.group(4) ?? '0') ?? 0;
      final minute = int.tryParse(match.group(5) ?? '0') ?? 0;
      final second = int.tryParse(match.group(6) ?? '0') ?? 0;
      final microsText = (match.group(7) ?? '').padRight(6, '0');
      final micros = microsText.isEmpty
          ? 0
          : int.tryParse(microsText.substring(0, 6)) ?? 0;
      try {
        final result = DateTime(
          year,
          month,
          day,
          hour,
          minute,
          second,
          0,
          micros,
        );
        // DateTime 会自动进位非法日期，需拒绝而不是接受修正后的日期。
        if (result.year != year || result.month != month || result.day != day) {
          return null;
        }
        return result;
      } catch (_) {
        return null;
      }
    }

    final serial = double.tryParse(text);
    if (serial != null && serial >= 20000 && serial <= 73050) {
      final wholeDays = serial.floor();
      final minutes = ((serial - wholeDays) * 24 * 60).round();
      return DateTime(
        1899,
        12,
        30,
      ).add(Duration(days: wholeDays, minutes: minutes));
    }
    return null;
  }
}
