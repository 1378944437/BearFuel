import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../domain/fuel_price_service.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/chart_axis_utils.dart';
import '../../../providers/fuel_price_provider.dart';
import '../../../providers/vehicle_provider.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/apizero_oil_forecast_service.dart';
import '../../../data/services/ai_audit_config_store.dart';
import '../../../data/services/ai_audit_service.dart';
import '../../widgets/custom_card.dart';
import '../../widgets/city_picker_sheet.dart';
import '../../widgets/app_page_title.dart';

/// 全国实时油价与历史调价走势查询大屏（支持城市定位持久化同步、加满一箱油计算器与31省市秒级检索）
class NationalFuelPriceScreen extends StatefulWidget {
  const NationalFuelPriceScreen({super.key});

  @override
  State<NationalFuelPriceScreen> createState() =>
      _NationalFuelPriceScreenState();
}

class _NationalFuelPriceScreenState extends State<NationalFuelPriceScreen> {
  bool _isAiReviewingPrice = false;
  AiReviewResult? _priceAiResult;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final vehicleProv = context.watch<VehicleProvider>();
    final currentVehicle = vehicleProv.currentVehicle;

    final fuelProv = context.watch<FuelPriceProvider>();
    final currentCity = fuelProv.currentCity;
    final currentProvince = fuelProv.currentProvince;
    final priceData = fuelProv.currentPrice;
    final forecast = fuelProv.forecast;
    final history = fuelProv.adjustmentSchedule;

