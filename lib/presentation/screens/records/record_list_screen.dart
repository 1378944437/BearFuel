import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/refuel_record_model.dart';
import '../../../providers/refuel_provider.dart';
import '../../../providers/audit_provider.dart';
import '../../../data/models/audit_finding_model.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/vehicle_provider.dart';
import '../../../presentation/widgets/empty_state_view.dart';
import '../../../presentation/widgets/compact_date_range_dialog.dart';
import '../../../presentation/widgets/app_page_title.dart';
import '../refuel/add_refuel_screen.dart';
import '../expense/add_expense_screen.dart';
import '../settings/service_settings_screen.dart';

/// 历史明细账本流水页面（支持右下角悬浮搜索、迷你自定义时间、双项精简筛选栏与纯净左滑编辑删除）
class RecordListScreen extends StatefulWidget {
  /// 主导航底栏显隐通知：底栏可见时悬浮按钮需上移避让
  final ValueListenable<bool> navVisible;

  const RecordListScreen({super.key, required this.navVisible});

  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _RefuelSwipeController _refuelSwipeController =
      _RefuelSwipeController();
  String _searchQuery = '';
  bool _hasSeenSwipeHint = true; // 默认为 true，待异步加载
  bool _showBackToTop = false;
  int _currentTabIndex = 0; // 悬浮按钮仅服务加油列表

  // 1. 综合筛选条件
  String _selectedFuelType = '全部';
  String _selectedTankStatus = '全部'; // 全部, 仅加满, 未加满
  String _selectedEfficiency = '全部'; // 全部, 经济省油, 油耗偏高
  bool _onlyWithNotes = false; // 是否仅看有备注

