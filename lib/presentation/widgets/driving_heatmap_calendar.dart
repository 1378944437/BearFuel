import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/date_formatter.dart';
import '../../domain/statistics_service.dart';
import 'custom_card.dart';

/// 365天行驶足迹热力日历组件 (GitHub-style 52周 x 7天横向流动足迹图谱)
class DrivingHeatmapCalendar extends StatefulWidget {
  final YearlyHeatmapSummary summary;

  const DrivingHeatmapCalendar({
    super.key,
    required this.summary,
  });

  @override
  State<DrivingHeatmapCalendar> createState() => _DrivingHeatmapCalendarState();
}

class _DrivingHeatmapCalendarState extends State<DrivingHeatmapCalendar> {
  DailyActivityCell? _selectedCell;

  // 5 级热力颜色梯度（由浅入深）
  static const List<Color> _lightHeatColors = [
    Color(0xFFE0E0E0), // 0级：未出车
    Color(0xFFFFCC80), // 1级：1~25km (轻度)
    Color(0xFFFF9800), // 2级：26~70km (中度)
    Color(0xFFF57C00), // 3级：71~150km (较多)
    Color(0xFFD84315), // 4级：>150km (超长途)
  ];

  static const List<Color> _darkHeatColors = [
    Color(0xFF2C2C2C), // 0级
    Color(0xFF8D531B), // 1级
    Color(0xFFBF620D), // 2级
    Color(0xFFF57C00), // 3级
    Color(0xFFFF5722), // 4级
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final heatColors = isDark ? _darkHeatColors : _lightHeatColors;

    // 将 365 天的数据按周划分（每列 7 天，从周一开始）
    final List<List<DailyActivityCell?>> weeks = [];
    List<DailyActivityCell?> currentWeek = List.filled(7, null);

    for (final cell in widget.summary.cells) {
      final weekdayIndex = cell.weekday - 1; // 0 = Mon, 6 = Sun
      currentWeek[weekdayIndex] = cell;

      if (weekdayIndex == 6) {
        weeks.add(List.from(currentWeek));
        currentWeek = List.filled(7, null);
      }
    }
    if (currentWeek.any((c) => c != null)) {
      weeks.add(currentWeek);
    }

    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 标题与核心统计
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(AppIcons.grid_on_outlined,
                      color: Color(0xFFFF5A24), size: 18),
                  const SizedBox(width: 6),
                  Text('${widget.summary.year}年 365天行驶热力日历',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5A24).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '活跃率 ${widget.summary.activeRate}%',
                  style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFFF5A24),
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('记录全年 365 天出车足迹与驾驶密度（横向滑动浏览全年）',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          const SizedBox(height: 10),

          // 2. 四大出车指标迷你胶囊
          Row(
            children: [
              _buildMiniStatChip(
                  '出车天数', '${widget.summary.activeDays}天', Colors.orange),
              const SizedBox(width: 6),
              _buildMiniStatChip(
                  '全年里程',
                  '${widget.summary.totalYearMileage.toStringAsFixed(0)}km',
                  Colors.blue),
              const SizedBox(width: 6),
              _buildMiniStatChip(
                  '单日最高',
                  '${widget.summary.maxDailyMileage.toStringAsFixed(0)}km',
                  Colors.purple),
              const SizedBox(width: 6),
              _buildMiniStatChip('连续出车',
                  '${widget.summary.maxConsecutiveActiveDays}天', Colors.teal),
            ],
          ),

          const SizedBox(height: 12),

          // 3. 52周 x 7天 横向滚动热力图谱
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 星期轴指示
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('一',
                        style: TextStyle(
                            fontSize: 9, color: colors.onSurfaceVariant)),
                    SizedBox(height: 14),
                    Text('三',
                        style: TextStyle(
                            fontSize: 9, color: colors.onSurfaceVariant)),
                    SizedBox(height: 14),
                    Text('五',
                        style: TextStyle(
                            fontSize: 9, color: colors.onSurfaceVariant)),
                    SizedBox(height: 14),
                    Text('日',
                        style: TextStyle(
                            fontSize: 9, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),

              // 横向滚动网格
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: weeks.asMap().entries.map((entry) {
                      final weekCells = entry.value;

                      return Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Column(
                          children: List.generate(7, (dayIndex) {
                            final cell = weekCells[dayIndex];
                            if (cell == null) {
                              return Container(
                                width: 11,
                                height: 11,
                                margin: const EdgeInsets.only(bottom: 3),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              );
                            }

                            final isSelected = _selectedCell?.date == cell.date;
                            final color =
                                heatColors[cell.intensityLevel.clamp(0, 4)];

                            return InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedCell = cell);
                              },
                              borderRadius: BorderRadius.circular(2),
                              child: Container(
                                width: 11,
                                height: 11,
                                margin: const EdgeInsets.only(bottom: 3),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                  border: isSelected
                                      ? Border.all(
                                          color: colors.onSurface, width: 1.5)
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 4. 图例与选定日期详情提示
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 点击查看详情卡片
              Expanded(
                child: _selectedCell != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFF5A24).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFFFF5A24)
                                  .withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '${DateFormatter.formatChineseYmd(_selectedCell!.date)}: '
                          '${_selectedCell!.mileage > 0 ? "行驶 ${_selectedCell!.mileage.toStringAsFixed(0)}km · " : ""}'
                          '${_selectedCell!.fuelAmount > 0 ? "加油 ${_selectedCell!.fuelAmount.toStringAsFixed(1)}L · " : ""}'
                          '${_selectedCell!.totalExpense > 0 ? "支出 ¥${_selectedCell!.totalExpense.toStringAsFixed(0)}" : (_selectedCell!.mileage == 0 ? "未出车" : "")}',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF5A24)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : Text('点击方块查看当日行程与加油详情',
                        style: TextStyle(
                            fontSize: 10, color: colors.onSurfaceVariant)),
              ),
              const SizedBox(width: 8),
              // 色阶图例
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('少',
                      style: TextStyle(
                          fontSize: 9, color: colors.onSurfaceVariant)),
                  const SizedBox(width: 3),
                  ...heatColors.map(
                    (c) => Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text('多',
                      style: TextStyle(
                          fontSize: 9, color: colors.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatChip(String label, String value, Color color) {
    final textColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 9, color: textColor)),
            const SizedBox(height: 1),
            Text(value,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
