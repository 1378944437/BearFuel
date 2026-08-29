import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/vehicle_provider.dart';
import '../../providers/refuel_provider.dart';
import '../../providers/expense_provider.dart';
import 'dashboard/dashboard_screen.dart';
import 'records/record_list_screen.dart';
import 'charts/statistics_screen.dart';
import 'vehicle/vehicle_management_screen.dart';
import 'refuel/add_refuel_screen.dart';

/// 底部导航主框架页面（集成滑动自适应隐藏底栏扩展可视面积、双击防误触侧滑退出拦截）
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  DateTime? _lastBackTime;
  bool _isNavVisible = true;

  @override
  void initState() {
    super.initState();
    // 首次进入加载车辆与对应记录
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vehicleProv = context.read<VehicleProvider>();
      await vehicleProv.loadVehicles();

      if (vehicleProv.currentVehicle != null && mounted) {
        final vId = vehicleProv.currentVehicle!.id;
        final refuelProv = context.read<RefuelProvider>();
        await refuelProv.loadRecords(vId);

        if (mounted) {
          final expenseProv = context.read<ExpenseProvider>();
          await expenseProv.loadExpenses(
            vId,
            currentMaxMileage: refuelProv.latestMileage,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<Widget> pages = [
      DashboardScreen(
        onNavigateToRecords: () {
          setState(() => _currentIndex = 1);
        },
      ),
      const RecordListScreen(),
      const StatisticsScreen(),
      const VehicleManagementScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // 一级主界面：在 4 个主 Tab（仪表盘、明细账本、统计图表、爱车档案）任意页面，
        // 连续侧滑返回两次即可直接安全退出应用，不再强制切换回仪表盘
        final now = DateTime.now();
        if (_lastBackTime == null ||
            now.difference(_lastBackTime!) > const Duration(seconds: 2)) {
          _lastBackTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('再侧滑返回一次退出应用'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        extendBody: true,
        body: NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            // 自适应滚动监测：向上滑动隐藏底栏以最大化可视范围，向下滑动时呼出底栏
            if (notification.direction == ScrollDirection.reverse) {
              if (_isNavVisible) {
                setState(() => _isNavVisible = false);
              }
            } else if (notification.direction == ScrollDirection.forward) {
              if (!_isNavVisible) {
                setState(() => _isNavVisible = true);
              }
            }
            return false;
          },
          child: IndexedStack(index: _currentIndex, children: pages),
        ),
        floatingActionButton: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: _isNavVisible ? Offset.zero : const Offset(0, 2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _isNavVisible ? 1.0 : 0.0,
            child: FloatingActionButton(
              tooltip: '记录加油',
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddRefuelScreen()),
                );
              },
              child: const Icon(AppIcons.add, size: 24),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: _isNavVisible ? Offset.zero : const Offset(0, 1.2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _isNavVisible ? 1.0 : 0.0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: isDark ? 0.96 : 0.98),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.24 : 0.08,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    children: [
                      _buildNavTabItem(0, AppIcons.speed, '仪表盘'),
                      _buildNavTabItem(1, AppIcons.receipt_long, '账本'),
                      const SizedBox(width: 54),
                      _buildNavTabItem(2, AppIcons.bar_chart, '统计'),
                      _buildNavTabItem(3, AppIcons.directions_car, '爱车'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTabItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final colors = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: isSelected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