  // 2. 时间控件筛选条件
  String _selectedTimeRange = '全部时间'; // 全部时间, 近1天, 近1周, 近1月, 近半年, 近1年, 今年, 自定义
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_currentTabIndex != _tabController.index) {
        setState(() => _currentTabIndex = _tabController.index);
      }
    });
    _scrollController.addListener(_onScroll);
    _checkSwipeHintPref();
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
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkSwipeHintPref() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('has_operated_record_swipe_hint') ?? false;
    if (mounted) {
      setState(() => _hasSeenSwipeHint = seen);
    }
  }

  Future<void> _dismissSwipeHintPermanently() async {
    if (_hasSeenSwipeHint) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_operated_record_swipe_hint', true);
    if (mounted) {
      setState(() => _hasSeenSwipeHint = true);
    }
  }

  /// 弹出搜索弹窗（由右下角悬停搜索图标触发）
  void _showSearchDialog(BuildContext context) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(AppIcons.search, color: Color(0xFFFF5A24), size: 22),
              SizedBox(width: 8),
              Text(
                '搜索账本流水',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '输入加油站、油品或备注关键词...',
              prefixIcon: const Icon(AppIcons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(AppIcons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
            onChanged: (val) {
              setState(() => _searchQuery = val);
            },
            onSubmitted: (_) => Navigator.pop(ctx),
          ),
          actions: [
            if (_searchQuery.isNotEmpty)
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                  Navigator.pop(ctx);
                },
                child: const Text('清空搜索', style: TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5A24),
                foregroundColor: Colors.white,
              ),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }

  /// 弹出 1: 综合筛选 BottomSheet（油品、是否加满、油耗表现、备注）
  void _showAdvancedFilterModal(BuildContext context) {
    HapticFeedback.selectionClick();
    String tempFuel = _selectedFuelType;
    String tempTank = _selectedTankStatus;
    String tempEff = _selectedEfficiency;
    bool tempNote = _onlyWithNotes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isDark = Theme.of(modalCtx).brightness == Brightness.dark;
            final colors = Theme.of(modalCtx).colorScheme;
            final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

            return Material(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                AppIcons.tune,
                                color: Color(0xFFFF5A24),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '综合筛选',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(AppIcons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 1. 燃油标号
                      const Text(
                        '燃油标号 / 油品',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: ['全部', '92#', '95#', '98#', '柴油'].map((f) {
                          final isSel = tempFuel == f;
                          return ChoiceChip(
                            showCheckmark: false,
                            label: Text(
                              f,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: isSel,
                            selectedColor: const Color(0xFFFF5A24),
                            labelStyle: TextStyle(
                              color: isSel
                                  ? colors.onPrimary
                                  : colors.onSurface,
                            ),
                            onSelected: (_) =>
                                setModalState(() => tempFuel = f),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // 2. 是否加满
                      const Text(
                        '油箱状态',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: ['全部', '仅加满', '未加满'].map((t) {
                          final isSel = tempTank == t;
                          return ChoiceChip(
                            showCheckmark: false,
                            label: Text(
                              t,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: isSel,
                            selectedColor: const Color(0xFFFF5A24),
                            labelStyle: TextStyle(
                              color: isSel
                                  ? colors.onPrimary
                                  : colors.onSurface,
                            ),
                            onSelected: (_) =>
                                setModalState(() => tempTank = t),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // 3. 油耗表现
                      const Text(
                        '油耗表现',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: ['全部', '经济省油', '油耗偏高'].map((e) {
                          final isSel = tempEff == e;
                          return ChoiceChip(
                            showCheckmark: false,
                            label: Text(
                              e,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: isSel,
                            selectedColor: const Color(0xFFFF5A24),
                            labelStyle: TextStyle(
                              color: isSel
                                  ? colors.onPrimary
                                  : colors.onSurface,
                            ),
                            onSelected: (_) => setModalState(() => tempEff = e),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // 4. 备注/优惠
                      const Text(
                        '备注与其他',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FilterChip(
                        showCheckmark: false,
                        label: const Text(
                          '仅看有备注/优惠信息',
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: tempNote,
                        selectedColor: const Color(0xFFFF5A24),
                        labelStyle: TextStyle(
                          color: tempNote ? colors.onPrimary : colors.onSurface,
                        ),
                        checkmarkColor: colors.onPrimary,
                        onSelected: (val) =>
                            setModalState(() => tempNote = val),
                      ),

                      const SizedBox(height: 20),

                      // 底部重置与确认按钮
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModalState(() {
                                  tempFuel = '全部';
                                  tempTank = '全部';
                                  tempEff = '全部';
                                  tempNote = false;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                              ),
                              child: const Text('重置'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _selectedFuelType = tempFuel;
                                  _selectedTankStatus = tempTank;
                                  _selectedEfficiency = tempEff;
                                  _onlyWithNotes = tempNote;
                                });
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF5A24),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 44),
                              ),
                              child: const Text('确定筛选'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 弹出 2: 时间控件 BottomSheet（快捷时间范围 + 迷你版自定义时间图标视图）
  void _showTimeRangeModal(BuildContext context) {
    HapticFeedback.selectionClick();
    const quickTimeList = [
      '全部时间',
      '近1天',
      '近1周',
      '近1月 (近30天)',
      '近半年',
      '近1年',
      '今年',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final colors = Theme.of(ctx).colorScheme;
        final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

        return Material(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            AppIcons.calendar_month,
                            color: Color(0xFF1E88E5),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '选择时间范围',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(AppIcons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 1. 快捷时间范围
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickTimeList.map((t) {
                      final isSel = _selectedTimeRange == t;
                      return ChoiceChip(
                        showCheckmark: false,
                        label: Text(
                          t,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSel ? colors.onPrimary : colors.onSurface,
                          ),
                        ),
                        selected: isSel,
                        selectedColor: const Color(0xFF1E88E5),
                        onSelected: (_) {
                          Navigator.pop(ctx);
                          setState(() => _selectedTimeRange = t);
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // 2. 迷你自定义时间图标按钮视图（非全屏迷你弹窗）
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final picked = await CompactDateRangeDialog.show(
                        context,
                        initialRange: _customDateRange,
                      );
                      if (picked != null) {
                        setState(() {
                          _customDateRange = picked;
                          _selectedTimeRange = '自定义';
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _selectedTimeRange == '自定义'
                            ? const Color(0xFF1E88E5).withValues(alpha: 0.12)
                            : Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedTimeRange == '自定义'
                              ? const Color(0xFF1E88E5)
                              : Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1E88E5,
                              ).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              AppIcons.edit_calendar_outlined,
                              size: 18,
                              color: Color(0xFF1E88E5),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '自定义日期范围',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _customDateRange != null
                                      ? '${DateFormatter.formatChineseYmd(_customDateRange!.start)} 至 ${DateFormatter.formatChineseYmd(_customDateRange!.end)}'
                                      : '点此选取任意起始和截止日期',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            AppIcons.chevron_right,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasActiveFilters =
        _selectedFuelType != '全部' ||
        _selectedTankStatus != '全部' ||
        _selectedEfficiency != '全部' ||
        _onlyWithNotes;

    final isCustomTime =
        _selectedTimeRange == '自定义' && _customDateRange != null;
    final timeLabel = isCustomTime
        ? '${DateFormatter.formatMonthDay(_customDateRange!.start)}~${DateFormatter.formatMonthDay(_customDateRange!.end)}'
        : _selectedTimeRange;

    return Scaffold(
      appBar: AppBar(
        title: const AppPageTitle(title: '明细账本', subtitle: '加油、费用与筛选记录'),
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF5A24),
          labelColor: const Color(0xFFFF5A24),
          unselectedLabelColor: colors.onSurfaceVariant,
          tabs: const [
            Tab(text: '加油记录'),
            Tab(text: '其它费用'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            // 允许左右滑动切换加油/其他费用；卡片自身的横向拖拽在
            // 手势竞技场中优先级更高，互不冲突
            physics: const ClampingScrollPhysics(),
            children: [
              _RefuelRecordListView(
                searchQuery: _searchQuery,
                fuelTypeFilter: _selectedFuelType,
                tankStatusFilter: _selectedTankStatus,
                efficiencyFilter: _selectedEfficiency,
                onlyWithNotes: _onlyWithNotes,
                hasActiveFilters: hasActiveFilters,
                timeRange: _selectedTimeRange,
                isCustomTime: isCustomTime,
                timeLabel: timeLabel,
                hasSeenSwipeHint: _hasSeenSwipeHint,
                onDismissSwipeHint: _dismissSwipeHintPermanently,
                onOpenFilterModal: () => _showAdvancedFilterModal(context),
                onOpenTimeModal: () => _showTimeRangeModal(context),
                onResetAllFilters: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _selectedFuelType = '全部';
                    _selectedTankStatus = '全部';
                    _selectedEfficiency = '全部';
                    _onlyWithNotes = false;
                    _selectedTimeRange = '全部时间';
                    _customDateRange = null;
                    _searchController.clear();
                    _searchQuery = '';
                  });
                },
                scrollController: _scrollController,
                swipeController: _refuelSwipeController,
                customDateRange: _customDateRange,
              ),
              const _ExpenseRecordListView(),
            ],
          ),

          // 右下角悬停按钮组：底栏未隐藏时上移避让，隐藏后贴边
          ValueListenableBuilder<bool>(
            valueListenable: widget.navVisible,
            builder: (context, navVisible, child) {
              // 回顶/搜索仅作用于加油列表，费用页签下隐藏避免误导
              if (_currentTabIndex != 0) {
                return const SizedBox.shrink();
              }
              final double bottomInset = MediaQuery.of(context).padding.bottom;
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                right: 16,
                bottom: navVisible ? bottomInset + 80 : 28,
                child: child!,
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 回到顶部按钮（滚动超过阈值时顺滑出现）
                AnimatedScale(
                  scale: _showBackToTop ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: AnimatedOpacity(
                    opacity: _showBackToTop ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
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
                            child: const Icon(
                              AppIcons.arrow_upward,
                              size: 20,
                              color: Color(0xFFFF5A24),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. 搜索悬浮按钮
                Material(
                  elevation: 4,
                  shape: const CircleBorder(),
                  color: _searchQuery.isNotEmpty
                      ? const Color(0xFFFF5A24)
                      : Theme.of(context).cardColor,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _showSearchDialog(context),
                    child: Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            AppIcons.search,
                            size: 22,
                            color: _searchQuery.isNotEmpty
                                ? Colors.white
                                : const Color(0xFFFF5A24),
                          ),
                          if (_searchQuery.isNotEmpty)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.amberAccent,
                                  shape: BoxShape.circle,
                                ),
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
    );
  }
}

/// 加油记录列表子视图（纯净双项筛选栏 + 纯净左滑编辑删除）
class _RefuelRecordListView extends StatelessWidget {
  final String searchQuery;
  final String fuelTypeFilter;
  final String tankStatusFilter;
  final String efficiencyFilter;
  final bool onlyWithNotes;
  final bool hasActiveFilters;
  final String timeRange;
  final bool isCustomTime;
  final String timeLabel;
  final bool hasSeenSwipeHint;
  final VoidCallback onDismissSwipeHint;
  final VoidCallback onOpenFilterModal;
  final VoidCallback onOpenTimeModal;
  final VoidCallback onResetAllFilters;
  final ScrollController scrollController;
  final _RefuelSwipeController swipeController;
  final DateTimeRange? customDateRange;

  const _RefuelRecordListView({
    required this.searchQuery,
    required this.fuelTypeFilter,
    required this.tankStatusFilter,
    required this.efficiencyFilter,
    required this.onlyWithNotes,
    required this.hasActiveFilters,
    required this.timeRange,
    required this.isCustomTime,
    required this.timeLabel,
    required this.hasSeenSwipeHint,
    required this.onDismissSwipeHint,
    required this.onOpenFilterModal,
    required this.onOpenTimeModal,
    required this.onResetAllFilters,
    required this.scrollController,
    required this.swipeController,
    required this.customDateRange,
  });

  @override
  Widget build(BuildContext context) {
    final refuelProv = context.watch<RefuelProvider>();
    final colors = Theme.of(context).colorScheme;
    final allRecords = refuelProv.records.reversed.toList();
    final avgConsumption = refuelProv.summary.averageConsumption;

    if (refuelProv.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (refuelProv.errorMessage != null) {
      final vehicle = context.read<VehicleProvider>().currentVehicle;
      return _DataLoadErrorView(
        message: refuelProv.errorMessage!,
        onRetry: vehicle == null
            ? null
            : () => refuelProv.loadRecords(vehicle.id),
      );
    }

    if (allRecords.isEmpty) {
      return EmptyStateView(
        title: '暂无加油记录',
        subtitle: '点击下方按钮记录第一笔加油数据',
        buttonText: '记加油',
        onButtonPressed: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddRefuelScreen()),
          );
        },
      );
    }

    final now = DateTime.now();

    // 1. 根据时间范围过滤
    final timeFiltered = allRecords.where((r) {
      // 自定义范围按日界比较（与统计页口径一致），且不隐藏未来的补录记录
      if (isCustomTime && customDateRange != null) {
        final start = DateTime(
          customDateRange!.start.year,
          customDateRange!.start.month,
          customDateRange!.start.day,
        );
        final end = DateTime(
          customDateRange!.end.year,
          customDateRange!.end.month,
          customDateRange!.end.day,
          23,
          59,
          59,
        );
        return !r.refuelDate.isBefore(start) && !r.refuelDate.isAfter(end);
      }
      final age = now.difference(r.refuelDate);
      // 仅相对时间范围（近1天/近1周...）排除未来记录，"全部时间"应显示补录
      Duration? maxAge;
      if (timeRange == '近1天') {
        if (age.isNegative) return false;
        maxAge = const Duration(days: 1);
      } else if (timeRange == '近1周') {
        if (age.isNegative) return false;
        maxAge = const Duration(days: 7);
      } else if (timeRange == '近1月 (近30天)') {
        if (age.isNegative) return false;
        maxAge = const Duration(days: 30);
      } else if (timeRange == '近半年') {
        if (age.isNegative) return false;
        maxAge = const Duration(days: 183);
      } else if (timeRange == '近1年') {
        if (age.isNegative) return false;
        maxAge = const Duration(days: 365);
      } else if (timeRange == '今年') {
        return r.refuelDate.year == now.year;
      }
      return maxAge == null || !r.refuelDate.isBefore(now.subtract(maxAge));
    }).toList();

    // 2. 根据综合筛选与搜索过滤
    final filtered = timeFiltered.where((r) {
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matchStation = r.gasStation?.toLowerCase().contains(q) ?? false;
        final matchNote = r.note?.toLowerCase().contains(q) ?? false;
        final matchFuel = r.fuelType.toLowerCase().contains(q);
        if (!matchStation && !matchNote && !matchFuel) return false;
      }

      if (fuelTypeFilter != '全部' && !r.fuelType.contains(fuelTypeFilter)) {
        return false;
      }
      if (tankStatusFilter == '仅加满' && !r.isFullTank) return false;
      if (tankStatusFilter == '未加满' && r.isFullTank) return false;
      if (efficiencyFilter == '经济省油' &&
          (r.fuelConsumption == null ||
              avgConsumption <= 0 ||
              r.fuelConsumption! > avgConsumption)) {
        return false;
      }
      if (efficiencyFilter == '油耗偏高' &&
          (r.fuelConsumption == null ||
              avgConsumption <= 0 ||
              r.fuelConsumption! <= avgConsumption)) {
        return false;
      }
      if (onlyWithNotes && (r.note == null || r.note!.trim().isEmpty)) {
        return false;
      }

      return true;
    }).toList();

    // 3. 按年月分组
    final Map<String, List<RefuelRecordModel>> monthlyGroups = {};
    for (final r in filtered) {
      final key =
          '${r.refuelDate.year}年${r.refuelDate.month.toString().padLeft(2, '0')}月';
      monthlyGroups.putIfAbsent(key, () => []).add(r);
    }

    return Column(
      children: [
        // 顶部精简双项筛选栏
        _buildTwoItemFilterBar(context),

        // 搜索中状态或未操作过的手势提示条（正常操作或关闭后永久隐藏）
        if (searchQuery.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: const Color(0xFFFF5A24).withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(AppIcons.search, size: 14, color: Color(0xFFFF5A24)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '搜索中关键词: “$searchQuery” (共匹配 ${filtered.length} 笔)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF5A24),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else if (!hasSeenSwipeHint)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: Colors.grey.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(AppIcons.swipe, size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '向左滑动卡片可进行编辑或删除',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: onDismissSwipeHint,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Icon(
                      AppIcons.close,
                      size: 14,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        AppIcons.search_off,
                        size: 48,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '在当前筛选条件下未找到匹配记录',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : NotificationListener<ScrollStartNotification>(
                  onNotification: (notification) {
                    // 用户开始拖动滚动时收起已滑开的卡片
                    if (notification.dragDetails != null) {
                      swipeController.close();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: scrollController,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                    padding: const EdgeInsets.only(top: 6, bottom: 24),
                    itemCount: monthlyGroups.keys.length,
                    itemBuilder: (context, groupIndex) {
                      final monthKey = monthlyGroups.keys.elementAt(groupIndex);
                      final groupRecords = monthlyGroups[monthKey]!;

                      final totalFuel = groupRecords.fold(
                        0.0,
                        (sum, r) => sum + r.fuelAmount,
                      );
                      final totalCost = groupRecords.fold(
                        0.0,
                        (sum, r) => sum + r.totalPrice,
                      );
                      final validConsumptions = groupRecords
                          .where(
                            (r) =>
                                r.fuelConsumption != null &&
                                r.fuelConsumption! > 0,
                          )
                          .map((r) => r.fuelConsumption!)
                          .toList();
                      final monthAvg = validConsumptions.isNotEmpty
                          ? (validConsumptions.reduce((a, b) => a + b) /
                                validConsumptions.length)
                          : 0.0;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMonthSummaryCard(
                            context,
                            monthKey,
                            groupRecords.length,
                            totalFuel,
                            totalCost,
                            monthAvg,
                          ),
                          ...groupRecords.map((r) {
                            return RepaintBoundary(
                              key: ValueKey(r.id),
                              child: _SlidableRefuelItemCard(
                                record: r,
                                globalAvgConsumption: avgConsumption,
                                swipeController: swipeController,
                                onOperated: onDismissSwipeHint,
                                onEdit: () {
                                  onDismissSwipeHint();
                                  HapticFeedback.lightImpact();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AddRefuelScreen(editRecord: r),
                                    ),
                                  );
                                },
                                onDelete: () async {
                                  HapticFeedback.lightImpact();
                                  final confirm = await _showDeleteConfirmDialog(
                                    context,
                                    title: '删除加油记录',
                                    summary:
                                        '${DateFormatter.formatYmdHm(r.refuelDate)} · ${r.fuelAmount.toStringAsFixed(2)}升 · ¥${r.totalPrice.toStringAsFixed(2)}'
                                        '${(r.gasStation != null && r.gasStation!.isNotEmpty) ? "\n${r.gasStation}" : ""}',
                                  );
                                  if (confirm == true && context.mounted) {
                                    final deleted = r;
                                    final success = await refuelProv
                                        .deleteRecord(r.id);
                                    if (!success) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('删除失败，请重试'),
                                        ),
                                      );
                                      return;
                                    }

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: const Text('已删除 1 笔加油记录'),
                                          duration: const Duration(seconds: 5),
                                          behavior: SnackBarBehavior.floating,
                                          action: SnackBarAction(
                                            label: '撤销恢复',
                                            textColor: Colors.amberAccent,
                                            onPressed: () async {
                                              HapticFeedback.lightImpact();
                                              await refuelProv.addRecord(
                                                deleted,
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// 筛选栏两项：1为综合筛选按钮，2为时间范围控件（支持迷你自定义时间图标展示）
  Widget _buildTwoItemFilterBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          // 1. 综合筛选按钮
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onOpenFilterModal,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: hasActiveFilters
                      ? const Color(0xFFFF5A24).withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasActiveFilters
                        ? const Color(0xFFFF5A24)
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      AppIcons.tune,
                      size: 16,
                      color: hasActiveFilters
                          ? const Color(0xFFFF5A24)
                          : colors.onSurface,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasActiveFilters ? '已筛选' : '综合筛选',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: hasActiveFilters
                            ? const Color(0xFFFF5A24)
                            : colors.onSurface,
                      ),
                    ),
                    Icon(
                      AppIcons.arrow_drop_down,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 2. 时间控件按钮（包含迷你自定义日期图标视图）
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onOpenTimeModal,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: timeRange != '全部时间'
                      ? const Color(0xFF1E88E5).withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: timeRange != '全部时间'
                        ? const Color(0xFF1E88E5)
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isCustomTime
                          ? AppIcons.edit_calendar_outlined
                          : AppIcons.calendar_month,
                      size: 16,
                      color: timeRange != '全部时间'
                          ? const Color(0xFF1E88E5)
                          : colors.onSurface,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: timeRange != '全部时间'
                              ? const Color(0xFF1E88E5)
                              : colors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      AppIcons.arrow_drop_down,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. 筛选激活状态下的一键重置按钮
          if (hasActiveFilters || timeRange != '全部时间' || searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: InkWell(
                onTap: onResetAllFilters,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.refresh, size: 14, color: Colors.redAccent),
                      SizedBox(width: 4),
                      Text(
                        '重置',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthSummaryCard(
    BuildContext context,
    String monthKey,
    int count,
    double fuel,
    double cost,
    double avg,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5A24).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFF5A24).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(
                AppIcons.calendar_month,
                color: Color(0xFFFF5A24),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                monthKey,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFFFF5A24),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '($count笔)',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                '${fuel.toStringAsFixed(1)}L | ¥${cost.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (avg > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '均 ${avg.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 高性能单向左滑卡片（纯净左滑调出编辑/删除，无右滑多选）
/// 账本记录删除确认弹窗：品牌风格，展示记录摘要与撤销提示。
Future<bool?> _showDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String summary,
  String confirmLabel = '删除',
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final colors = Theme.of(ctx).colorScheme;
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.delete_outline,
                color: Colors.red,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary, style: const TextStyle(fontSize: 13, height: 1.5)),
            const SizedBox(height: 8),
            Text(
              '删除后可在提示条中撤销恢复。',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

/// 账本左滑卡片协调器：同一时间只允许一张卡片处于滑开状态，
/// 并支持在滚动开始或点击其他区域时统一收起。
class _RefuelSwipeController {
  _SlidableRefuelItemCardState? _openCard;

  /// 请求滑开 [card]，同时收起当前已滑开的其他卡片
  void opened(_SlidableRefuelItemCardState card) {
    if (_openCard == card) return;
    _openCard?._collapse();
    _openCard = card;
  }

  /// 通知 [card] 已收起，解除登记
  void closed(_SlidableRefuelItemCardState card) {
    if (_openCard == card) {
      _openCard = null;
    }
  }

  /// 收起当前滑开的卡片（如滚动开始时）
  void close() {
    _openCard?._collapse();
    _openCard = null;
  }
}

class _SlidableRefuelItemCard extends StatefulWidget {
  final RefuelRecordModel record;
  final double globalAvgConsumption;
  final _RefuelSwipeController swipeController;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onOperated;

  const _SlidableRefuelItemCard({
    required this.record,
    required this.globalAvgConsumption,
    required this.swipeController,
    required this.onEdit,
    required this.onDelete,
    this.onOperated,
  });

  @override
  State<_SlidableRefuelItemCard> createState() =>
      _SlidableRefuelItemCardState();
}

class _SlidableRefuelItemCardState extends State<_SlidableRefuelItemCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  static const double _actionWidth = 140.0; // 编辑70 + 删除70

  _RefuelSwipeController get swipeController => widget.swipeController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0.0, end: 0.0).animate(_controller);
    _controller.addListener(() {
      if (mounted) setState(() => _dragOffset = _animation.value);
    });
  }

  @override
  void dispose() {
    swipeController.closed(this);
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _animation = Tween<double>(
      begin: _dragOffset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0.0);
  }

  void _resetPosition() {
    _animateTo(0.0);
  }

  /// 收起卡片（供滑动协调器调用），仅当已滑开时才执行动画
  void _collapse() {
    if (!mounted) return;
    if (_dragOffset != 0) {
      _resetPosition();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final colors = Theme.of(context).colorScheme;
    final hasConsumption = r.fuelConsumption != null && r.fuelConsumption! > 0;
    final isEconomy =
        hasConsumption &&
        widget.globalAvgConsumption > 0 &&
        r.fuelConsumption! <= widget.globalAvgConsumption;
    final isHigher =
        hasConsumption &&
        widget.globalAvgConsumption > 0 &&
        r.fuelConsumption! > widget.globalAvgConsumption * 1.1;
    final isAnomaly =
        hasConsumption &&
        widget.globalAvgConsumption > 0 &&
        (r.fuelConsumption! > widget.globalAvgConsumption * 1.8 ||
            r.fuelConsumption! < widget.globalAvgConsumption * 0.4);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. 底层右侧操作抽屉（左滑显示编辑与删除）
          Positioned.fill(
            child: Container(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: () {
                      swipeController.closed(this);
                      _resetPosition();
                      widget.onEdit();
                    },
                    child: Container(
                      width: 70,
                      color: const Color(0xFF1E88E5),
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            AppIcons.edit_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                          SizedBox(height: 2),
                          Text(
                            '编辑',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      swipeController.closed(this);
                      _resetPosition();
                      widget.onOperated?.call();
                      widget.onDelete();
                    },
                    child: Container(
                      width: 70,
                      color: Colors.redAccent,
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            AppIcons.delete_outline,
                            color: Colors.white,
                            size: 22,
                          ),
                          SizedBox(height: 2),
                          Text(
                            '删除',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. 表层主卡片（仅允许向左拖拽；滑开后仍可点击/右滑收回）
          //   Transform 必须在 GestureDetector 外层：命中区域才会跟随卡片平移，
          //   否则未平移的整行命中框会吞掉右侧"编辑/删除"按钮的点击。
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _dragOffset += details.primaryDelta!;
                  // 仅允许左滑（负偏移），禁止右滑（最大为 0.0）
                  _dragOffset = _dragOffset.clamp(-_actionWidth, 0.0);
                });
              },
              onHorizontalDragEnd: (details) {
                if (_dragOffset < -45) {
                  // 左滑超过阈值：露出右侧编辑与删除抽屉，并收起其他已滑开的卡片
                  HapticFeedback.lightImpact();
                  widget.onOperated?.call();
                  swipeController.opened(this);
                  _animateTo(-_actionWidth);
                } else {
                  swipeController.closed(this);
                  _resetPosition();
                }
              },
              onTap: () {
                if (_dragOffset != 0) {
                  // 已滑开时点击卡片任意位置收回
                  swipeController.closed(this);
                  _resetPosition();
                } else {
                  _showRefuelDetailSheet(
                    context,
                    r,
                    widget.globalAvgConsumption,
                  );
                }
              },
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  // 右侧直角：滑动时与抽屉保持平直拼缝，整体圆角由外层容器裁剪
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                AppIcons.local_gas_station,
                                color: Color(0xFFFF5A24),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormatter.formatYmdHm(r.refuelDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              if (r.fuelWarningLightOn == true) ...[
                                const SizedBox(width: 4),
                                const Tooltip(
                                  message: '加油时油量警告灯已点亮',
                                  child: Icon(
                                    AppIcons.warning_amber_rounded,
                                    size: 14,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (hasConsumption)
                            Row(
                              children: [
                                if (isAnomaly) ...[
                                  const Tooltip(
                                    message: '此笔油耗偏离平均值较多，可能存在漏记里程或升数偏差',
                                    child: Icon(
                                      AppIcons.warning_amber_rounded,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                if (isEconomy)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '节省 ${((widget.globalAvgConsumption - r.fuelConsumption!).abs()).toStringAsFixed(1)}L',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else if (isHigher)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '偏高 ${((r.fuelConsumption! - widget.globalAvgConsumption).abs()).toStringAsFixed(1)}L',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFF5A24,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${r.fuelConsumption!.toStringAsFixed(2)} L/100km',
                                    style: const TextStyle(
                                      color: Color(0xFFFF5A24),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else if (!r.isFullTank)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '未加满 (累计平摊)',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else if (r.isForgotPrevious)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '漏记前次 (新基准)',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '¥${r.totalPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF5A24),
                                  ),
                                ),
                                if (r.discountAmount != null &&
                                    r.discountAmount! > 0) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '已优惠 ¥${r.discountAmount!.toStringAsFixed(2)}（机显 ¥${(r.fuelAmount * r.unitPrice).toStringAsFixed(2)}）',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  '${r.fuelAmount.toStringAsFixed(2)}升 @ ¥${r.unitPrice.toStringAsFixed(2)}/升 (${r.fuelType})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${r.mileage.toStringAsFixed(2)} km',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (r.distance != null)
                                Text(
                                  '行驶 +${r.distance!.toStringAsFixed(2)} km',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (r.costPerKm != null)
                                Text(
                                  '¥${r.costPerKm!.toStringAsFixed(2)}/km',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (r.gasStation != null && r.gasStation!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              AppIcons.location_on_outlined,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                r.gasStation!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (r.note != null && r.note!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              AppIcons.edit_note,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                r.note!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRefuelDetailSheet(
    BuildContext context,
    RefuelRecordModel r,
    double globalAvg,
  ) {
    HapticFeedback.selectionClick();
    final colors = Theme.of(context).colorScheme;
    final hasConsumption = r.fuelConsumption != null && r.fuelConsumption! > 0;
    final distance = r.distance ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶端把手
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 账本审查发现提示
              FutureBuilder<List<AuditFinding>>(
                future: context.read<AuditProvider>().findingsForRecord(r.id),
                builder: (context, snapshot) {
                  final pendingFindings =
                      snapshot.data?.where((f) => f.isPending).toList() ??
                      const <AuditFinding>[];
                  if (pendingFindings.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          AppIcons.warning_amber_rounded,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '此记录存在 ${pendingFindings.length} 项待确认问题（账本审查）',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        AppIcons.receipt_long_outlined,
                        color: Color(0xFFFF5A24),
                        size: 22,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '加油明细参数',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    DateFormatter.formatYmdHm(r.refuelDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),

              // 核心数值三列概览
              Row(
                children: [
                  Expanded(
                    child: _buildDetailCell(
                      '实测油耗',
                      hasConsumption
                          ? '${r.fuelConsumption!.toStringAsFixed(2)} L/100km'
                          : (r.isFullTank ? '基准起算' : '未加满'),
                      const Color(0xFFFF5A24),
                    ),
                  ),
                  Expanded(
                    child: _buildDetailCell(
                      '单公里油费',
                      r.costPerKm != null
                          ? '¥ ${r.costPerKm!.toStringAsFixed(2)}/km'
                          : '--',
                      const Color(0xFF1E88E5),
                    ),
                  ),
                  Expanded(
                    child: _buildDetailCell(
                      '实付总额',
                      '¥ ${r.totalPrice.toStringAsFixed(2)}',
                      colors.onSurface,
                    ),
                  ),
                ],
              ),
              if (r.discountAmount != null && r.discountAmount! > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailCell(
                        '机显金额',
                        '¥ ${(r.fuelAmount * r.unitPrice).toStringAsFixed(2)}',
                        colors.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: _buildDetailCell(
                        '优惠金额',
                        '-¥ ${r.discountAmount!.toStringAsFixed(2)}',
                        Colors.green[700]!,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // 加油关键参数表
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  children: [
                    _buildDetailRow('加油站', r.gasStation ?? '未填写'),
                    _buildDetailRow('燃油标号', r.fuelType),
                    _buildDetailRow(
                      '单价 / 升数',
                      '¥${r.unitPrice.toStringAsFixed(2)}/L · ${r.fuelAmount.toStringAsFixed(2)}L',
                    ),
                    _buildDetailRow(
                      '油量警告灯',
                      r.fuelWarningLightOn == null
                          ? '未记录'
                          : (r.fuelWarningLightOn! ? '点亮' : '未点亮'),
                    ),
                    _buildDetailRow(
                      '表显总里程',
                      '${r.mileage.toStringAsFixed(2)} km',
                    ),
                    _buildDetailRow(
                      '本箱行驶里程',
                      distance > 0
                          ? '${distance.toStringAsFixed(2)} km'
                          : '新基准',
                    ),
                    _buildDetailRow(
                      '加满状态',
                      r.isFullTank ? '已加满跳枪' : '未加满 (油量累计至下次)',
                    ),
                    if (r.note != null && r.note!.isNotEmpty)
                      _buildDetailRow('备注说明', r.note!),
                  ],
                ),
              ),
              if (hasConsumption && distance > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5A24).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        AppIcons.functions,
                        size: 16,
                        color: Color(0xFFFF5A24),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${r.fuelAmount.toStringAsFixed(2)} L ÷ ${distance.toStringAsFixed(2)} km × 100 = ${(r.fuelConsumption ?? 0.0).toStringAsFixed(2)} L/100km',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFF5A24),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailCell(String label, String value, Color color) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 其它费用列表子视图
class _ExpenseRecordListView extends StatefulWidget {
  const _ExpenseRecordListView();

  @override
  State<_ExpenseRecordListView> createState() => _ExpenseRecordListViewState();
}

class _ExpenseRecordListViewState extends State<_ExpenseRecordListView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expenseProv = context.watch<ExpenseProvider>();
    final refuelProv = context.read<RefuelProvider>();
    final colors = Theme.of(context).colorScheme;
    final expenses = expenseProv.expenses;

    if (expenseProv.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (expenseProv.errorMessage != null) {
      final vehicle = context.read<VehicleProvider>().currentVehicle;
      return _DataLoadErrorView(
        message: expenseProv.errorMessage!,
        onRetry: vehicle == null
            ? null
            : () => expenseProv.loadExpenses(vehicle.id),
      );
    }

    if (expenses.isEmpty) {
      return EmptyStateView(
        title: '暂无其它费用记录',
        subtitle: '记录保养、保险、洗车、停车等用车开销',
        buttonText: '记一笔费用',
        onButtonPressed: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
          );
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
      // AlwaysScrollable：内容不满一屏时拖动同样产生滚动方向通知，
      // 保证底栏"上滑隐藏、下滑呼出"在费用页同样生效
      physics: const AlwaysScrollableScrollPhysics(),
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: expenses.length,
      itemBuilder: (context, index) {
        final e = expenses[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF1E88E5).withValues(alpha: 0.12),
              child: const Icon(
                AppIcons.account_balance_wallet,
                color: Color(0xFF1E88E5),
                size: 20,
              ),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  e.category,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '¥${e.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF1E88E5),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  '${DateFormatter.formatYmdHm(e.expenseDate)}'
                  '${e.currentMileage != null ? " · ${e.currentMileage!.toStringAsFixed(1)}km" : ""}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (e.note != null && e.note!.isNotEmpty)
                  Text(
                    '备注: ${e.note}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(
                AppIcons.delete_outline,
                size: 18,
                color: Colors.red,
              ),
              onPressed: () async {
                HapticFeedback.lightImpact();
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除费用记录'),
                    content: const Text('确定要删除这笔开销记录吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  final deleted = e;
                  final success = await expenseProv.deleteExpense(e.id);
                  if (!success) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
                    return;
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('已删除 1 笔费用记录'),
                        duration: const Duration(seconds: 5),
                        behavior: SnackBarBehavior.floating,
                        action: SnackBarAction(
                          label: '撤销恢复',
                          textColor: Colors.amberAccent,
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            await expenseProv.addExpense(
                              deleted,
                              currentMaxMileage: refuelProv.latestMileage,
                            );
                          },
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ),
        );
      },
    );
  }
}

class _DataLoadErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _DataLoadErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.error_outline, color: colors.error, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(AppIcons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
