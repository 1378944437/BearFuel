import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../core/utils/location_service.dart';

/// 仿天气软件的高颜值城市与地区选择弹窗
class CityPickerSheet extends StatefulWidget {
  final String currentCity;
  final UserLocation? currentGpsLocation;
  final bool domesticOnly;

  const CityPickerSheet({
    super.key,
    required this.currentCity,
    this.currentGpsLocation,
    this.domesticOnly = false,
  });

  /// 快速弹出城市选择器
  static Future<String?> show(
    BuildContext context, {
    required String currentCity,
    UserLocation? currentGpsLocation,
    bool domesticOnly = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CityPickerSheet(
        currentCity: currentCity,
        currentGpsLocation: currentGpsLocation,
        domesticOnly: domesticOnly,
      ),
    );
  }

  @override
  State<CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<CityPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  bool _isExpanded = false;
  bool _isLocating = false;
  String? _locatedCity;

  // 国内热门城市列表 (参照主流天气 App 排序，优先包含荆门、武汉等重点地市)
  static const List<String> _domesticHotCities = [
    '北京',
    '上海',
    '广州',
    '深圳',
    '天津',
    '杭州',
    '东莞',
    '宁波',
    '西安',
    '成都',
    '重庆',
    '南京',
    '苏州',
    '武汉',
    '厦门',
    '福州',
    '昆明',
    '沈阳',
    '长春',
    '大连',
    '荆门',
    '宜昌',
    '襄阳',
    '荆州',
    '长沙',
    '郑州',
    '济南',
    '青岛',
    '合肥',
    '南昌',
    '南宁',
    '贵阳',
    '海口',
    '三亚',
    '哈尔滨',
    '太原',
    '兰州',
    '乌鲁木齐',
    '呼和浩特',
    '银川',
    '西宁',
    '拉萨',
  ];

  // 国际热门城市列表
  static const List<String> _internationalHotCities = [
    '纽约',
    '巴黎',
    '伦敦',
    '东京',
    '洛杉矶',
    '首尔',
    '悉尼',
    '多伦多',
    '曼谷',
    '新加坡',
    '迪拜',
    '吉隆坡',
  ];

  @override
  void initState() {
    super.initState();
    _locatedCity = widget.currentGpsLocation?.cityName;
    if (_locatedCity == null || _locatedCity!.isEmpty) {
      _silentGpsLocate();
    }
  }

