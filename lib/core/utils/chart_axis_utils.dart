import 'dart:math' as math;

import 'package:flutter/painting.dart';

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

  /// 按刻度间隔本身的小数位数确定显示位数（2.5 → 1 位，0.25 → 2 位），
  /// 避免"间隔 2.5 的网格在 7.5 处被印成 8"这类标错。
  static int decimalsForInterval(double interval) {
    var text = interval.toStringAsFixed(6);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'[.]$'), '');
    final dot = text.indexOf('.');
    return dot < 0 ? 0 : text.length - dot - 1;
  }

  /// 单位固有小数位：金额保留分，油耗保留 1 位，温度等由间隔决定。
  static int decimalsForUnit(String unit) {
    if (unit.contains('¥')) return 2;
    if (unit.contains('L/100km')) return 1;
    return 0;
  }

  /// 纵轴标签格式化：取"间隔小数位"与"单位小数位"的较大者，
  /// 并消除 "-0" 这类负零显示。
  static String formatAxisValue(double value, double interval, {String? unit}) {
    var decimals = decimalsForInterval(interval);
    if (unit != null) {
      decimals = decimals > decimalsForUnit(unit)
          ? decimals
          : decimalsForUnit(unit);
    }
    final text = value.toStringAsFixed(decimals);
    if (text.startsWith('-') && double.parse(text) == 0) {
      return text.substring(1);
    }
    return text;
  }

  /// 生成 [min, max] 内按 [interval] 对齐的全部刻度值。
  static List<double> yTicks(double min, double max, double interval) {
    if (interval <= 0) return [min, max];
    final epsilon = interval / 1e5;
    final start = (min / interval).floorToDouble() * interval;
    final ticks = <double>[];
    for (double v = start; v <= max + epsilon; v += interval) {
      if (v >= min - epsilon) {
        ticks.add(double.parse(v.toStringAsFixed(6)));
      }
    }
    return ticks.isEmpty ? [min, max] : ticks;
  }

  /// 依据实际刻度文本测量纵轴预留宽度，替代写死的 reservedSize。
  static double reservedSizeFor(
    Iterable<String> labels,
    TextStyle style, {
    double padding = 10,
  }) {
    final painter = TextPainter(textDirection: TextDirection.ltr);
    var maxWidth = 0.0;
    for (final label in labels) {
      painter.text = TextSpan(text: label, style: style);
      painter.layout();
      if (painter.width > maxWidth) {
        maxWidth = painter.width;
      }
    }
    painter.dispose();
    return maxWidth + padding;
  }
}
