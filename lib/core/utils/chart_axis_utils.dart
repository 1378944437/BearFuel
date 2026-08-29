import 'dart:math' as math;

/// 图表坐标轴刻度工具：统一生成"整洁"的刻度间隔与抽稀后的标签，
/// 避免横纵坐标标签拥挤或相互重叠。
class ChartAxisUtils {
  ChartAxisUtils._();

  /// 根据数值跨度计算不超过 [maxTicks] 个刻度的美观间隔
  /// (1-2-2.5-5-10 序列)。
  static double niceInterval(double span, {int maxTicks = 5}) {
    if (span <= 0 || span.isNaN || span.isInfinite) {
      return 1.0;
    }
    final raw = span / maxTicks;
    final magnitude = math
        .pow(10.0, (math.log(raw) / math.ln10).floorToDouble())
        .toDouble();
    final normalized = raw / magnitude; // 归一化到 1..10
    double nice;
    if (normalized <= 1) {
      nice = 1;
    } else if (normalized <= 2) {
      nice = 2;
    } else if (normalized <= 2.5) {
      nice = 2.5;
    } else if (normalized <= 5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  /// X 轴标签抽稀步长：数据点多时最多显示约 6 个标签。
  static int xLabelStep(int count) {
    if (count <= 6) return 1;
    return (count / 6).ceil();
  }

  /// 判断第 [index] 个 X 轴标签是否显示。
  /// 常规标签按 [step] 抽稀；末尾标签仅在距上一个已显示标签
  /// 超过步长一半时才补充，避免与前一个标签重叠。
  static bool shouldShowXLabel(int index, int count, int step) {
    if (index < 0 || index >= count) return false;
    if (index % step == 0) return true;
    if (index == count - 1) return index % step * 2 > step;
    return false;
  }

  /// 按刻度间隔大小选择小数位，避免冗长小数导致纵轴标签过宽。
  static String formatAxisValue(double value, double interval) {
    final decimals = interval >= 1
        ? 0
        : interval >= 0.1
        ? 1
        : 2;
    return value.toStringAsFixed(decimals);
  }
}
