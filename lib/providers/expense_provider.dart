import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/expense_record_model.dart';
import '../domain/statistics_service.dart';
import '../core/config/app_config.dart';

/// 车辆其他费用与保养提醒状态管理 Provider
class ExpenseProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  List<ExpenseRecordModel> _expenses = [];
  List<ReminderItem> _reminders = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentVehicleId;
  int _loadRequestId = 0;

  List<ExpenseRecordModel> get expenses => _expenses;
  List<ReminderItem> get reminders => _reminders;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 计算其他费用总金额
  double get totalExpenseAmount {
    return _expenses.fold(0.0, (sum, item) => sum + item.amount);
  }

  /// 加载指定车辆的费用记录与保养提醒
  Future<void> loadExpenses(String vehicleId,
      {double currentMaxMileage = 0.0}) async {
    final requestId = ++_loadRequestId;
    _currentVehicleId = vehicleId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final expenses = await _db.getExpenseRecords(vehicleId);
      if (requestId != _loadRequestId || _currentVehicleId != vehicleId) return;
      _expenses = expenses;
      // 扫描并计算临期与逾期保养/保险提醒
      _reminders = StatisticsService.getActiveReminders(
        currentMaxMileage: currentMaxMileage,
        expenseRecords: _expenses,
      );
      AppConfig.log(
          '已加载车辆($vehicleId)的 ${_expenses.length} 条费用记录，活跃提醒: ${_reminders.length} 项');
    } catch (e) {
      AppConfig.log('加载费用记录失败: $e');
      if (requestId == _loadRequestId && _currentVehicleId == vehicleId) {
        _errorMessage = '费用记录加载失败，请检查本地数据后重试';
      }
    } finally {
      if (requestId == _loadRequestId && _currentVehicleId == vehicleId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 新增费用记录
  Future<bool> addExpense(ExpenseRecordModel record,
      {double currentMaxMileage = 0.0}) async {
    try {
      await _db.insertExpenseRecord(record);
      if (_currentVehicleId != null) {
        await loadExpenses(_currentVehicleId!,
            currentMaxMileage: currentMaxMileage);
      }
      return true;
    } catch (e) {
      AppConfig.log('新增费用记录失败: $e');
      return false;
    }
  }

  /// 删除费用记录
  Future<bool> deleteExpense(String recordId,
      {double currentMaxMileage = 0.0}) async {
    try {
      await _db.deleteExpenseRecord(recordId);
      if (_currentVehicleId != null) {
        await loadExpenses(_currentVehicleId!,
            currentMaxMileage: currentMaxMileage);
      }
      return true;
    } catch (e) {
      AppConfig.log('删除费用记录失败: $e');
      return false;
    }
  }
}
