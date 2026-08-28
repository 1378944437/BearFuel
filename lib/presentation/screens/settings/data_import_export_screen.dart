import 'package:bearfuel/core/theme/app_icons.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../domain/bear_fuel_importer.dart';
import '../../../data/database/database_helper.dart';
import '../../../providers/vehicle_provider.dart';
import '../../../providers/refuel_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../widgets/custom_card.dart';

/// 小熊油耗全格式导入、CSV 导出与本地全库数据安全备份中心
class DataImportExportScreen extends StatefulWidget {
  const DataImportExportScreen({super.key});

  @override
  State<DataImportExportScreen> createState() => _DataImportExportScreenState();
}

class _DataImportExportScreenState extends State<DataImportExportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _overwriteExisting = false;
  ImportResult? _previewResult;
  bool _isImporting = false;
  String? _selectedFileName;
  int? _selectedFileSize;

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

  /// 打开系统文件选择器，直接选取手机本地的 CSV / XLS / XLSX / TXT 原始文件
  Future<void> _pickCsvFile() async {
    final vehicleProv = context.read<VehicleProvider>();
    final currentVehicle = vehicleProv.currentVehicle;

    if (currentVehicle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一辆爱车以导入数据')),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xls', 'xlsx', 'tsv', 'json'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedFileName = file.name;
          _selectedFileSize = file.size;
        });

        List<int> bytes;
        if (file.bytes != null) {
          bytes = file.bytes!;
        } else if (file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('读取所选文件失败')),
          );
          return;
        }

        // 检查是否为全量 JSON 备份
        if (file.name.toLowerCase().endsWith('.json')) {
          try {
            final jsonStr = utf8.decode(bytes);
            final map = json.decode(jsonStr) as Map<String, dynamic>;
            if (map.containsKey('vehicles') &&
                map.containsKey('refuel_records')) {
              await _restoreJsonBackup(map);
              return;
            }
          } catch (_) {}
        }

        final parsed = BearFuelImporter.parseBytes(bytes, currentVehicle.id);
        setState(() {
          _previewResult = parsed;
        });

        if (parsed.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '成功解析 $_selectedFileName，读取到 ${parsed.validCount} 条记录'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('文件解析警告: ${parsed.errorMessage}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件选择异常: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 恢复全量 JSON 备份
  Future<void> _restoreJsonBackup(Map<String, dynamic> backupMap) async {
    bool validList(String key) {
      final value = backupMap[key];
      return value is List && value.every((item) => item is Map);
    }

    final requiredKeys = ['vehicles', 'refuel_records'];
    final optionalKeys = ['expense_records', 'weather_snapshots'];
    final hasInvalidData = [
      ...requiredKeys,
      ...optionalKeys.where(backupMap.containsKey),
    ].any((key) => !validList(key));
    if (hasInvalidData) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('备份文件结构不完整或包含无效数据，未执行恢复'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复全量账本备份'),
        content: const Text('检测到 BearFuel 全量备份文件，导入将覆盖合并当前车辆与历史所有流水记录。确定继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5A24)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await DatabaseHelper().restoreFullBackupData(backupMap);
      if (success && mounted) {
        final vehicleProv = context.read<VehicleProvider>();
        await vehicleProv.loadVehicles();
        if (vehicleProv.currentVehicle != null && mounted) {
          final vId = vehicleProv.currentVehicle!.id;
          final refuelProv = context.read<RefuelProvider>();
          await refuelProv.loadRecords(vId);
          await context.read<ExpenseProvider>().loadExpenses(
                vId,
                currentMaxMileage: refuelProv.latestMileage,
              );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('全量账本与车辆数据已成功恢复！'),
                backgroundColor: Colors.green),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('备份恢复失败，当前数据未完成恢复，请检查备份文件'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 执行一键导入入库
  Future<void> _executeImport() async {
    if (_previewResult == null || !_previewResult!.success) return;

    final refuelProv = context.read<RefuelProvider>();
    setState(() => _isImporting = true);

    try {
      final success = await refuelProv.importBearFuelRecords(
        _previewResult!.parsedRecords,
        overwrite: _overwriteExisting,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功导入 ${_previewResult!.validCount} 笔加油数据，已生成油耗走势'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('数据写入失败，请检查数据完整性'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入异常: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// 导出为 CSV 文件并调起系统分享（嵌入 UTF-8 BOM 彻底规避 Excel / WPS 中文乱码）
  Future<void> _exportAndShareCsv(String csvContent, String carName) async {
    try {
      HapticFeedback.mediumImpact();
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName =
          'BearFuel_${carName}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
      final filePath = '${tempDir.path}/$fileName';

      final file = File(filePath);
      // 写入 UTF-8 BOM 头: [0xEF, 0xBB, 0xBF]
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csvContent)];
      await file.writeAsBytes(bytes);

      final xfile = XFile(filePath, mimeType: 'text/csv', name: fileName);
      await Share.shareXFiles(
        [xfile],
        subject: 'BearFuel 账本数据导出 ($carName)',
        text: '来自 BearFuel 的标准小熊油耗 CSV 数据备份文件。',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出分享失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 导出全库 JSON 备份并调起系统分享
  Future<void> _exportFullBackupJson() async {
    try {
      HapticFeedback.mediumImpact();
      final data = await DatabaseHelper().exportFullBackupData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName =
          'BearFuel_全量备份_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
      final filePath = '${tempDir.path}/$fileName';

      final file = File(filePath);
      await file.writeAsString(jsonStr, encoding: utf8);

      final xfile =
          XFile(filePath, mimeType: 'application/json', name: fileName);
      await Share.shareXFiles(
        [xfile],
        subject: 'BearFuel 全量账本数据库备份',
        text: '包含全部爱车档案、加油明细与其它费用的完整备份文件。',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出备份失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final vehicleProv = context.watch<VehicleProvider>();
    final currentVehicle = vehicleProv.currentVehicle;
    final carName = currentVehicle?.name ?? '爱车';

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据导入与备份中心'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF5A24),
          labelColor: const Color(0xFFFF5A24),
          unselectedLabelColor: colors.onSurfaceVariant,
          tabs: const [
            Tab(
                icon: Icon(AppIcons.file_download_outlined, size: 20),
                text: '导入数据'),
            Tab(
                icon: Icon(AppIcons.file_upload_outlined, size: 20),
                text: '导出与备份'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildImportView(carName),
          _buildExportView(carName),
        ],
      ),
    );
  }

  /// 导入视图
  Widget _buildImportView(String carName) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CustomCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(AppIcons.directions_car,
                      color: Color(0xFFFF5A24), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '当前目标爱车: $carName',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '支持直接导入小熊油耗官方导出的.XLS表格',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 选择文件卡片
        CustomCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择本地表格或备份文件',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _pickCsvFile,
                icon: const Icon(AppIcons.folder_open),
                label: const Text('选择本地 XLS 文件'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  backgroundColor: const Color(0xFF1E88E5),
                  foregroundColor: Colors.white,
                ),
              ),
              if (_selectedFileName != null) ...[
                const SizedBox(height: 8),
                Text(
                  '已选文件: $_selectedFileName (${(_selectedFileSize ?? 0) ~/ 1024} KB)',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 覆盖/追加 开关
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('覆盖导入目标车辆已有记录'),
          subtitle: const Text('开启后将清空当前爱车原先记录，关闭则追加在末尾',
              style: TextStyle(fontSize: 12)),
          activeThumbColor: const Color(0xFFFF5A24),
          value: _overwriteExisting,
          onChanged: (val) => setState(() => _overwriteExisting = val),
        ),
        const SizedBox(height: 12),

        // 解析预览报告
        if (_previewResult != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _previewResult!.success
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    _previewResult!.success ? Colors.green : Colors.redAccent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _previewResult!.success
                          ? AppIcons.check_circle
                          : AppIcons.error,
                      color:
                          _previewResult!.success ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _previewResult!.success ? '解析就绪：' : '解析失败：',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _previewResult!.success
                            ? Colors.green[900]
                            : Colors.red[900],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '提取 ${_previewResult!.validCount} 条加油记录 (跳过 ${_previewResult!.skippedCount} 行)',
                        style: TextStyle(
                          fontSize: 13,
                          color: _previewResult!.success
                              ? Colors.green[800]
                              : Colors.red[800],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_previewResult!.parsedRecords.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '时间跨度: ${_previewResult!.parsedRecords.first.refuelDate.toString().split(" ")[0]} ~ ${_previewResult!.parsedRecords.last.refuelDate.toString().split(" ")[0]}',
                    style:
                        TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                  Text(
                    '里程跨度: ${_previewResult!.parsedRecords.first.mileage} km ~ ${_previewResult!.parsedRecords.last.mileage} km',
                    style:
                        TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 确认导入大按钮
        ElevatedButton(
          onPressed: (_isImporting ||
                  _previewResult == null ||
                  !_previewResult!.success)
              ? null
              : _executeImport,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF5A24),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
          ),
          child: _isImporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('确认一键批量入库',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  /// 导出与备份视图
  Widget _buildExportView(String carName) {
    final colors = Theme.of(context).colorScheme;
    final refuelProv = context.watch<RefuelProvider>();
    final csvText = refuelProv.exportCsvData();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. 全量数据快照与安全备份卡片
        CustomCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(AppIcons.shield_outlined, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text('全量账本数据安全备份 (推荐)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '一键打包所有车辆档案、全部历史加油流水与开销明细，生成独立 JSON 备份文件，可在换机或重装时一键完整还原。',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _exportFullBackupJson,
                icon: const Icon(AppIcons.backup_outlined),
                label: const Text('导出全量账本备份并分享 / 保存'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. 单车 CSV 导出卡片
        CustomCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '导出当前爱车 ($carName) 为标准 CSV',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                '导出的数据包含日期、当前里程、加油量、单价、金额、加满状态、百公里油耗及油站名称，小熊油耗完全兼容。',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (csvText.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.center,
                  child: Text('当前爱车暂无加油记录可供导出',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                )
              else ...[
                ElevatedButton.icon(
                  onPressed: () => _exportAndShareCsv(csvText, carName),
                  icon: const Icon(AppIcons.share),
                  label: const Text('导出为 CSV 文件并分享 / 保存'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    backgroundColor: const Color(0xFFFF5A24),
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: csvText));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制完整 CSV 文本数据到剪贴板！'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(AppIcons.copy, size: 18),
                  label: const Text('复制 CSV 文本到剪贴板'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
