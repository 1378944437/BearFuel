import 'package:bearfuel/core/theme/app_icons.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/vehicle_model.dart';
import '../../data/models/refuel_record_model.dart';
import '../../data/models/expense_record_model.dart';
import '../../domain/fuel_calculator.dart';
import '../../domain/statistics_service.dart';
import '../../domain/pdf_report_generator.dart';
import '../../core/utils/date_formatter.dart';

/// 报表导出与战报分享中心弹窗
class ReportShareCardDialog extends StatefulWidget {
  final VehicleModel vehicle;
  final List<RefuelRecordModel> records;
  final List<ExpenseRecordModel> expenses;
  final FuelCalculationSummary summary;
  final double totalOtherExpense;

  const ReportShareCardDialog({
    super.key,
    required this.vehicle,
    required this.records,
    required this.expenses,
    required this.summary,
    required this.totalOtherExpense,
  });

  @override
  State<ReportShareCardDialog> createState() => _ReportShareCardDialogState();
}

class _ReportShareCardDialogState extends State<ReportShareCardDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey _a4ReportKey = GlobalKey();
  final GlobalKey _socialCardKey = GlobalKey();
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 捕获指定 GlobalKey 渲染区域的高清图片字节流
  Future<Uint8List?> _captureWidgetToPng(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('截取图片失败: $e');
      return null;
    }
  }

  /// 导出并分享标准 A4 PDF 审计报告
  Future<void> _exportPdfReport() async {
    setState(() => _isGenerating = true);
    HapticFeedback.mediumImpact();

    try {
      final bytes = await _captureWidgetToPng(_a4ReportKey);
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('报告渲染异常，请重试'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final fileName =
          '${widget.vehicle.name}_全寿命成本审计报告_${DateFormatter.formatYmd(DateTime.now())}.pdf';
      final pdfFile = await PdfReportGenerator.generatePdfFromImage(
        imageBytes: bytes,
        fileName: fileName,
      );

      if (mounted) {
        await Share.shareXFiles(
          [XFile(pdfFile.path, mimeType: 'application/pdf')],
          text: '【${widget.vehicle.name}】全寿命用车成本审计报告 (PDF)',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出 PDF 失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  /// 导出并分享高清战报长图 (PNG)
  Future<void> _shareSocialCard() async {
    setState(() => _isGenerating = true);
    HapticFeedback.mediumImpact();

    try {
      final bytes = await _captureWidgetToPng(_socialCardKey);
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('战报渲染异常，请重试'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName =
          '${widget.vehicle.name}_用车战报_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png')],
          text:
              '这是我的爱车【${widget.vehicle.name}】百公里实测油耗 ${widget.summary.averageConsumption.toStringAsFixed(2)}L！',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享战报失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700, maxWidth: 440),
        child: Column(
          children: [
            // 1. 弹窗标题与 Tab 栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(AppIcons.assessment_outlined,
                          color: Color(0xFFFF5A24), size: 20),
                      SizedBox(width: 6),
                      Text('报表导出与战报分享',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(AppIcons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 38,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFFFF5A24),
                  borderRadius: BorderRadius.circular(8),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: colors.onSurfaceVariant,
                labelStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: 'PDF 审计报告'),
                  Tab(text: '社交战报长图'),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // 2. 预览区域
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: PDF 审计报告预览 (A4 格式)
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: RepaintBoundary(
                      key: _a4ReportKey,
                      child: _buildA4ReportPreview(),
                    ),
                  ),

                  // Tab 2: 社交战报长图预览
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: RepaintBoundary(
                      key: _socialCardKey,
                      child: _buildSocialCardPreview(),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 3. 底部导出操作按钮
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isGenerating ? null : _exportPdfReport,
                      icon: const Icon(AppIcons.picture_as_pdf,
                          size: 18, color: Colors.redAccent),
                      label: const Text('导出 PDF 报告',
                          style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _shareSocialCard,
                      icon: const Icon(AppIcons.share, size: 18),
                      label:
                          const Text('分享高清战报', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5A24),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // A4 全寿命成本审计报告视图
  // ===========================================================================
  Widget _buildA4ReportPreview() {
    final totalAllCost =
        widget.summary.totalFuelCost + widget.totalOtherExpense;
    final totalDistance = widget.summary.totalValidDistance;
    final costPerKmTotal =
        totalDistance > 0 ? (totalAllCost / totalDistance) : 0.0;
    final shares = StatisticsService.getExpenseStructure(
      refuelRecords: widget.records,
      expenseRecords: widget.expenses,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 报告表头
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '车辆全寿命用车成本审计报告',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'VEHICLE LIFECYCLE COST & ENERGY AUDIT',
                    style: TextStyle(
                        fontSize: 8,
                        color: Colors.grey[600],
                        letterSpacing: 0.5),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('BearFuel 官方认证',
                    style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFF1A237E),
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '生成时间: ${DateFormatter.formatChineseYmd(DateTime.now())} · 车辆标识: ${widget.vehicle.plateNumber != null && widget.vehicle.plateNumber!.isNotEmpty ? widget.vehicle.plateNumber! : widget.vehicle.name}',
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
          const Divider(height: 16),

          // 1. 车辆基本档案
          _buildSectionHeader('一、 车辆基本档案 (Vehicle Profile)'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                _buildInfoCell('车型名称', widget.vehicle.name),
                _buildInfoCell('车牌号码', widget.vehicle.plateNumber ?? '未登记'),
                _buildInfoCell('推荐油品', widget.vehicle.defaultFuelType),
                _buildInfoCell('油箱容积',
                    '${widget.vehicle.tankCapacity.toStringAsFixed(0)} L'),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. 核心审计 KPI
          _buildSectionHeader('二、 核心审计指标 (Key Audit Metrics)'),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildKpiCard('全车累计总花费', '¥ ${totalAllCost.toStringAsFixed(0)}',
                  '油费 + 维保其他', const Color(0xFF1A237E)),
              const SizedBox(width: 6),
              _buildKpiCard(
                  '实测综合百公里油耗',
                  '${widget.summary.averageConsumption.toStringAsFixed(2)} L',
                  '小熊算法平摊',
                  const Color(0xFFFF5A24)),
              const SizedBox(width: 6),
              _buildKpiCard('综合每公里成本', '¥ ${costPerKmTotal.toStringAsFixed(2)}',
                  '全口径每公里开销', const Color(0xFF00897B)),
            ],
          ),

          const SizedBox(height: 12),

          // 3. 用车成本结构分布
          _buildSectionHeader('三、 用车成本结构明细 (Expense Breakdown)'),
          const SizedBox(height: 6),
          Table(
            border: TableBorder.all(
                color: Colors.grey.withValues(alpha: 0.2), width: 0.5),
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(2.5),
              2: FlexColumnWidth(2.5),
            },
            children: [
              TableRow(
                decoration:
                    BoxDecoration(color: Colors.grey.withValues(alpha: 0.08)),
                children: const [
                  Padding(
                      padding: EdgeInsets.all(4),
                      child: Text('费用类别',
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(4),
                      child: Text('金额 (元)',
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(4),
                      child: Text('占比 (%)',
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.bold))),
                ],
              ),
              TableRow(
                children: [
                  const Padding(
                      padding: EdgeInsets.all(4),
                      child: Text('燃油加油支出', style: TextStyle(fontSize: 9))),
                  Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                          '¥${widget.summary.totalFuelCost.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 9))),
                  Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                          '${totalAllCost > 0 ? ((widget.summary.totalFuelCost / totalAllCost) * 100).toStringAsFixed(1) : "0.0"}%',
                          style: const TextStyle(fontSize: 9))),
                ],
              ),
              ...shares.take(4).map((s) => TableRow(
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(s.category,
                              style: const TextStyle(fontSize: 9))),
                      Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text('¥${s.totalAmount.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 9))),
                      Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text('${s.percentage}%',
                              style: const TextStyle(fontSize: 9))),
                    ],
                  )),
            ],
          ),

          const SizedBox(height: 12),

          // 4. 维保履历与重要事项
          _buildSectionHeader('四、 维保履历与重要事项清单 (Maintenance History)'),
          const SizedBox(height: 6),
          if (widget.expenses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('暂无维保与杂费明细记录',
                  style: TextStyle(fontSize: 9, color: Colors.grey)),
            )
          else
            Column(
              children: widget.expenses.take(3).map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          '• ${DateFormatter.formatYmd(e.expenseDate)} [${e.category}]',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.black87)),
                      Text('¥${e.amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E))),
                    ],
                  ),
                );
              }).toList(),
            ),

          const Divider(height: 14),

          // 报告尾部签章声明
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('BearFuel 算法计算中心 · 审计专用',
                  style: TextStyle(fontSize: 8, color: Colors.grey[500])),
              Text(
                  '防伪校验码: BF-${DateTime.now().millisecondsSinceEpoch % 1000000}',
                  style: TextStyle(fontSize: 8, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 社交战报长图视图 (微信朋友圈 / 小红书战报风格)
  // ===========================================================================
  Widget _buildSocialCardPreview() {
    final totalAllCost =
        widget.summary.totalFuelCost + widget.totalOtherExpense;
    final totalDistance = widget.summary.totalValidDistance;
    final costPerKmTotal =
        totalDistance > 0 ? (totalAllCost / totalDistance) : 0.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFFFF5A24)],
          stops: [0.0, 0.65, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 顶部 Logo 与战报标题
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(AppIcons.local_gas_station,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'BearFuel',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${DateTime.now().year} 用车战报',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 爱车名字
          Text(
            widget.vehicle.name,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            '累计行驶 ${totalDistance.toStringAsFixed(0)} km · 记录 ${widget.records.length} 笔加油',
            style: TextStyle(
                fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
          ),

          const SizedBox(height: 16),

          // 核心成就主徽章
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text('实测综合百公里油耗',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      widget.summary.averageConsumption.toStringAsFixed(2),
                      style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF5A24)),
                    ),
                    const SizedBox(width: 4),
                    const Text('L/100km',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.military_tech,
                          color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text('暂无全国同款车对比数据',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 四大衍生数据卡片
          Row(
            children: [
              _buildSocialMiniCard(
                  '每公里燃油花费',
                  '¥ ${widget.summary.averageCostPerKm.toStringAsFixed(2)}',
                  '燃油成本',
                  Colors.white),
              const SizedBox(width: 8),
              _buildSocialMiniCard(
                  '综合每公里成本',
                  '¥ ${costPerKmTotal.toStringAsFixed(2)}',
                  '含维保其他',
                  Colors.white),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSocialMiniCard(
                  '累计总耗油量',
                  '${widget.summary.totalFuelAmount.toStringAsFixed(1)} L',
                  '已消耗油量',
                  Colors.white),
              const SizedBox(width: 8),
              _buildSocialMiniCard(
                  '全车累计总花费',
                  '¥ ${totalAllCost.toStringAsFixed(0)}',
                  '总用车支出',
                  Colors.white),
            ],
          ),

          const SizedBox(height: 14),

          // 底部水印与防伪说明
          Text(
            '扫描使用 BearFuel · 记录每一次真实出发',
            style: TextStyle(
                fontSize: 9, color: Colors.white.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
    );
  }

  Widget _buildInfoCell(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey)),
          const SizedBox(height: 1),
          Text(value,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
      String title, String value, String subtitle, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 8, color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(value,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            Text(subtitle,
                style: const TextStyle(fontSize: 7, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialMiniCard(
      String title, String value, String subtitle, Color textColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 9, color: textColor.withValues(alpha: 0.8))),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textColor)),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 8, color: textColor.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }
}
