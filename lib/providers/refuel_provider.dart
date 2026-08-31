import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/refuel_record_model.dart';
import '../domain/fuel_calculator.dart';
import '../domain/bear_fuel_importer.dart';
import '../core/config/app_config.dart';

/// 加油记录与油耗计算状态管理 Provider
class RefuelProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  List<RefuelRecordModel> _records = [];
  FuelCalculationSummary _summary = const FuelCalculationSummary();
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentVehicleId;
  int _loadRequestId = 0;
  int _importOperationId = 0;

  List<RefuelRecordModel> get records => _records;
  FuelCalculationSummary get summary => _summary;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 当前表显：按最新有效加油时间记录读取 (P1-05)。
  double get latestMileage => latestMileageOf(_records);

  /// 历史最大表显（诊断值）。
  ///
  /// 与 [latestMileage] 分开提供：里程回拨或换表后两者会出现差异，
  /// 该值可用于保养提醒等仍需"历史最高读数"的场景与数据诊断。
  double get maxMileage => maxMileageOf(_records);

  /// [latestMileage] 的纯函数实现：非法日期记录不参与当前表显。
  static double latestMileageOf(List<RefuelRecordModel> records) =>
      latestRecordOf(records)?.mileage ?? 0.0;

  /// 从全量记录中选出最新有效日期的记录。
  static RefuelRecordModel? latestRecordOf(List<RefuelRecordModel> records) {
    RefuelRecordModel? latest;
    for (final record in records) {
      if (record.hasInvalidDate) continue;
      if (latest == null ||
          record.refuelDate.isAfter(latest.refuelDate) ||
          record.refuelDate.isAtSameMomentAs(latest.refuelDate)) {
        latest = record;
      }
    }
    return latest;
  }

  /// 最近有效记录的油品、单价和加油站也使用同一时间口径。
  RefuelRecordModel? get latestRecord => latestRecordOf(_records);

  /// [maxMileage] 的纯函数实现：全部有效记录中的最大表显。
  static double maxMileageOf(List<RefuelRecordModel> records) {
    if (records.isEmpty) return 0.0;
    return records.fold(
      0.0,
      (maximum, record) => record.mileage > maximum ? record.mileage : maximum,
    );
  }

  /// 获取最近使用的加油标号
  String? get latestFuelType => latestRecord?.fuelType;

  /// 获取最近使用的单价
  double? get latestUnitPrice => latestRecord?.unitPrice;

  /// 获取最近使用的加油站
  String? get latestGasStation => latestRecord?.gasStation;

  /// 根据车辆 ID 加载加油记录并执行小熊油耗算法计算。
  ///
  /// 返回是否完整成功（P2-19）：数据库读取、重算或回写任一环节失败时
  /// 返回 false 并设置 [errorMessage]，调用方（尤其是导入流程）不得把
  /// 这种情况当作导入成功。
  Future<bool> loadRecords(String vehicleId) async {
    final requestId = ++_loadRequestId;
    _currentVehicleId = vehicleId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawList = await _db.getRefuelRecords(vehicleId);
      if (requestId != _loadRequestId || _currentVehicleId != vehicleId) {
        return false;
      }
      // 使用小熊油耗算法重新计算所有记录的百公里油耗
      _records = FuelCalculator.computeRecords(rawList);
      // 汇总综合统计数据
      _summary = FuelCalculator.calculateSummary(_records);

      // P2-20：回写派生字段前再次确认本次加载仍然有效，
      // 避免旧请求的并发回写覆盖新一次加载的计算结果。
      if (requestId != _loadRequestId || _currentVehicleId != vehicleId) {
        return false;
      }
      await _db.batchUpdateRefuelCalculations(_records);

      if (requestId != _loadRequestId || _currentVehicleId != vehicleId) {
        return false;
      }

      AppConfig.log(
        '已加载车辆($vehicleId)的 ${_records.length} 条加油记录，计算有效次数: ${_summary.validCalculatedCount}',
      );
      return true;
    } catch (e) {
      AppConfig.log('加载加油记录失败: $e');
      if (requestId == _loadRequestId && _currentVehicleId == vehicleId) {
        _errorMessage = '加油记录加载失败，请检查本地数据后重试';
      }
      return false;
    } finally {
      if (requestId == _loadRequestId && _currentVehicleId == vehicleId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 清空内存中的记录状态（如当前车辆被删除后调用），
  /// 避免界面继续展示已不存在车辆的数据。
  void clear() {
    _loadRequestId++;
    _currentVehicleId = null;
    _records = [];
    _summary = const FuelCalculationSummary();
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// 新增加油记录
  Future<bool> addRecord(RefuelRecordModel record) async {
    try {
      await _db.insertRefuelRecord(record);
      if (_currentVehicleId != null) {
        await loadRecords(_currentVehicleId!);
      }
      return true;
    } catch (e) {
      AppConfig.log('新增加油记录失败: $e');
      return false;
    }
  }

  /// 更新加油记录
  Future<bool> updateRecord(RefuelRecordModel record) async {
    try {
      final count = await _db.updateRefuelRecord(record);
      if (count == 0) return false;
      if (_currentVehicleId != null) {
        await loadRecords(_currentVehicleId!);
      }
      return true;
    } catch (e) {
      AppConfig.log('更新加油记录失败: $e');
      return false;
    }
  }

  /// 删除加油记录
  Future<bool> deleteRecord(String recordId) async {
    try {
      final count = await _db.deleteRefuelRecord(recordId);
      if (count == 0) return false;
      if (_currentVehicleId != null) {
        await loadRecords(_currentVehicleId!);
      }
      return true;
    } catch (e) {
      AppConfig.log('删除加油记录失败: $e');
      return false;
    }
  }

  /// 批量导入小熊油耗数据（覆盖或追加）
  ///
  /// 返回 null 表示导入失败（P2-19）：数据库写入失败，或写入后的
  /// 重算/回写未完整成功时均视为失败，由界面提示用户，不得静默报成功。
  /// 成功时返回新增/跳过重复的统计。
  Future<BatchImportStats?> importBearFuelRecords(
    List<RefuelRecordModel> importedRecords, {
    bool overwrite = false,
  }) async {
    if (_currentVehicleId == null || importedRecords.isEmpty) return null;

    final targetVehicleId = _currentVehicleId!;
    final operationId = ++_importOperationId;
    if (importedRecords.any((r) => r.vehicleId != targetVehicleId)) {
      _errorMessage = '导入记录与当前车辆不一致，已拒绝写入';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    notifyListeners();

    try {
      BatchImportStats stats;
      if (overwrite) {
        await _db.replaceVehicleRefuelRecords(targetVehicleId, importedRecords);
        stats = BatchImportStats(
          inserted: importedRecords.length,
          skippedDuplicates: 0,
        );
      } else {
        stats = await _db.batchInsertRefuelRecords(importedRecords);
      }

      // 导入流程必须在重算和回写成功后才返回成功
      final recalcOk = await loadRecords(targetVehicleId);
      if (operationId != _importOperationId ||
          _currentVehicleId != targetVehicleId ||
          !recalcOk) {
        AppConfig.log('导入后重算未完成或操作已失效，本次导入不按成功处理');
        return null;
      }
      return stats;
    } catch (e) {
      AppConfig.log('导入小熊油耗记录失败: $e');
      if (operationId == _importOperationId &&
          _currentVehicleId == targetVehicleId) {
        _errorMessage = '导入失败，请检查数据完整性';
        _isLoading = false;
        notifyListeners();
      }
      return null;
    }
  }

  /// 导出当前车辆的加油记录为小熊油耗兼容 CSV
  String exportCsvData() {
    return _records.isEmpty ? '' : BearFuelImporter.exportToCsv(_records);
  }
}
