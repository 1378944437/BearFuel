import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 左滑卡片全局协调器：同一时间只允许一张卡片处于滑开状态，
/// 并支持在滚动开始或点击其他区域时统一收起。
class SwipeActionController {
  SwipeActionCardState? _openCard;

  /// 请求滑开 [card]，同时收起当前已滑开的其他卡片
  void opened(SwipeActionCardState card) {
    if (_openCard == card) return;
    _openCard?._collapse();
    _openCard = card;
  }

  /// 通知 [card] 已收起，解除登记
  void closed(SwipeActionCardState card) {
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

/// 高性能单向左滑卡片：左滑调出"编辑/删除"操作抽屉，无右滑。
///
/// [canDelete] 为 false 时抽屉仅显示"编辑"（内置/受保护项用）。
/// Transform 必须在 GestureDetector 外层：命中区域才会跟随卡片平移，
/// 否则未平移的整行命中框会吞掉右侧"编辑/删除"按钮的点击。
class SwipeActionCard extends StatefulWidget {
  final SwipeActionController? controller;
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  final VoidCallback? onOperated;
  final bool canDelete;
  final BorderRadius cardRadius;

  const SwipeActionCard({
    super.key,
    this.controller,
    required this.child,
    required this.onEdit,
    required this.onDelete,
    this.onTap,
    this.onOperated,
    this.canDelete = true,
    this.cardRadius = const BorderRadius.horizontal(left: Radius.circular(12)),
  });

  @override
  State<SwipeActionCard> createState() => SwipeActionCardState();
}

class SwipeActionCardState extends State<SwipeActionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  static const double _actionWidth = 140.0; // 编辑70 + 删除70

  double get _maxActionWidth => widget.canDelete ? _actionWidth : 70.0;

  SwipeActionController? get swipeController => widget.controller;

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
    swipeController?.closed(this);
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
    return Stack(
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
                    swipeController?.closed(this);
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
                if (widget.canDelete)
                  InkWell(
                    onTap: () {
                      swipeController?.closed(this);
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
        Transform.translate(
          offset: Offset(_dragOffset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              setState(() {
                _dragOffset += details.primaryDelta ?? 0;
                // 仅允许左滑（负偏移），禁止右滑（最大为 0.0）
                _dragOffset = _dragOffset.clamp(-_maxActionWidth, 0.0);
              });
            },
            onHorizontalDragEnd: (details) {
              if (_dragOffset < -45) {
                // 左滑超过阈值：露出右侧编辑与删除抽屉，并收起其他已滑开的卡片
                HapticFeedback.lightImpact();
                widget.onOperated?.call();
                swipeController?.opened(this);
                _animateTo(-_maxActionWidth);
              } else {
                swipeController?.closed(this);
                _resetPosition();
              }
            },
            onTap: () {
              if (_dragOffset != 0) {
                // 已滑开时点击卡片任意位置收回
                swipeController?.closed(this);
                _resetPosition();
              } else {
                widget.onTap?.call();
              }
            },
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                // 右侧直角：滑动时与抽屉保持平直拼缝，整体圆角由外层容器裁剪
                borderRadius: widget.cardRadius,
              ),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}
