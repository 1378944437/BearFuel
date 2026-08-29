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

  List<RefuelRecordModel> get records => _records;
  FuelCalculationSummary get summary => _summary;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 获取最新一条记录的总里程（用于记账时作为基准里程校验与提示）
  double get latestMileage {
    if (_records.isEmpty) return 0.0;
    return _records.fold(
      0.0,
      (maximum, record) => record.mileage > maximum ? record.mileage : maximum,
    );
  }

  /// 获取最近使用的加油标号
  String? get latestFuelType {
    if (_records.isEmpty) return null;
    return _records.last.fuelType;
  }

  /// 获取最近使用的单价
  double? get latestUnitPrice {
    if (_records.isEmpty) return null;
    return _records.last.unitPrice;
  }

  /// 获取最近使用的加油站
  String? get latestGasStation {
    if (_records.isEmpty) return null;
    return _records.last.gasStation;
  }

  /// 根据车辆 ID 加载加油记录并执行小熊油耗算法计算
  Future<void> loadRecords(String vehicleId) async {
    final requestId = ++_loadRequestId;
    _currentVehicleId = vehicleId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawList = await _db.getRefuelRecords(vehicleId);
      if (requestId != _loadRequestId || _currentVehicleId != vehicleId) return;
      // 使用小熊油耗算法重新计算所有记录的百公里油耗
      _records = FuelCalculator.computeRecords(rawList);
      // 汇总综合统计数据
      _summary = FuelCalculator.calculateSummary(_records);

      // 异步回写计算后的油耗字段到数据库
      await _db.batchUpdateRefuelCalculations(_records);

      if (requestId != _loadRequestId || _currentVehicleId != vehicleId) return;

      AppConfig.log(
        '已加载车辆($vehicleId)的 ${_records.length} 条加油记录，计算有效次数: ${_summary.validCalculatedCount}',
      );
    } catch (e) {
      AppConfig.log('加载加油记录失败: $e');
      if (requestId == _loadRequestId && _currentVehicleId == vehicleId) {
        _errorMessage = '加油记录加载失败，请检查本地数据后重试';
      }
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
  /// 返回 null 表示导入失败；成功时返回新增/跳过重复的统计。
  Future<BatchImportStats?> importBearFuelRecords(
    List<RefuelRecordModel> importedRecords, {
    bool overwrite = false,
  }) async {
    if (_currentVehicleId == null || importedRecords.isEmpty) return null;

    _isLoading = true;
    notifyListeners();

    try {
      if (overwrite) {
        await _db.replaceVehicleRefuelRecords(
          _currentVehicleId!,
          importedRecords,
        );
        await loadRecords(_currentVehicleId!);
        return BatchImportStats(
          inserted: importedRecords.length,
          skippedDuplicates: 0,
        );
      }
      final stats = await _db.batchInsertRefuelRecords(importedRecords);
      await loadRecords(_currentVehicleId!);
      return stats;
    } catch (e) {
      AppConfig.log('导入小熊油耗记录失败: $e');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// 导出当前车辆的加油记录为小熊油耗兼容 CSV
  String exportCsvData() {
    return _records.isEmpty ? '' : BearFuelImporter.exportToCsv(_records);
  }
}
