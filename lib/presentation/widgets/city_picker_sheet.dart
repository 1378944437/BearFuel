import 'package:bearfuel/core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../core/constants/china_cities.dart';
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
    // 仅回显外部已获取的定位城市；不在此处自动请求 GPS 权限，
    // 用户点击"定位城市"按钮时才触发定位。
    _locatedCity = widget.currentGpsLocation?.cityName;
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
    // 键盘弹出时压缩面板高度，保证搜索结果不被输入法遮挡
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final sheetHeight = MediaQuery.of(context).size.height * 0.88;

    return Material(
      color: bgColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: keyboardInset > 0 ? sheetHeight - keyboardInset : sheetHeight,
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
                              ? AppBrandColors.brand
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
                      foregroundColor: AppBrandColors.brand,
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

  /// 搜索实时匹配结果（覆盖全国城市，支持中文名/省份/全拼/首字母）
  Widget _buildSearchResults(String query, bool isDark, Color cardBg) {
    final colors = Theme.of(context).colorScheme;
    final matches = ChinaCities.search(query);

    // 非仅国内模式时，附加热门国际城市的名称匹配
    final internationalMatches = widget.domesticOnly
        ? const <String>[]
        : _internationalHotCities.where((c) => c.contains(query)).toList();

    if (matches.isEmpty && internationalMatches.isEmpty) {
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
            const SizedBox(height: 6),
            Text(
              '支持城市名、省份、拼音（wenzhou）或首字母（wz）',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final totalCount = matches.length + internationalMatches.length;
    return ListView.separated(
      itemCount: totalCount,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index < matches.length) {
          final city = matches[index];
          final isCurrent = city.name == widget.currentCity;
          return ListTile(
            leading: Icon(
              AppIcons.location_city,
              color: isCurrent ? AppBrandColors.brand : colors.onSurfaceVariant,
            ),
            title: Text(
              city.name,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent ? AppBrandColors.brand : null,
              ),
            ),
            subtitle: Text(
              city.province,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            trailing: isCurrent
                ? const Icon(
                    AppIcons.check_circle,
                    color: AppBrandColors.brand,
                    size: 20,
                  )
                : Icon(
                    AppIcons.chevron_right,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
            onTap: () => Navigator.pop(context, city.name),
          );
        }

        final city = internationalMatches[index - matches.length];
        return ListTile(
          leading: Icon(AppIcons.globe, color: colors.onSurfaceVariant),
          title: Text(city),
          trailing: Icon(
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
    final displayedCities = _isExpanded
        ? ChinaCities.hotCities
        : ChinaCities.hotCities.take(17).toList();

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
                    color: AppBrandColors.infoBlue,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      AppIcons.location_on,
                      size: 14,
                      color: AppBrandColors.infoBlue,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        hasLoc ? '定位: $_locatedCity' : '定位城市',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppBrandColors.infoBlue,
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
                  ? AppBrandColors
                        .infoBlue // 选中城市文字变蓝 (参照截图)
                  : (isDark ? colors.onSurface : AppBrandColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