    return Scaffold(
      appBar: AppBar(
        title: AppPageTitle(
          title: '实时油价',
          subtitle: '$currentCity · $currentProvince',
        ),
        actions: [
          // 手动更新当前城市油价
          IconButton(
            icon: fuelProv.isRefreshingPrice
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF1E88E5),
                    ),
                  )
                : Icon(AppIcons.refresh, color: colors.secondary, size: 20),
            tooltip: '手动更新当前城市油价',
            onPressed: fuelProv.isRefreshingPrice
                ? null
                : () async {
                    HapticFeedback.lightImpact();
                    await fuelProv.refreshCurrentPrice();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(fuelProv.priceStatusText),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
          ),
          // 重新定位按钮
          IconButton(
            icon: fuelProv.isLocating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF5A24),
                    ),
                  )
                : Icon(AppIcons.my_location, color: colors.primary, size: 20),
            tooltip: '重新 GPS 卫星定位',
            onPressed: fuelProv.isLocating
                ? null
                : () async {
                    HapticFeedback.lightImpact();
                    final success = await fuelProv.autoLocate();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(fuelProv.statusText),
                          backgroundColor: success
                              ? Colors.green
                              : Colors.orange,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
          ),
          // 城市切换选择器
          IconButton(
            icon: const Icon(AppIcons.location_city),
            tooltip: '切换城市',
            onPressed: () async {
              HapticFeedback.selectionClick();
              final selected = await CityPickerSheet.show(
                context,
                currentCity: currentCity,
                domesticOnly: true,
              );
              if (selected != null && selected.isNotEmpty && context.mounted) {
                final success = await fuelProv.updateCity(selected);
                if (!success && context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(fuelProv.statusText)));
                }
              }
            },
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          // 1. 省份油价头部状态
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$currentCity ($currentProvince) 今日指导油价',
                    maxLines: 2,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  priceData.isAvailable
                      ? '更新于 ${DateFormatter.formatChineseYmd(priceData.lastChangeDate)}'
                      : '暂无在线数据',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          _buildPriceSourceNotice(fuelProv),

          _buildAiPriceReviewCard(
            fuelProv: fuelProv,
            priceData: priceData,
            schedule: history,
          ),

          const SizedBox(height: 6),

          // 2. 四大标号油价大字展示卡片
          _buildFuelPriceGrid(
            priceData,
            // action=price only returns the current price, not per-grade changes.
            showChange: false,
          ),

          const SizedBox(height: 12),

          // 3. 爱车加满一箱油费用与省钱建议计算器
          _buildTankFillCalculator(
            context,
            currentVehicle,
            priceData,
            forecast,
          ),

          const SizedBox(height: 12),

          // 4. 下一轮发改委调价窗口期预测
          _buildAdjustmentForecastCard(forecast),

          const SizedBox(height: 12),

          // 5. 国家调价幅度历史图
          _buildHistoricalPriceChart(history),

          const SizedBox(height: 12),

          // 6. 历史调价清单流水
          _buildHistoricalLogList(history),
        ],
      ),
    );
  }

  /// AI 油价审查与缺失调价分析入口。
  /// AI 只分析接口已返回的数据和缺失字段，不会把推测值写回油价或账本。
  Widget _buildAiPriceReviewCard({
    required FuelPriceProvider fuelProv,
    required ProvinceFuelPrice priceData,
    required List<ApiZeroAdjustmentScheduleItem> schedule,
  }) {
    final colors = Theme.of(context).colorScheme;
    final configured = AiAuditConfigStore.isConfigured;
    final missingCount = schedule
        .where(
          (item) =>
              item.status == '已过' &&
              item.gasolineYuanPerTon == null &&
              item.summary == null,
        )
        .length;

    return CustomCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                AppIcons.auto_awesome_outlined,
                size: 18,
                color: Color(0xFF6558D3),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'AI 油价数据审查',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              if (missingCount > 0)
                Text(
                  '$missingCount 项待核对',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            configured
                ? '检查当前油价与调价日历的一致性，或分析已过窗口仍缺少金额的原因。AI 不会补造官方价格。'
                : '配置 AI 服务后，可审查接口结果并分析缺失调价字段；当前油价数据不受影响。',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: configured && !_isAiReviewingPrice
                      ? () => _runPriceAiReview(
                          fuelProv: fuelProv,
                          priceData: priceData,
                          schedule: schedule,
                          completion: false,
                        )
                      : null,
                  icon: const Icon(AppIcons.assessment_outlined, size: 15),
                  label: const Text('审查当前油价'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      configured && missingCount > 0 && !_isAiReviewingPrice
                      ? () => _runPriceAiReview(
                          fuelProv: fuelProv,
                          priceData: priceData,
                          schedule: schedule,
                          completion: true,
                        )
                      : null,
                  icon: const Icon(AppIcons.auto_awesome_outlined, size: 15),
                  label: const Text('分析缺失调价'),
                ),
              ),
            ],
          ),
          if (_isAiReviewingPrice) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_priceAiResult != null) ...[
            const SizedBox(height: 8),
            _buildInlinePriceAiResult(_priceAiResult!),
          ],
        ],
      ),
    );
  }

  Future<void> _runPriceAiReview({
    required FuelPriceProvider fuelProv,
    required ProvinceFuelPrice priceData,
    required List<ApiZeroAdjustmentScheduleItem> schedule,
    required bool completion,
  }) async {
    final models = AiAuditConfigStore.models;
    if (models.isEmpty) {
      _showPriceAiMessage('请先在 AI 账本审查设置中添加模型', Colors.orange);
      return;
    }
    final model = models.length == 1
        ? models.first
        : await _choosePriceAiModel(models, AiAuditConfigStore.model);
    if (model == null || model.isEmpty || !mounted) return;

    setState(() {
      _isAiReviewingPrice = true;
      _priceAiResult = null;
    });

    final currentPrice = fuelProv.currentPrice;
    final contextData = <String, dynamic>{
      'task': completion
          ? 'review_missing_adjustment_result'
          : 'review_current_fuel_price',
      'province': fuelProv.currentProvince,
      'price': {
        'gas92': currentPrice.gas92,
        'gas95': currentPrice.gas95,
        'gas98': currentPrice.gas98,
        'diesel0': currentPrice.diesel0,
        'last_change_date': currentPrice.lastChangeDate
            .toIso8601String()
            .substring(0, 10),
      },
      'schedule': schedule
          .take(8)
          .map(
            (item) => <String, dynamic>{
              'date': item.date.toIso8601String().substring(0, 10),
              'status': item.status,
              'effective': item.effective,
              'gasoline_yuan_per_ton': item.gasolineYuanPerTon,
              'diesel_yuan_per_ton': item.dieselYuanPerTon,
              'summary': item.summary,
            },
          )
          .toList(),
      'constraints': [
        '接口数据是事实来源，缺失金额不得猜测或补造',
        'AI 只能指出冲突、证据不足与核查建议',
        '不要修改任何油价或账本数据',
      ],
    };

    final result = await AiAuditService.reviewFinding(
      context: contextData,
      model: model,
    );
    if (!mounted) return;
    setState(() {
      _isAiReviewingPrice = false;
      _priceAiResult = result;
    });
    if (result == null) {
      _showPriceAiMessage('AI 未返回有效结果；接口油价与调价日历保持不变', Colors.orange);
    }
  }

  Future<String?> _choosePriceAiModel(List<String> models, String active) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择本次使用的模型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final model in models)
              ListTile(
                dense: true,
                leading: Icon(
                  model == active
                      ? AppIcons.check_circle
                      : AppIcons.circle_outlined,
                  color: model == active
                      ? const Color(0xFFFF5A24)
                      : Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
                title: Text(model),
                onTap: () => Navigator.pop(ctx, model),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildInlinePriceAiResult(AiReviewResult result) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            result.explanation,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          if (result.suggestion != null && result.suggestion!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '建议：${result.suggestion}',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'AI 结果仅供辅助审查；缺失官方金额不会用推测值替代。',
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showPriceAiMessage(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Widget _buildPriceSourceNotice(FuelPriceProvider fuelProv) {
    final colors = Theme.of(context).colorScheme;
    final isOnlineApi = fuelProv.isPriceFromApi;
    final isLoading = fuelProv.priceStatusText.startsWith('正在');
    final accent = isOnlineApi ? colors.secondary : colors.primary;
    final fetchedAt = fuelProv.priceFetchedAt;
    final ageText = fetchedAt == null ? null : _humanizeAge(fetchedAt);
    final isCached =
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) > const Duration(minutes: 30);
    final source = isOnlineApi
        ? 'ApiZero 当前省级油价接口${isCached ? '（本地缓存，$ageText）' : ''}'
        : 'ApiZero 当前省级油价接口（暂未返回数据）';
    final readTime = isLoading
        ? '读取时间：读取中'
        : '读取时间：${fetchedAt == null ? '--' : DateFormatter.formatYmdHm(fetchedAt)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isLoading
                ? AppIcons.sync_outlined
                : (isOnlineApi
                      ? AppIcons.verified_outlined
                      : AppIcons.warning_amber_rounded),
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '来源：$source',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  readTime,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 爱车加满一箱油费用与省钱测算卡片
  Widget _buildTankFillCalculator(
    BuildContext context,
    VehicleModel? vehicle,
    ProvinceFuelPrice price,
    AdjustmentForecast forecast,
  ) {
    if (!price.isAvailable) {
      return _buildUnavailablePriceCard('暂无在线油价，无法测算加满一箱费用');
    }
    if (vehicle == null) {
      return _buildUnavailablePriceCard('请先在"爱车"中添加车辆档案，再使用加满一箱计算');
    }
    final colors = Theme.of(context).colorScheme;
    final capacity = vehicle.tankCapacity;
    final capacityLabel = capacity
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    final cost92 = capacity * price.gas92;
    final cost95 = capacity * price.gas95;
    final potentialDelta = (forecast.forecastDelta * capacity).abs();
    final isStagnant = forecast.direction.contains('搁浅');
    final isDark = colors.brightness == Brightness.dark;

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    AppIcons.calculate_outlined,
                    color: Color(0xFFFF5A24),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${vehicle.name} · 加满一箱油测算',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '油箱容积: ${capacityLabel}L',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5A24).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '92# 加满一箱',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFFF5A24),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '¥ ${cost92.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF5A24),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '95# 加满一箱',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1E88E5),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '¥ ${cost95.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E88E5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isStagnant
                  ? colors.surfaceContainerHighest.withValues(alpha: 0.45)
                  : (forecast.isIncrease
                        ? (isDark
                              ? const Color(0xFF3A2F1B)
                              : const Color(0xFFFFF3E0))
                        : (isDark
                              ? const Color(0xFF203429)
                              : const Color(0xFFE8F5E9))),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  isStagnant
                      ? AppIcons.horizontal_rule
                      : (forecast.isIncrease
                            ? AppIcons.trending_up
                            : AppIcons.trending_down),
                  size: 16,
                  color: isStagnant
                      ? colors.onSurfaceVariant
                      : (forecast.isIncrease
                            ? (isDark ? Colors.orange[200] : Colors.orange[800])
                            : (isDark ? Colors.green[200] : Colors.green[800])),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isStagnant
                        ? '下轮调价预计搁浅，当前无需根据预测提前加油。'
                        : (forecast.isIncrease
                              ? '下轮调价预计上涨，提前加满一箱可节省约 ¥${potentialDelta.toStringAsFixed(1)} 元！'
                              : '下轮调价预计下调，建议按需补油，下周加满可省约 ¥${potentialDelta.toStringAsFixed(1)} 元。'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isStagnant
                          ? colors.onSurface
                          : (forecast.isIncrease
                                ? (isDark
                                      ? Colors.orange[200]
                                      : Colors.orange[900])
                                : (isDark
                                      ? Colors.green[200]
                                      : Colors.green[900])),
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

  /// 4大标号油价卡片矩阵
  Widget _buildFuelPriceGrid(
    ProvinceFuelPrice price, {
    required bool showChange,
  }) {
    if (!price.isAvailable) {
      return _buildUnavailablePriceCard('暂无当前省份在线油价');
    }
    return CustomCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildPriceBox(
                  '92# 汽油',
                  price.gas92,
                  '¥/升',
                  const Color(0xFFFF5A24),
                  price.lastChangeAmount,
                  showChange: showChange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPriceBox(
                  '95# 汽油',
                  price.gas95,
                  '¥/升',
                  const Color(0xFF1E88E5),
                  price.lastChangeAmount,
                  showChange: showChange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPriceBox(
                  '98# 汽油',
                  price.gas98,
                  '¥/升',
                  const Color(0xFF8E24AA),
                  price.lastChangeAmount,
                  showChange: showChange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPriceBox(
                  '0# 柴油',
                  price.diesel0,
                  '¥/升',
                  const Color(0xFF00897B),
                  price.lastChangeAmount,
                  showChange: showChange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBox(
    String name,
    double price,
    String unit,
    Color color,
    double change, {
    required bool showChange,
  }) {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final isUp = change > 0;
    final isZero = change == 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: !showChange
                      ? color.withValues(alpha: 0.12)
                      : (isZero
                            ? Colors.grey.withValues(alpha: 0.2)
                            : (isUp
                                  ? (isDark
                                        ? const Color(0xFF4A2F32)
                                        : const Color(0xFFFFEBEE))
                                  : (isDark
                                        ? const Color(0xFF24452F)
                                        : const Color(0xFFE8F5E9)))),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  showChange
                      ? (isZero ? '持平' : (isUp ? '↑ +$change' : '↓ $change'))
                      : '省级基准',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: !showChange
                        ? color
                        : (isZero
                              ? colors.onSurfaceVariant
                              : (isUp
                                    ? (isDark
                                          ? Colors.red[200]
                                          : Colors.red[800])
                                    : (isDark
                                          ? Colors.green[200]
                                          : Colors.green[800]))),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 下一轮发改委调价窗口期预测
  Widget _buildAdjustmentForecastCard(AdjustmentForecast forecast) {
    if (!forecast.isAvailable) {
      return _buildUnavailablePriceCard('暂无在线调价预测数据');
    }
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    // 窗口日期次日已过 → 进入"等待官方公布实际结果"阶段，不再按预测渲染
    final windowPassed = context
        .read<FuelPriceProvider>()
        .isAdjustmentWindowPassed;
    final isStagnant = forecast.direction.contains('搁浅');
    final isIncrease = !isStagnant && forecast.isIncrease;
    final accent = isStagnant
        ? colors.onSurfaceVariant
        : (isDark
              ? (isIncrease ? Colors.red[200]! : Colors.green[200]!)
              : (isIncrease ? Colors.red[800]! : Colors.green[800]!));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.08), colors.surface),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isStagnant
                          ? AppIcons.horizontal_rule
                          : (isIncrease
                                ? AppIcons.trending_up
                                : AppIcons.trending_down),
                      color: accent,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        windowPassed ? '上一轮调价窗口已开启，等待官方公布' : '下轮发改委调价窗口期预测',
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: windowPassed
                      ? colors.outline
                      : isStagnant
                      ? colors.outline
                      : (isIncrease ? Colors.red[700] : Colors.green[700]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  windowPassed
                      ? '待公布'
                      : isStagnant
                      ? '搁浅'
                      : '剩 ${forecast.daysRemaining} 天',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '开启时间: ${DateFormatter.formatChineseYmd(forecast.nextAdjustmentDate)} 24:00',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            windowPassed
                ? '窗口已于 ${DateFormatter.formatChineseYmd(forecast.nextAdjustmentDate)} 开启，官方实际调价结果以公告为准'
                : isStagnant
                ? '本轮预计搁浅，汽油和柴油价格暂无变动'
                : '预计变动: ${isIncrease ? "预计上涨约" : "预计下调约"} ¥${forecast.forecastDelta.toStringAsFixed(2)} /升',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: colors.onSurface.withValues(alpha: 0.16)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                AppIcons.tips_and_updates_outlined,
                size: 16,
                color: Color(0xFFFF5A24),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  forecast.advice,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final fetchedAt = context
                  .read<FuelPriceProvider>()
                  .forecastFetchedAt;
              if (fetchedAt == null) return const SizedBox.shrink();
              return Text(
                '预测数据更新于 ${DateFormatter.formatYmdHm(fetchedAt)}（${_humanizeAge(fetchedAt)}）',
                style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 把时间戳转成 "x 分钟前 / x 小时前 / x 天前"
  String _humanizeAge(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  /// 国家调价幅度历史图，直接使用 ApiZero 调价日历返回的每吨幅度。
  Widget _buildHistoricalPriceChart(
    List<ApiZeroAdjustmentScheduleItem> history,
  ) {
    final colors = Theme.of(context).colorScheme;
    final points = history
        .where((item) => item.gasolineYuanPerTon != null)
        .toList();
    if (points.isEmpty) {
      return _buildUnavailablePriceCard('暂无在线调价幅度数据');
    }

    final values = points.map((item) => item.gasolineYuanPerTon!).toList();
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final buffer = ((rawMax - rawMin) * 0.18).clamp(20.0, 120.0);
    final minY = rawMin - buffer;
    final maxY = rawMax + buffer;
    final interval = ChartAxisUtils.niceInterval(maxY - minY, maxTicks: 4);

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '国家调价幅度历史（汽油 元/吨）',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '仅展示接口实际返回调价幅度，不推算调价后每升价格。',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (points.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colors.outline.withValues(alpha: 0.35),
                    strokeWidth: 1,
                    dashArray: [6, 6],
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      // 按实际刻度文本测量宽度，兼容 "+3000" 等宽标签
                      reservedSize: ChartAxisUtils.reservedSizeFor(
                        ChartAxisUtils.yTicks(minY, maxY, interval).map(
                          (v) =>
                              v == 0 ? '0' : '${v > 0 ? '+' : ''}${v.round()}',
                        ),
                        const TextStyle(fontSize: 9),
                      ),
                      interval: interval,
                      getTitlesWidget: (value, meta) => Text(
                        value == 0
                            ? '0'
                            : '${value > 0 ? '+' : ''}${value.round()}',
                        style: TextStyle(
                          fontSize: 9,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      // 固定步距 1，由标签内过滤决定显示，避免强制绘制
                      // max 刻度造成相邻日期重叠
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 || index >= points.length) {
                          return const SizedBox.shrink();
                        }
                        final step = (points.length / 5).ceil().clamp(
                          1,
                          points.length,
                        );
                        if (!ChartAxisUtils.shouldShowXLabel(
                          index,
                          points.length,
                          step,
                        )) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 5,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                          child: Text(
                            DateFormatter.formatMonthDay(points[index].date),
                            style: TextStyle(
                              fontSize: 9,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    // 气泡钳制在图表可视范围内，避免触点靠边时越界
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => const Color(0xDE1A1A1A),
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        final index = spot.x.toInt();
                        final date = index >= 0 && index < points.length
                            ? DateFormatter.formatMonthDay(points[index].date)
                            : '';
                        return LineTooltipItem(
                          '$date\n${spot.y.toStringAsFixed(0)} 元/吨',
                          const TextStyle(color: Colors.white, fontSize: 11),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: points
                        .asMap()
                        .entries
                        .map(
                          (entry) => FlSpot(
                            entry.key.toDouble(),
                            entry.value.gasolineYuanPerTon!,
                          ),
                        )
                        .toList(),
                    isCurved: false,
                    color: const Color(0xFFFF5A24),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 近期国家调价日历明细。
  Widget _buildHistoricalLogList(List<ApiZeroAdjustmentScheduleItem> history) {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final items = history.where((item) => !item.isPending).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '近期国家调价历史明细',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text('暂无在线调价日历数据', style: TextStyle(color: colors.onSurfaceVariant))
          else
            ...items.take(8).map((item) {
              final isUp = item.status.contains('上调');
              final isDown = item.status.contains('下调');
              final isStagnant = item.isStagnant;
              final color = isStagnant
                  ? colors.onSurfaceVariant
                  : (isUp
                        ? (isDark ? Colors.red[200]! : Colors.red[700]!)
                        : (isDown
                              ? (isDark
                                    ? Colors.green[200]!
                                    : Colors.green[700]!)
                              : colors.onSurface));
              final amount = item.gasolineYuanPerTon;
              final amountText = isStagnant
                  ? ' · 汽油、柴油均未调整'
                  : (amount == null
                        ? ''
                        : ' · 汽油 ${amount > 0 ? '+' : ''}${amount.toStringAsFixed(0)} 元/吨');
              final summary = item.summary;
              final displayStatus =
                  item.status == '已过' && amount == null && summary == null
                  ? '已过，官方未公布实际调价金额'
                  : item.status;
              final dateLabel =
                  '${item.date.year}年\n${item.date.month.toString().padLeft(2, '0')}月${item.date.day.toString().padLeft(2, '0')}日';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.28,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            fontWeight: FontWeight.bold,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$displayStatus$amountText',
                              style: TextStyle(
                                fontSize: 11,
                                color: color,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (summary != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                summary,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildUnavailablePriceCard(String message) {
    final colors = Theme.of(context).colorScheme;
    return CustomCard(
      child: Row(
        children: [
          Icon(AppIcons.info_outline, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
