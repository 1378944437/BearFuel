import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';

/// 应用统一的紧凑日期选择弹窗。
///
/// 与系统默认 DatePicker 相比：尺寸紧凑、配色跟随品牌主题
/// （周一为首列、选中日为品牌橙圆底）。
class AppDatePicker {
  AppDatePicker._();

  static const List<String> _weekdayLabels = [
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  /// 弹出日期选择，返回所选日期（当日 00:00），取消返回 null。
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    String title = '选择日期',
  }) {
    return showDialog<DateTime>(
      context: context,
      builder: (_) => _AppDatePickerDialog(
        title: title,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
  }
}

class _AppDatePickerDialog extends StatefulWidget {
  final String title;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _AppDatePickerDialog({
    required this.title,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_AppDatePickerDialog> createState() => _AppDatePickerDialogState();
}

class _AppDatePickerDialogState extends State<_AppDatePickerDialog> {
  late DateTime _selected; // 所选日期（00:00）
  late int _year;
  late int _month;

  static const Color _brand = AppBrandColors.brand;

  @override
  void initState() {
    super.initState();
    _selected = _dateOnly(
      widget.initialDate.clampDate(from: widget.firstDate, to: widget.lastDate),
    );
    _year = _selected.year;
    _month = _selected.month;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isBeforeRange(DateTime d) => d.isBefore(_dateOnly(widget.firstDate));

  bool _isAfterRange(DateTime d) => d.isAfter(_dateOnly(widget.lastDate));

  bool _inRange(DateTime d) => !_isBeforeRange(d) && !_isAfterRange(d);

  bool _monthIntersectsRange(int year, int month) {
    final firstOfMonth = DateTime(year, month, 1);
    final lastOfMonth = DateTime(year, month + 1, 0);
    final first = _dateOnly(widget.firstDate);
    final last = _dateOnly(widget.lastDate);
    return !firstOfMonth.isAfter(last) && !lastOfMonth.isBefore(first);
  }

  void _shiftMonth(int delta) {
    var y = _year;
    var m = _month + delta;
    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }
    if (!_monthIntersectsRange(y, m)) return;
    setState(() {
      _year = y;
      _month = m;
    });
  }

  bool get _canGoPrev => _monthIntersectsRange(_year, _month - 1);

  bool get _canGoNext => _monthIntersectsRange(_year, _month + 1);

  List<int?> _buildCells() {
    final firstOfMonth = DateTime(_year, _month, 1);
    // 周一为首列：DateTime.weekday 周一=1 … 周日=7，前置空位 = weekday-1
    final leadingBlanks = firstOfMonth.weekday - 1;
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    return [
      ...List<int?>.filled(leadingBlanks, null),
      for (var d = 1; d <= daysInMonth; d++) d,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = _dateOnly(DateTime.now());

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题与当前选中日期
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_selected.month}月${_selected.day}日 · ${_weekdayName(_selected)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _brand,
              ),
            ),
            const SizedBox(height: 8),

            // 月份切换行
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$_year年$_month月',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _NavButton(
                  icon: AppIcons.chevron_left,
                  enabled: _canGoPrev,
                  onTap: () => _shiftMonth(-1),
                ),
                _NavButton(
                  icon: AppIcons.chevron_right,
                  enabled: _canGoNext,
                  onTap: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 星期表头
            Row(
              children: [
                for (final label in AppDatePicker._weekdayLabels)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),

            // 日期网格
            for (final row in _buildRows(_buildCells()))
              Row(
                children: [
                  for (final cell in row)
                    Expanded(
                      child: cell == null
                          ? const SizedBox(height: 38)
                          : _DayCell(
                              day: cell,
                              date: DateTime(_year, _month, cell),
                              isSelected:
                                  _dateOnly(DateTime(_year, _month, cell)) ==
                                  _selected,
                              isToday:
                                  _dateOnly(DateTime(_year, _month, cell)) ==
                                  today,
                              enabled: _inRange(DateTime(_year, _month, cell)),
                              onSelect: () => setState(() {
                                _selected = DateTime(_year, _month, cell);
                              }),
                            ),
                    ),
                ],
              ),

            const SizedBox(height: 4),
            // 底部操作
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  style: TextButton.styleFrom(foregroundColor: _brand),
                  child: const Text(
                    '确定',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<List<int?>> _buildRows(List<int?> cells) {
    final rows = <List<int?>>[];
    for (var i = 0; i < cells.length; i += 7) {
      final slice = cells.sublist(
        i,
        (i + 7) > cells.length ? cells.length : i + 7,
      );
      while (slice.length < 7) {
        slice.add(null);
      }
      rows.add(slice);
    }
    return rows;
  }

  static String _weekdayName(DateTime d) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[d.weekday - 1];
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? colors.onSurface
              : colors.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final DateTime date;
  final bool isSelected;
  final bool isToday;
  final bool enabled;
  final VoidCallback onSelect;

  const _DayCell({
    required this.day,
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textColor = isSelected
        ? Colors.white
        : enabled
        ? colors.onSurface
        : colors.onSurfaceVariant.withValues(alpha: 0.35);

    return InkWell(
      borderRadius: BorderRadius.circular(19),
      onTap: enabled ? onSelect : null,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppBrandColors.brand : Colors.transparent,
            shape: BoxShape.circle,
            border: !isSelected && isToday && enabled
                ? Border.all(color: AppBrandColors.brand, width: 1.2)
                : null,
          ),
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected || isToday
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

extension on DateTime {
  /// 钳制到 [from] 与 [to]（含边界），仅比较日期部分
  DateTime clampDate({required DateTime from, required DateTime to}) {
    final thisDay = DateTime(year, month, day);
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day);
    if (thisDay.isBefore(f)) return f;
    if (thisDay.isAfter(t)) return t;
    return this;
  }
}
