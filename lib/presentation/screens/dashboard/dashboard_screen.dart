import 'package:bearfuel/core/theme/app_icons.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/vehicle_provider.dart';
import '../../../providers/refuel_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/fuel_price_provider.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../presentation/widgets/custom_card.dart';
import '../../../presentation/widgets/app_page_title.dart';
import '../refuel/add_refuel_screen.dart';
import '../expense/add_expense_screen.dart';
import '../price/national_fuel_price_screen.dart';
import '../settings/service_settings_screen.dart';

/// 首页仪表盘（小熊油耗经典微质感渐变仪表盘、调价倒计时与核心数据呈现）
class DashboardScreen extends StatelessWidget {
  final VoidCallback onNavigateToRecords;

  const DashboardScreen({super.key, required this.onNavigateToRecords});

  @override
  Widget build(BuildContext context) {
    final vehicleProv = context.watch<VehicleProvider>();
    final refuelProv = context.watch<RefuelProvider>();
    final expenseProv = context.watch<ExpenseProvider>();
    final vehicle = vehicleProv.currentVehicle;
    final summary = refuelProv.summary;
    final reminders = expenseProv.reminders;
    final records = refuelProv.records;

    return Scaffold(
      appBar: AppBar(
        title: AppPageTitle(
          title: '仪表盘',
          subtitle: vehicle?.name ?? '车辆油耗与用车成本',
        ),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.settings_outlined),
            tooltip: '服务设置',
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ServiceSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (vehicle != null) {
            await refuelProv.loadRecords(vehicle.id);
            await expenseProv.loadExpenses(
              vehicle.id,
              currentMaxMileage: refuelProv.latestMileage,
            );
          }
        },
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          children: [
            // 1. 顶部小熊油耗微质感渐变仪表盘
            _buildMainDashboardCard(
              context,
              vehicle,
              summary,
              refuelProv.latestMileage,
            ),

            // 2. 全国实时油价快报与调价倒计时横幅（实时滚动跑马灯，展示完整各标号与调价信息）
            _buildFuelPriceQuickBanner(context),

            // 3. 临期/逾期保养与保险提醒横幅
            if (reminders.isNotEmpty) _buildReminderBanner(context, reminders),

            // 4. 核心快捷操作区（记加油、记费用）
            _buildQuickActions(context),

            // 5. 近期加油流水速览
            _buildRecentActivity(context, records),
          ],
        ),
      ),
    );
  }

  /// 今日油价快报与发改委调价预警横幅（支持全文字平滑自动滚动跑马灯，完整显示各标号油价与倒计时）
  Widget _buildFuelPriceQuickBanner(BuildContext context) {
    final fuelProv = context.watch<FuelPriceProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final price = fuelProv.currentPrice;
    final forecast = fuelProv.forecast;
    final nextDateStr = DateFormatter.formatChineseYmd(
      forecast.nextAdjustmentDate,
    );
    final isStagnant = forecast.direction.contains('搁浅');
    final trendStr = isStagnant ? '搁浅' : (forecast.isIncrease ? '上涨' : '下调');
    final displayDelta = forecast.forecastDelta.abs();
    final deltaStr = isStagnant
        ? '0.00'
        : '${forecast.isIncrease ? '+' : '-'}${displayDelta.toStringAsFixed(2)}';

    final priceText = price.isAvailable
        ? '92# ¥${price.gas92.toStringAsFixed(2)} | 95# ¥${price.gas95.toStringAsFixed(2)} | 98# ¥${price.gas98.toStringAsFixed(2)} | 0#柴油 ¥${price.diesel0.toStringAsFixed(2)}'
        : '暂无在线油价';
    final forecastText = forecast.isAvailable
        ? '下轮调价窗口 $nextDateStr · 预计$trendStr $deltaStr元/L · 剩余 ${forecast.daysRemaining} 天 · ${forecast.advice}'
        : '暂无在线调价预测';
    final fullTickerText =
        '【${fuelProv.currentCity}油价】 $priceText   $forecastText';

    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NationalFuelPriceScreen(),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    AppIcons.local_gas_station,
                    color: colors.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DashboardMarqueeText(
                    text: fullTickerText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? colors.onSurface
                          : const Color(0xFF303638),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  AppIcons.arrow_forward_ios,
                  size: 14,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 经典大字微质感渐变仪表盘卡片（增加油耗表现等级徽章与当前表显快捷校准）
  Widget _buildMainDashboardCard(
    BuildContext context,
    VehicleModel? vehicle,
    dynamic summary,
    double latestMileage,
  ) {
    final hasData = summary.validCalculatedCount > 0;
    final avg = summary.averageConsumption as double;

    // 评价等级
    String levelText = '待测算';
    Color levelColor = const Color(0xFFB7C0C2);
    if (hasData) {
      if (avg <= 6.5) {
        levelText = '高效';
        levelColor = const Color(0xFF56D6A2);
      } else if (avg <= 8.5) {
        levelText = '稳定';
        levelColor = const Color(0xFF66C7D0);
      } else {
        levelText = '偏高';
        levelColor = const Color(0xFFFF9C66);
      }
    }

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF15191A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2B3234)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      '综合平均油耗',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (hasData) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: levelColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: levelColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          levelText,
                          style: TextStyle(
                            color: levelColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF212728),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF333A3C)),
                  ),
                  child: Text(
                    '已测算 ${summary.validCalculatedCount} 次',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 主油耗大字
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  hasData ? '$avg' : '--.--',
                  style: const TextStyle(
                    color: Color(0xFFFF7A3D),
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'L / 100km',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),

            // 核心附属指标
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSubMetric(
                  '每公里花费',
                  hasData ? '¥${summary.averageCostPerKm}/km' : '--',
                  const Color(0xFF66C7D0),
                ),
                _buildSubMetric(
                  '历史最佳',
                  summary.bestConsumption > 0
                      ? '${summary.bestConsumption} L'
                      : '--',
                  const Color(0xFF56D6A2),
                ),
                InkWell(
                  onTap: vehicle != null
                      ? () => _showQuickUpdateMileageDialog(
                          context,
                          vehicle,
                          latestMileage,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: _buildSubMetric(
                      '当前表显',
                      latestMileage > 0
                          ? '${latestMileage.toStringAsFixed(0)} km'
                          : (vehicle != null
                                ? '${vehicle.initialMileage.toStringAsFixed(0)} km'
                                : '--'),
                      const Color(0xFFFFC46B),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 快捷校准爱车当前表显总里程弹窗
  void _showQuickUpdateMileageDialog(
    BuildContext context,
    VehicleModel vehicle,
    double current,
  ) {
    HapticFeedback.selectionClick();
    final initialVal = current > 0
        ? current.toStringAsFixed(0)
        : vehicle.initialMileage.toStringAsFixed(0);
    final controller = TextEditingController(text: initialVal);

    showDialog(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(AppIcons.speed, color: Color(0xFFFF5A24), size: 20),
              SizedBox(width: 6),
              Text(
                '校准当前表显里程',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '爱车【${vehicle.name}】实际仪表盘里程读数：',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '表显总里程',
                  suffixText: 'km',
                  prefixIcon: Icon(AppIcons.edit_road),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final val = double.tryParse(controller.text.trim());
                if (val != null && val >= 0) {
                  final vehicleProv = context.read<VehicleProvider>();
                  final updated = VehicleModel(
                    id: vehicle.id,
                    name: vehicle.name,
                    plateNumber: vehicle.plateNumber,
                    brand: vehicle.brand,
                    model: vehicle.model,
                    tankCapacity: vehicle.tankCapacity,
                    defaultFuelType: vehicle.defaultFuelType,
                    initialMileage: val,
                    isDefault: vehicle.isDefault,
                    createdAt: vehicle.createdAt,
                  );
                  final success = await vehicleProv.updateVehicle(updated);
                  if (success && ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? '已更新【${vehicle.name}】表显里程为 ${val.toStringAsFixed(0)} km'
                              : '更新失败，请重试',
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('保存校准'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubMetric(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 保养与保险提醒 Banner
  Widget _buildReminderBanner(BuildContext context, List<dynamic> reminders) {
    final urgentOrOverdue = reminders
        .where((r) => r.isOverdue || r.isUrgent)
        .toList();
    if (urgentOrOverdue.isEmpty) return const SizedBox.shrink();

    final first = urgentOrOverdue.first;
    final isOverdue = first.isOverdue;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = isOverdue
        ? (isDark ? Colors.red[200]! : Colors.red[900]!)
        : (isDark ? Colors.orange[200]! : Colors.orange[900]!);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isOverdue
            ? (isDark ? const Color(0xFF3A2425) : const Color(0xFFFFEBEE))
            : (isDark ? const Color(0xFF3A2F1B) : const Color(0xFFFFF3E0)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOverdue
              ? Colors.redAccent.withValues(alpha: 0.4)
              : Colors.orangeAccent.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOverdue ? AppIcons.error_outline : AppIcons.warning_amber_rounded,
            color: statusColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${first.title}: ${isOverdue ? "已逾期！" : "即将到期！"}${first.remainingMileage != null ? " 距保养还剩 ${first.remainingMileage!.toStringAsFixed(0)} km" : ""}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 快捷操作区
  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddRefuelScreen()),
                );
              },
              icon: const Icon(AppIcons.local_gas_station, size: 20),
              label: const Text('记一笔加油'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5A24),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
                );
              },
              icon: const Icon(AppIcons.build_circle_outlined, size: 20),
              label: const Text('记其他费用'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1E88E5),
                side: const BorderSide(color: Color(0xFF1E88E5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 近期记录速览
  Widget _buildRecentActivity(BuildContext context, List<dynamic> records) {
    final colors = Theme.of(context).colorScheme;
    final recent = records.reversed.take(10).toList();

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '近期加油记录',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onNavigateToRecords();
                },
                child: const Text('查看全部 >', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              alignment: Alignment.center,
              child: Text(
                '暂无加油记录，点击上方按钮开始记账',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            )
          else
            ...recent.map((r) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  child: Icon(
                    AppIcons.local_gas_station,
                    color: Color(0xFFFF5A24),
                    size: 18,
                  ),
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormatter.formatChineseYmd(r.refuelDate),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '¥${r.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                subtitle: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${r.fuelAmount.toStringAsFixed(2)} L  |  ${r.fuelType}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      r.fuelConsumption != null
                          ? '${r.fuelConsumption!.toStringAsFixed(2)} L/100km'
                          : (r.isFullTank ? '基准首充' : '未加满'),
                      style: TextStyle(
                        fontSize: 11,
                        color: r.fuelConsumption != null
                            ? const Color(0xFFFF5A24)
                            : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// 首页油价与调价预警平滑自动循环跑马灯组件
class _DashboardMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _DashboardMarqueeText({required this.text, required this.style});

  @override
  State<_DashboardMarqueeText> createState() => _DashboardMarqueeTextState();
}

class _DashboardMarqueeTextState extends State<_DashboardMarqueeText> {
  late final ScrollController _scrollController;
  Timer? _scrollTimer;
  bool _isDisposed = false;
  // 文本变化时递增，使在途的滚动动画回调链整体失效，避免叠加出双循环
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMarqueeLoop();
    });
  }

  void _startMarqueeLoop() {
    if (_isDisposed || !mounted || !_scrollController.hasClients) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      // 文本没有超出单行宽度，无需滚动
      return;
    }

    final gen = _generation;
    // 匀速平滑滚动：根据内容像素宽度计算平滑时长
    final duration = Duration(
      milliseconds: (maxExtent * 45).toInt().clamp(4000, 30000),
    );

    _scrollController
        .animateTo(maxExtent, duration: duration, curve: Curves.linear)
        .then((_) {
          if (_isDisposed || !mounted || gen != _generation) return;
          // 滚动到尽头后停顿 1.5 秒再无缝回弹重滚
          _scrollTimer?.cancel();
          _scrollTimer = Timer(const Duration(milliseconds: 1500), () {
            if (_isDisposed ||
                !mounted ||
                !_scrollController.hasClients ||
                gen != _generation) {
              return;
            }
            _scrollController.jumpTo(0.0);
            _scrollTimer?.cancel();
            _scrollTimer = Timer(const Duration(milliseconds: 800), () {
              if (_isDisposed || !mounted || gen != _generation) return;
              _startMarqueeLoop();
            });
          });
        });
  }

  @override
  void didUpdateWidget(covariant _DashboardMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _generation++;
      _scrollTimer?.cancel();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _startMarqueeLoop());
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style, maxLines: 1),
    );
  }
}
