import 'package:bearfuel/core/theme/app_icons.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/models/refuel_record_model.dart';
import '../../../data/models/expense_record_model.dart';
import '../../../domain/fuel_calculator.dart';
import '../../../domain/statistics_service.dart';
import '../../../providers/refuel_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/fuel_price_provider.dart';
import '../../../providers/weather_provider.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../presentation/widgets/custom_card.dart';
import '../../../presentation/widgets/compact_date_range_dialog.dart';
import '../../../presentation/widgets/app_page_title.dart';
import '../settings/service_settings_screen.dart';

/// 全维度统计分析大屏（彻底消除双重边距浪费、优化全宽图表呈现、完善周期报表防溢出排版）
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  String _selectedRange = '全部'; // 全部, 近半年, 今年, 自定义
  DateTimeRange? _customDateRange;
  String _selectedPeriodGranularity = '月度'; // 年度, 季度, 月度
  bool _showBackToTop = false;
  bool _isAnomalyExpanded = false;
  bool _weatherRefreshQueued = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
  }

  void _onTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 350;
    if (show != _showBackToTop) {
      setState(() => _showBackToTop = show);
    }
  }

  void _scrollToTop() {
    HapticFeedback.lightImpact();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final refuelProv = context.watch<RefuelProvider>();
    final expenseProv = context.watch<ExpenseProvider>();
    final allRecords = refuelProv.records;
    final allExpenses = expenseProv.expenses;
    final now = DateTime.now();

    // 1. 根据顶部【统计周期】过滤生效的数据子集
    final List<RefuelRecordModel> records = allRecords.where((r) {
      if (_selectedRange == '近半年') {
        final age = now.difference(r.refuelDate);
        return !age.isNegative && age.inDays <= 183;
      } else if (_selectedRange == '今年') {
        return r.refuelDate.year == now.year;
      } else if (_selectedRange == '自定义' && _customDateRange != null) {
        return r.refuelDate.isAfter(
                _customDateRange!.start.subtract(const Duration(days: 1))) &&
            r.refuelDate
                .isBefore(_customDateRange!.end.add(const Duration(days: 1)));
      }
      return true;
    }).toList();

    final List<ExpenseRecordModel> expenses = allExpenses.where((e) {
      if (_selectedRange == '近半年') {
        final age = now.difference(e.expenseDate);
        return !age.isNegative && age.inDays <= 183;
      } else if (_selectedRange == '今年') {
        return e.expenseDate.year == now.year;
      } else if (_selectedRange == '自定义' && _customDateRange != null) {
        return e.expenseDate.isAfter(
                _customDateRange!.start.subtract(const Duration(days: 1))) &&
            e.expenseDate
                .isBefore(_customDateRange!.end.add(const Duration(days: 1)));
      }
      return true;
    }).toList();

    // 2. 动态实时重新计算当前选定【统计范围】内的核心四大指标
    final double rangeFuelCost =
        records.fold(0.0, (sum, r) => sum + r.totalPrice);
    final double rangeDistance =
        records.fold(0.0, (sum, r) => sum + (r.distance ?? 0.0));
    final double rangeFuelAmount =
        records.fold(0.0, (sum, r) => sum + r.fuelAmount);
    final double rangeOtherCost =
        expenses.fold(0.0, (sum, e) => sum + e.amount);

    final validRecords = records.where((r) =>
        r.fuelConsumption != null &&
        r.fuelConsumption! > 0 &&
        r.distance != null &&
        r.distance! > 0);
    final validDistance = validRecords.fold(0.0, (sum, r) => sum + r.distance!);
    final validFuel = validRecords.fold(
        0.0, (sum, r) => sum + (r.fuelConsumption! * r.distance!) / 100.0);
    final validCost = validRecords.fold(
        0.0, (sum, r) => sum + (r.costPerKm ?? 0.0) * r.distance!);
    final double rangeAvgConsumption = validDistance > 0
        ? (validFuel / validDistance) * 100.0
        : (records.isNotEmpty && refuelProv.summary.averageConsumption > 0
            ? refuelProv.summary.averageConsumption
            : 0.0);
    final double rangeCostPerKm =
        validDistance > 0 ? validCost / validDistance : 0.0;

    final dynamicRangeSummary = FuelCalculationSummary(
      averageConsumption: rangeAvgConsumption,
      averageCostPerKm: rangeCostPerKm,
      totalFuelCost: rangeFuelCost,
      totalValidDistance: rangeDistance,
      totalFuelAmount: rangeFuelAmount,
    );

    final isCustomRange = _selectedRange == '自定义' && _customDateRange != null;
    final customLabel = isCustomRange
        ? '${DateFormatter.formatMonthDay(_customDateRange!.start)}~${DateFormatter.formatMonthDay(_customDateRange!.end)}'
        : '自定义';

    return Scaffold(
      appBar: AppBar(
        title: const AppPageTitle(
          title: '统计图表',
          subtitle: '油耗、天气与成本分析',
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
                    builder: (_) => const ServiceSettingsScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelPadding: EdgeInsets.zero,
          indicatorColor: const Color(0xFFFF5A24),
          labelColor: const Color(0xFFFF5A24),
          unselectedLabelColor: colors.onSurfaceVariant,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: '综合总览'),
            Tab(text: '油耗进阶'),
            Tab(text: '环境行情'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 全局固顶统计范围选择器（支持全部、近半年、今年与自定义范围）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context).cardColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(AppIcons.filter_alt_outlined,
                        size: 16, color: Color(0xFFFF5A24)),
                    const SizedBox(width: 4),
                    Text('统计周期:',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colors.onSurfaceVariant)),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...['全部', '近半年', '今年'].map((range) {
                        final isSelected = _selectedRange == range;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedRange = range);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFF5A24)
                                    : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFFF5A24)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                range,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.white
                                      : colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      // 自定义日期范围按钮（非全屏迷你弹窗）
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: InkWell(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            final picked = await CompactDateRangeDialog.show(
                              context,
                              initialRange: _customDateRange,
                            );
                            if (picked != null) {
                              setState(() {
                                _customDateRange = picked;
                                _selectedRange = '自定义';
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _selectedRange == '自定义'
                                  ? const Color(0xFF1E88E5)
                                  : Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedRange == '自定义'
                                    ? const Color(0xFF1E88E5)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  AppIcons.edit_calendar_outlined,
                                  size: 13,
                                  color: _selectedRange == '自定义'
                                      ? Colors.white
                                      : colors.onSurface,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  customLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _selectedRange == '自定义'
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _selectedRange == '自定义'
                                        ? Colors.white
                                        : colors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),

          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // 1. 综合总览看板
                    _buildOverviewTab(context, records, expenses,
                        dynamicRangeSummary, rangeOtherCost),

                    // 2. 油耗进阶分析看板
                    _buildAdvancedFuelTab(
                        context, records, rangeAvgConsumption),

                    // 3. 环境气温看板
                    _buildClimateAndMarketTab(context, records),
                  ],
                ),

                // 右下角回到顶部悬浮按钮（贴合底栏收缩状态，留白适中）
                Positioned(
                  right: 16,
                  bottom: 28,
                  child: AnimatedScale(
                    scale: _showBackToTop ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: AnimatedOpacity(
                      opacity: _showBackToTop ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Material(
                        elevation: 4,
                        shape: const CircleBorder(),
                        color: Theme.of(context).cardColor,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _scrollToTop,
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            child: const Icon(AppIcons.arrow_upward,
                                size: 20, color: Color(0xFFFF5A24)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. 综合总览看板 (Overview Tab - 优化边距与报表排版)
  // ===========================================================================
  Widget _buildOverviewTab(
    BuildContext context,
    List<RefuelRecordModel> records,
    List<ExpenseRecordModel> expenses,
    FuelCalculationSummary summary,
    double totalOtherExpense,
  ) {
    final expenseShares = StatisticsService.getExpenseStructure(
      refuelRecords: records,
      expenseRecords: expenses,
    );

    final periodStats = StatisticsService.getPeriodStats(
      records: records,
      expenses: expenses,
      periodType: _selectedPeriodGranularity,
    );

    return ListView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      children: [
        _buildSummaryGrid(summary, totalOtherExpense),
        const SizedBox(height: 8),
        _buildPeriodStatsCard(context, periodStats),
        const SizedBox(height: 8),
        _buildExpenseStructureCard(context, expenseShares),
      ],
    );
  }

  // ===========================================================================
  // 2. 油耗进阶分析看板 (Advanced Fuel Tab - 宽度最大化)
  // ===========================================================================
  Widget _buildAdvancedFuelTab(BuildContext context,
      List<RefuelRecordModel> records, double avgConsumption) {
    final singleConsumptionTrends =
        StatisticsService.getConsumptionTrend(records);
    final movingAvgEvolution =
        StatisticsService.getMovingAverageEvolutionTrend(records);
    final costPerKmTrends = StatisticsService.getCostPerKmTrend(records);
    final tenThousandStats = StatisticsService.getTenThousandKmStats(records);
    final priceTrends = StatisticsService.getPriceTrend(records);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
      children: [
        // 1. 单次百公里油耗波动走势图
        _buildLineChartCard(
          context: context,
          title: '单次百公里油耗走势',
          subtitle: '记录每次实测波动，虚线为均值基准线',
          dataPoints: singleConsumptionTrends,
          baselineValue: avgConsumption,
          unit: 'L/100km',
          lineColor: const Color(0xFFFF5A24),
        ),

        const SizedBox(height: 10),

        // 2. 累计平均油耗演进过程图 (Evolution Curve 平滑收敛曲线)
        _buildLineChartCard(
          context: context,
          title: '累计平均油耗演进过程',
          subtitle: '平滑收敛曲线，展示全车平稳油耗水准',
          dataPoints: movingAvgEvolution,
          baselineValue: avgConsumption,
          unit: 'L/100km',
          lineColor: const Color(0xFF1E88E5),
        ),

        const SizedBox(height: 10),

        // 3. 每公里燃油花费历史走势图 (¥/km)
        _buildLineChartCard(
          context: context,
          title: '每公里燃油花费走势',
          subtitle: '直观反映单公里实际用油成本变动',
          dataPoints: costPerKmTrends,
          unit: '¥/km',
          lineColor: Colors.purple,
        ),

        const SizedBox(height: 10),

        // 4. 每万公里阶段平均油耗阶梯统计 (优化升级版)
        _buildTenThousandKmCard(context, tenThousandStats),

        const SizedBox(height: 10),

        // 5. 个人实际加油单价历史走势图
        _buildLineChartCard(
          context: context,
          title: '实际加油单价历史走势',
          subtitle: '记录历次加油每升实付单价变动',
          dataPoints: priceTrends,
          unit: '¥/L',
          lineColor: Colors.teal,
        ),
      ],
    );
  }

  // ===========================================================================
  // 3. 环境气温与国际原油行情看板 (Climate & Market Tab - 宽度最大化)
  // ===========================================================================
  Widget _buildCurrentWeatherCard(WeatherProvider weatherProv, String city) {
    final colors = Theme.of(context).colorScheme;
    final weather = weatherProv.current;
    if (weather == null) {
      return CustomCard(
        margin: EdgeInsets.zero,
        child: Row(
          children: [
            Icon(AppIcons.cloud_off_outlined, color: colors.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '实时天气暂不可用\n${weatherProv.statusText}',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    final details = <String>[];
    if (weather.tempHigh != null) {
      details.add('高 ${weather.tempHigh!.toStringAsFixed(1)}°C');
    }
    if (weather.tempLow != null) {
      details.add('低 ${weather.tempLow!.toStringAsFixed(1)}°C');
    }
    if (weather.aqi != null) {
      details.add('AQI ${weather.aqi}');
    }
    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(AppIcons.cloud_outlined, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '实时天气 · ${weather.cityName.isEmpty ? city : weather.cityName}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  '${weather.temperature?.toStringAsFixed(1) ?? '--'}°C${weather.condition == null ? '' : ' · ${weather.condition}'}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (details.isNotEmpty)
                  Text(details.join(' · '),
                      style: TextStyle(
                          fontSize: 11, color: colors.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('墨迹天气 · ${weatherProv.historyWindow.coverageLabel}',
                    style: TextStyle(
                        fontSize: 10, color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClimateAndMarketTab(
      BuildContext context, List<RefuelRecordModel> records) {
    final colors = Theme.of(context).colorScheme;
    final fuelProv = context.watch<FuelPriceProvider>();
    final weatherProv = context.watch<WeatherProvider>();
    if (_tabController.index == 2 && !_weatherRefreshQueued) {
      _weatherRefreshQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _weatherRefreshQueued = false;
        if (!mounted || _tabController.index != 2) return;
        context.read<WeatherProvider>().refreshForActualLocation(
              fallbackCity: fuelProv.currentCity,
              referenceDates: records.map((record) => record.refuelDate),
            );
      });
    }
    final displayTempVsCons =
        StatisticsService.getTemperatureVsConsumptionFromSnapshots(
      records,
      weatherProv.snapshots,
    );
    String? weatherCity;
    final currentWeatherCity = weatherProv.current?.cityName;
    if (currentWeatherCity != null && currentWeatherCity.isNotEmpty) {
      weatherCity = currentWeatherCity;
    } else {
      for (final snapshot in weatherProv.snapshots) {
        if (snapshot.cityName.isNotEmpty) {
          weatherCity = snapshot.cityName;
          break;
        }
      }
    }
    final chartValues = displayTempVsCons
        .expand((point) => [point.avgConsumption, point.estimatedTemperature])
        .toList();
    final boundedChartValues = chartValues.isEmpty ? [0.0] : chartValues;
    final rawChartMin = boundedChartValues.reduce((a, b) => a < b ? a : b);
    final rawChartMax = boundedChartValues.reduce((a, b) => a > b ? a : b);
    final chartPadding = math.max(2.0, (rawChartMax - rawChartMin) * 0.1);
    final chartMinY =
        math.min(0.0, (rawChartMin - chartPadding).floorToDouble());
    final chartMaxY =
        math.max(0.0, (rawChartMax + chartPadding).ceilToDouble());
    final chartYInterval =
        math.max(1.0, (chartMaxY - chartMinY) / 5).ceilToDouble();

    final anomalies = StatisticsService.getAnomalyDiagnostics(records);
    final validConsumptionCount = records
        .where((r) =>
            r.fuelConsumption != null &&
            r.fuelConsumption! > 0 &&
            r.distance != null &&
            r.distance! > 0)
        .length;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
      children: [
        _buildCurrentWeatherCard(weatherProv, fuelProv.currentCity),

        const SizedBox(height: 10),

        // 1. 异常点智能诊断与能耗波动分析卡片
        _buildAnomalyDiagnosticsCard(context, anomalies, validConsumptionCount),

        const SizedBox(height: 10),

        // 2. 月度能耗与当地气温对比图 (地区气候强关联)
        if (displayTempVsCons.isEmpty)
          _buildUnavailableStatsCard('暂无已保存天气快照，无法生成真实温度与油耗关联图')
        else
          CustomCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(AppIcons.thermostat_outlined,
                            color: Colors.orange, size: 18),
                        SizedBox(width: 6),
                        Text('月度能耗与地区气温关联图',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '数据地区: ${weatherCity ?? '暂无定位地区'}',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF1E88E5),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('关联已保存的 ${weatherCity ?? '实际定位地区'} 每日天气快照，揭示温度变化与油耗的关系',
                    style: TextStyle(
                        fontSize: 11, color: colors.onSurfaceVariant)),
                const SizedBox(height: 10),

                // 图例说明
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLegendItem('实测百公里油耗 (L)', const Color(0xFFFF5A24)),
                    const SizedBox(width: 16),
                    _buildLegendItem('快照平均气温 (°C)', const Color(0xFF1E88E5)),
                  ],
                ),

                const SizedBox(height: 14),

                SizedBox(
                  height: 190,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      minY: chartMinY,
                      maxY: chartMaxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: colors.outline.withValues(alpha: 0.28),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                        ),
                      ),
                      barTouchData: BarTouchData(
                        enabled: true,
                        handleBuiltInTouches: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final p = displayTempVsCons[group.x.toInt()];
                            return BarTooltipItem(
                              '${p.monthLabel}\n'
                              '油耗: ${p.avgConsumption > 0 ? "${p.avgConsumption}L" : "无数据"}\n'
                              '当地气温: ${p.estimatedTemperature}°C',
                              const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (val, meta) {
                              final idx = val.toInt();
                              if (idx >= 0 && idx < displayTempVsCons.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(displayTempVsCons[idx].monthLabel,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: colors.onSurfaceVariant)),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            interval: chartYInterval,
                            getTitlesWidget: (val, meta) {
                              return Text('${val.toInt()}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: colors.onSurfaceVariant));
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: displayTempVsCons.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: p.avgConsumption > 0 ? p.avgConsumption : 0,
                              color: const Color(0xFFFF5A24),
                              width: 8,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            BarChartRodData(
                              toY: p.estimatedTemperature,
                              color: const Color(0xFF1E88E5),
                              width: 8,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // 公用组件：指标卡、周期卡片（防溢出）、折线图、环形图等
  // ===========================================================================

  Widget _buildUnavailableStatsCard(String message) {
    final colors = Theme.of(context).colorScheme;
    return CustomCard(
      child: Row(
        children: [
          Icon(AppIcons.info_outline, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text(message, style: TextStyle(color: colors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryGrid(
      FuelCalculationSummary summary, double totalOtherExpense) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricItem(
                '平均百公里油耗',
                '${summary.averageConsumption.toStringAsFixed(2)} L',
                '综合百公里实测',
                const Color(0xFFFF5A24),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricItem(
                '每公里总花费',
                '¥ ${summary.averageCostPerKm.toStringAsFixed(2)}',
                '燃油每公里成本',
                const Color(0xFF1E88E5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMetricItem(
                '累计加油总花费',
                '¥ ${summary.totalFuelCost.toStringAsFixed(2)}',
                '油费总支出',
                Colors.purple,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricItem(
                '累计总行驶里程',
                '${summary.totalValidDistance.toStringAsFixed(2)} km',
                '全车行驶总计',
                Colors.teal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricItem(
      String title, String value, String subtitle, Color color) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface)),
          Text(subtitle,
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  // 周期报表卡片（彻底防溢出设计：双列自适应弹性伸缩与单行截断保护）
  Widget _buildPeriodStatsCard(
      BuildContext context, List<PeriodStatsItem> periodStats) {
    final colors = Theme.of(context).colorScheme;
    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.calendar_view_month,
                  color: Color(0xFFFF5A24), size: 18),
              const SizedBox(width: 6),
              const Text('周期报表',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: ['月度', '季度', '年度'].map((g) {
                  final isSel = _selectedPeriodGranularity == g;
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedPeriodGranularity = g);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFFFF5A24)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          g,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSel ? FontWeight.bold : FontWeight.normal,
                            color: isSel ? Colors.white : colors.onSurface,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (periodStats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: Text('暂无周期统计数据',
                      style: TextStyle(color: colors.onSurfaceVariant))),
            )
          else
            Column(
              children: periodStats.reversed.take(6).map((p) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 第一行：周期标签与总花费
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            p.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            '¥${p.totalExpense.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFFFF5A24),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 第二行：行驶里程与完整耗油量、平均油耗与每公里成本
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '行驶 ${p.mileage.toStringAsFixed(2)} km  ·  耗油 ${p.fuelAmount.toStringAsFixed(2)} L',
                              style: TextStyle(
                                  fontSize: 11, color: colors.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            p.avgConsumption > 0
                                ? '均 ${p.avgConsumption.toStringAsFixed(2)}L | ¥${p.costPerKm.toStringAsFixed(2)}/km'
                                : '¥${p.costPerKm.toStringAsFixed(2)}/km',
                            style: TextStyle(
                                fontSize: 11, color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // 优化升级：每万公里阶段油耗统计卡片
  Widget _buildTenThousandKmCard(
      BuildContext context, List<TenThousandKmStats> stages) {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(AppIcons.stairs_outlined,
                  color: Color(0xFFFF5A24), size: 18),
              SizedBox(width: 6),
              Text('每万公里阶段油耗统计',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text('全生命周期各万公里里程段机械状态与磨合情况',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          const SizedBox(height: 10),
          if (stages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: Text('里程跨度不足 1 万公里，暂无阶段数据',
                      style: TextStyle(color: colors.onSurfaceVariant))),
            )
          else
            Column(
              children: stages.map((s) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: colors.outline.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF5A24)
                                      .withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(AppIcons.speed,
                                    color: Color(0xFFFF5A24), size: 14),
                              ),
                              const SizedBox(width: 6),
                              Text(s.stageLabel,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E88E5)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(s.phaseTitle,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF1E88E5),
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          Text(
                            s.avgConsumption > 0
                                ? '${s.avgConsumption.toStringAsFixed(2)} L'
                                : '--',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF5A24)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '行驶 +${s.totalDistance.toStringAsFixed(2)}km · 消耗 ${s.totalFuel.toStringAsFixed(2)}L · 记账 ${s.recordCount}笔',
                            style: TextStyle(
                                fontSize: 11, color: colors.onSurfaceVariant),
                          ),
                          if (s.diffFromPrevious != null)
                            Row(
                              children: [
                                Icon(
                                  s.diffFromPrevious! <= 0
                                      ? AppIcons.arrow_downward
                                      : AppIcons.arrow_upward,
                                  size: 12,
                                  color: s.diffFromPrevious! <= 0
                                      ? (isDark
                                          ? Colors.green[300]!
                                          : Colors.green[700]!)
                                      : (isDark
                                          ? Colors.orange[300]!
                                          : Colors.orange[800]!),
                                ),
                                Text(
                                  '${s.diffFromPrevious! > 0 ? "+" : ""}${s.diffFromPrevious!.toStringAsFixed(2)}L',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: s.diffFromPrevious! <= 0
                                        ? (isDark
                                            ? Colors.green[300]!
                                            : Colors.green[700]!)
                                        : (isDark
                                            ? Colors.orange[300]!
                                            : Colors.orange[800]!),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildLineChartCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<ChartDataPoint> dataPoints,
    required String unit,
    required Color lineColor,
    double? baselineValue,
  }) {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final minColor = isDark ? Colors.green[300]! : Colors.green[700]!;
    final maxColor = isDark ? Colors.orange[300]! : Colors.orange[800]!;
    if (dataPoints.isEmpty) {
      return CustomCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('需要至少 2 笔记录才能生成此趋势图',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      );
    }

    final values = dataPoints.map((p) => p.value).toList();
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final minY = (rawMin * 0.9).floorToDouble();
    final maxY = (rawMax * 1.1).ceilToDouble();
    final safeMaxY = (maxY <= minY) ? minY + 4.0 : maxY;
    final span = safeMaxY - minY;
    final double yInterval =
        span > 20 ? (span / 4).roundToDouble() : (span > 6 ? 2.0 : 1.0);

    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              if (baselineValue != null && baselineValue > 0)
                Text('均值: ${baselineValue.toStringAsFixed(2)} $unit',
                    style: TextStyle(
                        fontSize: 11,
                        color: lineColor,
                        fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 3),
          Text(subtitle,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          if (dataPoints.length >= 3) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: minColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('最低: ${rawMin.toStringAsFixed(2)} $unit',
                      style: TextStyle(
                          fontSize: 10,
                          color: minColor,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: maxColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('最高: ${rawMax.toStringAsFixed(2)} $unit',
                      style: TextStyle(
                          fontSize: 10,
                          color: maxColor,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: safeMaxY,
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xDE1A1A1A),
                    tooltipRoundedRadius: 8,
                    tooltipPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.x.toInt();
                        final point = (idx >= 0 && idx < dataPoints.length)
                            ? dataPoints[idx]
                            : null;
                        final dateStr = point != null
                            ? DateFormatter.formatChineseYmd(point.date)
                            : '';
                        final extraStr =
                            point?.extra != null ? '\n${point!.extra}' : '';
                        final diffStr = (baselineValue != null &&
                                baselineValue > 0)
                            ? '\n较均值: ${(spot.y - baselineValue).toStringAsFixed(2)} $unit'
                            : '';
                        return LineTooltipItem(
                          '$dateStr\n${spot.y.toStringAsFixed(2)} $unit$diffStr$extraStr',
                          const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              height: 1.3),
                        );
                      }).toList();
                    },
                  ),
                  getTouchedSpotIndicator: (barData, spotIndexes) {
                    return spotIndexes.map((index) {
                      return TouchedSpotIndicatorData(
                        FlLine(
                          color: lineColor.withValues(alpha: 0.6),
                          strokeWidth: 1.5,
                          dashArray: [4, 4],
                        ),
                        FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) {
                            return FlDotCirclePainter(
                              radius: 5,
                              color: lineColor,
                              strokeWidth: 2.5,
                              strokeColor: Colors.white,
                            );
                          },
                        ),
                      );
                    }).toList();
                  },
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colors.outline.withValues(alpha: 0.28),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        final count = dataPoints.length;
                        final step = count <= 5
                            ? 1
                            : (count <= 10 ? 2 : (count / 4).floor());
                        if (idx >= 0 &&
                            idx < count &&
                            (idx == 0 || idx == count - 1 || idx % step == 0)) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(dataPoints[idx].label,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: colors.onSurfaceVariant)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: yInterval,
                      reservedSize: 28,
                      getTitlesWidget: (val, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            val.toStringAsFixed(1),
                            style: TextStyle(
                                fontSize: 10, color: colors.onSurfaceVariant),
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: dataPoints
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
                        .toList(),
                    isCurved: true,
                    color: lineColor,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: lineColor.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseStructureCard(
      BuildContext context, List<ExpenseCategoryShare> shares) {
    if (shares.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = [
      const Color(0xFFFF5A24),
      const Color(0xFF1E88E5),
      Colors.green,
      Colors.purple,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
    ];

    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(AppIcons.pie_chart_outline,
                  color: Color(0xFFFF5A24), size: 18),
              SizedBox(width: 6),
              Text('全车用车成本结构分布',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 36,
                sections: shares.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  final color = colors[i % colors.length];

                  return PieChartSectionData(
                    color: color,
                    value: s.percentage,
                    title: '${s.percentage.toStringAsFixed(0)}%',
                    radius: 42,
                    titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: shares.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              final color = colors[i % colors.length];

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(
                      '${s.category}: ¥${s.totalAmount.toStringAsFixed(0)} (${s.percentage}%)',
                      style: const TextStyle(fontSize: 11)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    final textColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: textColor)),
      ],
    );
  }

  Widget _buildAnomalyDiagnosticsCard(BuildContext context,
      List<AnomalyDiagnosticItem> anomalies, int validConsumptionCount) {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final displayList =
        _isAnomalyExpanded ? anomalies : anomalies.take(3).toList();

    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(AppIcons.auto_awesome_outlined,
                      color: Color(0xFFFF5A24), size: 18),
                  SizedBox(width: 6),
                  Text('能耗波动与异常点智能诊断',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              if (anomalies.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '发现 ${anomalies.length} 项特征记录',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('基于 $validConsumptionCount 条有效实测油耗记录计算个人基线，仅在样本达到 5 条后进行诊断',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          const SizedBox(height: 10),
          if (validConsumptionCount < 5)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Text(
                '当前只有 $validConsumptionCount 条有效油耗记录，数据不足，暂不判断能耗波动',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            )
          else if (anomalies.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.check_circle_outline,
                      color: isDark ? Colors.green[300] : Colors.green[700],
                      size: 18),
                  const SizedBox(width: 6),
                  Text('全车能耗整体处于平稳受控范围，未检测到异常波动',
                      style: TextStyle(
                          color: colors.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            )
          else
            Column(
              children: [
                ...displayList.map((a) {
                  final isHigh = a.isHigh;
                  final themeColor = isHigh
                      ? (isDark ? Colors.red[300]! : Colors.red[700]!)
                      : (isDark ? Colors.green[300]! : Colors.green[700]!);
                  final itemBackground = isHigh
                      ? (isDark
                          ? const Color(0xFF3A2425)
                          : const Color(0xFFFFF8F8))
                      : (isDark
                          ? const Color(0xFF203429)
                          : const Color(0xFFF6FBF7));
                  final statusTextColor = isHigh
                      ? (isDark ? Colors.red[100]! : Colors.red[800]!)
                      : (isDark ? Colors.green[100]! : Colors.green[800]!);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: itemBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: themeColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. 紧凑防溢出顶部栏
                        Row(
                          children: [
                            Icon(
                              isHigh
                                  ? AppIcons.warning_amber_rounded
                                  : AppIcons.trending_down,
                              size: 14,
                              color: statusTextColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              DateFormatter.formatYmd(a.date),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: themeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isHigh
                                    ? '偏高 +${a.deviation}L'
                                    : '节油 ${a.deviation}L',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: statusTextColor,
                                ),
                              ),
                            ),
                            const Spacer(),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: a.consumption.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: statusTextColor,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' L/100km',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 7),

                        // 2. 成因分析
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text('成因',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: colors.onSurface,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                a.reason,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.onSurface,
                                    height: 1.35),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // 3. 对策建议（高对比度可读性字体）
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: themeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '建议',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: statusTextColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                a.suggestion,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                    height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

                // 展开/收起 切换按钮
                if (anomalies.length > 3)
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isAnomalyExpanded = !_isAnomalyExpanded);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isAnomalyExpanded
                                ? '收起诊断列表'
                                : '展开查看全部 (${anomalies.length}项特征)',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFFF5A24),
                                fontWeight: FontWeight.bold),
                          ),
                          Icon(
                            _isAnomalyExpanded
                                ? AppIcons.keyboard_arrow_up
                                : AppIcons.keyboard_arrow_down,
                            size: 16,
                            color: const Color(0xFFFF5A24),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