  Future<void> _silentGpsLocate() async {
    try {
      final result = await LocationService.getCurrentLocation();
      if (mounted && result.isSuccess && result.location != null) {
        setState(() {
          _locatedCity = result.location!.cityName;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 触发 GPS 重新卫星定位
  Future<void> _triggerGpsLocate() async {
    setState(() => _isLocating = true);
    try {
      final result = await LocationService.getCurrentLocation();
      if (!mounted) return;

      setState(() => _isLocating = false);
      if (result.isSuccess && result.location != null) {
        final city = result.location!.cityName;
        setState(() => _locatedCity = city);
        // 定位成功直接返回该城市
        Navigator.pop(context, city);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLocating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定位服务提示: $e'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final cardBg = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF3F4F6);
    final query = _searchController.text.trim();

    return Material(
      color: bgColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 顶部现代化搜索栏与“取消”控件
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: false,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(fontSize: 14, color: colors.onSurface),
                      decoration: InputDecoration(
                        hintText: '输入城市名称（如 荆门、武汉、北京）',
                        prefixIcon: Icon(
                          AppIcons.search,
                          color: query.isNotEmpty
                              ? const Color(0xFFFF5A24)
                              : colors.onSurfaceVariant,
                        ),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                tooltip: '清除搜索',
                                icon: const Icon(AppIcons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5A24),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: const Text('取消'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. 搜索过滤结果列表 或 热门城市九宫格
              Expanded(
                child: query.isNotEmpty
                    ? _buildSearchResults(query, isDark, cardBg)
                    : _buildHotCitySections(isDark, cardBg),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 搜索实时匹配结果
  Widget _buildSearchResults(String query, bool isDark, Color cardBg) {
    final colors = Theme.of(context).colorScheme;
    final allCities = {
      ..._domesticHotCities,
      '荆门',
      '武汉',
      '襄阳',
      '宜昌',
      '十堰',
      '荆州',
      '黄石',
      '黄冈',
      '鄂州',
      '咸宁',
      '随州',
      '恩施',
      '仙桃',
      '潜江',
      '天门',
      '神农架',
    }.toList();

    final matches = allCities.where((c) => c.contains(query)).toList();

    if (matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.location_off,
              size: 48,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '未找到包含 “$query” 的城市',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: matches.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final city = matches[index];
        final isCurrent = city == widget.currentCity;

        return ListTile(
          leading: Icon(
            AppIcons.location_city,
            color:
                isCurrent ? const Color(0xFFFF5A24) : colors.onSurfaceVariant,
          ),
          title: Text(
            city,
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent ? const Color(0xFFFF5A24) : null,
            ),
          ),
          trailing: isCurrent
              ? const Icon(
                  AppIcons.check_circle,
                  color: Color(0xFFFF5A24),
                  size: 20,
                )
              : Icon(
                  AppIcons.chevron_right,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
          onTap: () => Navigator.pop(context, city),
        );
      },
    );
  }

  /// 热门城市九宫格展示 (参照截图设计)
  Widget _buildHotCitySections(bool isDark, Color cardBg) {
    final colors = Theme.of(context).colorScheme;
    // 默认展示前 17 个城市 + 1个定位按钮 = 18个格子 (6排)
    final displayedCities =
        _isExpanded ? _domesticHotCities : _domesticHotCities.take(17).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // “国内热门城市” 标题
          Text(
            '国内热门城市',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),

          // 3列网格
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.6,
            ),
            itemCount: displayedCities.length + 1, // +1 是定位城市胶囊按钮
            itemBuilder: (context, index) {
              // 第 0 项始终为 “定位城市” 专属徽章按钮
              if (index == 0) {
                return _buildLocationPillButton(isDark);
              }

              final city = displayedCities[index - 1];
              final isSelected = city == widget.currentCity;

              return _buildCityPill(
                title: city,
                isSelected: isSelected,
                isDark: isDark,
                cardBg: cardBg,
                onTap: () => Navigator.pop(context, city),
              );
            },
          ),
          const SizedBox(height: 10),

          // “展开 ∨ / 收起 ∧” 切换按钮
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isExpanded ? '收起 ' : '展开 ',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Icon(
                      _isExpanded
                          ? AppIcons.keyboard_arrow_up
                          : AppIcons.keyboard_arrow_down,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (!widget.domesticOnly) ...[
            // “国际热门城市” 标题
            Text(
              '国际热门城市',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // 国际热门城市 3列网格
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.6,
              ),
              itemCount: _internationalHotCities.length,
              itemBuilder: (context, index) {
                final city = _internationalHotCities[index];
                final isSelected = city == widget.currentCity;

                return _buildCityPill(
                  title: city,
                  isSelected: isSelected,
                  isDark: isDark,
                  cardBg: cardBg,
                  onTap: () => Navigator.pop(context, city),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  /// 定位城市胶囊按钮 (带 GPS 图标与浅蓝高亮底色)
  Widget _buildLocationPillButton(bool isDark) {
    final hasLoc = _locatedCity != null && _locatedCity!.isNotEmpty;
    final isSelected = hasLoc && _locatedCity == widget.currentCity;

    return Material(
      color: isSelected
          ? const Color(0xFFE3F2FD) // 选中时浅蓝底色 (参照截图)
          : (isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEBF5FF)),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _isLocating ? null : _triggerGpsLocate,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _isLocating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF2196F3),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      AppIcons.location_on,
                      size: 14,
                      color: Color(0xFF2196F3),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        hasLoc ? '定位: $_locatedCity' : '定位城市',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2196F3),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// 单个城市胶囊按钮
  Widget _buildCityPill({
    required String title,
    required bool isSelected,
    required bool isDark,
    required Color cardBg,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? (isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEBF5FF))
          : cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? const Color(0xFF2196F3) // 选中城市文字变蓝 (参照截图)
                  : (isDark ? colors.onSurface : const Color(0xFF333333)),
            ),
          ),
        ),
      ),
    );
  }
}
