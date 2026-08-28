import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/date_formatter.dart';

/// 非全屏迷你自定义日期范围拾取弹窗（尽可能少占用屏幕空间，快捷高效）
class CompactDateRangeDialog extends StatefulWidget {
  final DateTimeRange? initialRange;
  final DateTime firstDate;
  final DateTime lastDate;

  const CompactDateRangeDialog({
    super.key,
    this.initialRange,
    required this.firstDate,
    required this.lastDate,
  });

  /// 静态快捷呼出方法
  static Future<DateTimeRange?> show(
    BuildContext context, {
    DateTimeRange? initialRange,
  }) {
    return showDialog<DateTimeRange>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CompactDateRangeDialog(
        initialRange: initialRange,
        firstDate: DateTime(2010),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      ),
    );
  }

  @override
  State<CompactDateRangeDialog> createState() => _CompactDateRangeDialogState();
}

class _CompactDateRangeDialogState extends State<CompactDateRangeDialog> {
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate =
        widget.initialRange?.start ?? now.subtract(const Duration(days: 90));
    _endDate = widget.initialRange?.end ?? now;
  }

  void _applyQuickPreset(Duration duration) {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    setState(() {
      _endDate = now;
      _startDate = now.subtract(duration);
    });
  }

  void _applyThisYear() {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, 1, 1);
      _endDate = now;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    HapticFeedback.selectionClick();
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      helpText: isStart ? '选择起始日期' : '选择截止日期',
      cancelText: '取消',
      confirmText: '确定',
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(AppIcons.date_range,
                        color: Color(0xFFFF5A24), size: 20),
                    SizedBox(width: 8),
                    Text(
                      '自定义时间范围',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(AppIcons.close,
                        size: 18, color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 2. 快捷预设胶囊标签
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildPresetChip(
                    '近30天', () => _applyQuickPreset(const Duration(days: 30))),
                _buildPresetChip(
                    '近90天', () => _applyQuickPreset(const Duration(days: 90))),
                _buildPresetChip(
                    '近半年', () => _applyQuickPreset(const Duration(days: 183))),
                _buildPresetChip('今年', _applyThisYear),
              ],
            ),
            const SizedBox(height: 16),

            // 3. 起止日期选择卡片
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: colors.outline.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(isStart: true),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('起始日期',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: colors.onSurfaceVariant)),
                          const SizedBox(height: 3),
                          Text(
                            DateFormatter.formatChineseYmd(_startDate),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(AppIcons.arrow_forward,
                        size: 16, color: colors.onSurfaceVariant),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(isStart: false),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('截止日期',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: colors.onSurfaceVariant)),
                          const SizedBox(height: 3),
                          Text(
                            DateFormatter.formatChineseYmd(_endDate),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 4. 底部操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(
                      context,
                      DateTimeRange(start: _startDate, end: _endDate),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5A24),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                  child: const Text('确定应用',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5A24).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFFF5A24),
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
