import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/input_formatters.dart';

/// 中国机动车号牌专用录入组件
/// 结构解耦：[省份简称 1字] + [发牌城市字母 1字] + [号牌代码 5位/6位]
/// 位数只计算除开省份简称、市字母简称之外的代码部分
class LicensePlateInputField extends StatefulWidget {
  final String? initialPlate;
  final ValueChanged<String> onChanged;

  const LicensePlateInputField({
    super.key,
    this.initialPlate,
    required this.onChanged,
  });

  @override
  State<LicensePlateInputField> createState() => _LicensePlateInputFieldState();
}

class _LicensePlateInputFieldState extends State<LicensePlateInputField> {
  // 全国 31 个省份/直辖市/自治区简称
  static const List<String> _provinces = [
    '鄂',
    '京',
    '沪',
    '粤',
    '津',
    '渝',
    '冀',
    '豫',
    '云',
    '辽',
    '黑',
    '湘',
    '皖',
    '鲁',
    '新',
    '苏',
    '浙',
    '赣',
    '桂',
    '甘',
    '晋',
    '蒙',
    '陕',
    '吉',
    '闽',
    '贵',
    '青',
    '藏',
    '川',
    '宁',
    '琼',
    '使',
    '领',
    '港',
    '澳'
  ];

  // 常见城市发牌代号 A-Z
  static const List<String> _cityLetters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'J',
    'K',
    'L',
    'M',
    'N',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z'
  ];

  late String _selectedProvince;
  late String _selectedCityLetter;
  late TextEditingController _codeController;
  bool _isNewEnergy = false;

  @override
  void initState() {
    super.initState();
    _parseInitialPlate(widget.initialPlate);
  }

  void _parseInitialPlate(String? plate) {
    _selectedProvince = '鄂';
    _selectedCityLetter = 'A';
    String code = '';

    if (plate != null && plate.trim().isNotEmpty) {
      final clean = plate
          .trim()
          .replaceAll('·', '')
          .replaceAll('-', '')
          .replaceAll(' ', '')
          .toUpperCase();
      if (clean.isNotEmpty) {
        // 提取省份
        if (_provinces.contains(clean.substring(0, 1))) {
          _selectedProvince = clean.substring(0, 1);
          if (clean.length > 1) {
            final secondChar = clean.substring(1, 2);
            if (RegExp(r'[A-Z]').hasMatch(secondChar)) {
              _selectedCityLetter = secondChar;
              if (clean.length > 2) {
                code = clean.substring(2);
              }
            } else {
              code = clean.substring(1);
            }
          }
        } else if (clean.isNotEmpty &&
            RegExp(r'[A-Z]').hasMatch(clean.substring(0, 1))) {
          _selectedCityLetter = clean.substring(0, 1);
          if (clean.length > 1) {
            code = clean.substring(1);
          }
        } else {
          code = clean;
        }
      }
    }

    _isNewEnergy = code.length >= 6;
    _codeController = TextEditingController(text: code);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _notifyChange() {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      widget.onChanged('');
    } else {
      widget.onChanged('$_selectedProvince$_selectedCityLetter·$code');
    }
  }

  /// 弹出省份简称选择器底抽屉
  void _showProvincePicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择发牌省份/直辖市简称',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(AppIcons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _provinces.map((prov) {
                  final isSel = prov == _selectedProvince;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedProvince = prov);
                      _notifyChange();
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFFFF5A24)
                            : (isDark ? Colors.white10 : Colors.grey[100]),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSel
                              ? const Color(0xFFFF5A24)
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        prov,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isSel
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 弹出城市字母简称选择器底抽屉
  void _showCityLetterPicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '选择【$_selectedProvince】地市发牌字母代号',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(AppIcons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _cityLetters.map((letter) {
                  final isSel = letter == _selectedCityLetter;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedCityLetter = letter);
                      _notifyChange();
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFF1E88E5)
                            : (isDark ? Colors.white10 : Colors.grey[100]),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSel
                              ? const Color(0xFF1E88E5)
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isSel
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final code = _codeController.text.trim().toUpperCase();
    final maxCodeDigits = _isNewEnergy ? 6 : 5;
    final currentCodeDigits = code.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部模式切换与车牌仿真徽章（位置直接放于“机动车牌照”后方，默认以 京A 88888 展示）
        Row(
          children: [
            const Text(
              '机动车牌照',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),

            // 车牌图片模拟（默认以 京A 88888 / 新能源 京A D12345 展示，有输入时实时动态更新）
            _buildInlineSimulationBadge(code),

            const Spacer(),
            Text(
              _isNewEnergy ? '新能源' : '燃油车',
              style: TextStyle(
                fontSize: 11,
                color:
                    _isNewEnergy ? Colors.green[700] : const Color(0xFF1E88E5),
                fontWeight: FontWeight.bold,
              ),
            ),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: _isNewEnergy,
                activeThumbColor: Colors.green,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _isNewEnergy = val;
                    // 如果从新能源切回燃油车且超过5位，自动截断
                    if (!_isNewEnergy && _codeController.text.length > 5) {
                      _codeController.text =
                          _codeController.text.substring(0, 5);
                    }
                  });
                  _notifyChange();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // 三段式组合输入区域：[省份简称] + [市字母简称] + [代码序号]
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. 省份简称点选按钮
            InkWell(
              onTap: _showProvincePicker,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 52,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5A24).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFFF5A24).withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _selectedProvince,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF5A24),
                      ),
                    ),
                    const Icon(AppIcons.arrow_drop_down,
                        size: 14, color: Color(0xFFFF5A24)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),

            // 2. 地市发牌字母代号点选按钮
            InkWell(
              onTap: _showCityLetterPicker,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _selectedCityLetter,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E88E5),
                      ),
                    ),
                    const Icon(AppIcons.arrow_drop_down,
                        size: 14, color: Color(0xFF1E88E5)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 3. 号牌代码输入框（位数严格限制为 5 位或 6 位，计数器只算代码部分）
            Expanded(
              child: SizedBox(
                height: 44,
                child: TextFormField(
                  controller: _codeController,
                  maxLength: maxCodeDigits,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    UpperCaseTextFormatter(),
                    LengthLimitingTextInputFormatter(maxCodeDigits),
                  ],
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5),
                  decoration: InputDecoration(
                    counterText: '', // 隐藏默认的下置计数器，使用右侧紧凑徽章
                    hintText: _isNewEnergy
                        ? '新能源代码 (6位，如 D12345)'
                        : '号牌代码 (5位，如 88888)',
                    hintStyle: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                        letterSpacing: 0),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 位数专属徽章：只计算代码位数
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: currentCodeDigits == maxCodeDigits
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$currentCodeDigits/$maxCodeDigits位',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: currentCodeDigits == maxCodeDigits
                                  ? Colors.green[800]
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (code.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _codeController.clear();
                              _notifyChange();
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(AppIcons.cancel,
                                  size: 16, color: colors.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                  onChanged: (v) {
                    setState(() {});
                    _notifyChange();
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 紧凑仿真车牌微质感徽章（默认以 京A 88888 / 京A D12345 展示，实时联动）
  Widget _buildInlineSimulationBadge(String code) {
    final displayProvince = code.isNotEmpty ? _selectedProvince : '京';
    final displayCityLetter = code.isNotEmpty ? _selectedCityLetter : 'A';
    final displayCode =
        code.isNotEmpty ? code : (_isNewEnergy ? 'D12345' : '88888');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: _isNewEnergy
            ? const LinearGradient(
                colors: [
                  Color(0xFFE8F5E9),
                  Color(0xFFA5D6A7),
                  Color(0xFF43A047)
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [
                  Color(0xFF1E88E5),
                  Color(0xFF1565C0),
                  Color(0xFF0D47A1)
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _isNewEnergy ? const Color(0xFF2E7D32) : Colors.white,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$displayProvince$displayCityLetter $displayCode',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: _isNewEnergy ? Colors.black87 : Colors.white,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
