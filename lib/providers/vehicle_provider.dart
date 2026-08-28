import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/vehicle_model.dart';
import '../core/config/app_config.dart';

/// 车辆状态管理 Provider
class VehicleProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  List<VehicleModel> _vehicles = [];
  VehicleModel? _currentVehicle;
  bool _isLoading = false;
  Future<void> _selectionTail = Future<void>.value();

  List<VehicleModel> get vehicles => _vehicles;
  VehicleModel? get currentVehicle => _currentVehicle;
  bool get isLoading => _isLoading;

  /// 初始化并加载车辆数据
  Future<void> loadVehicles() async {
    _isLoading = true;
    notifyListeners();

    try {
      _vehicles = await _db.getVehicles();
      _currentVehicle = await _db.getDefaultVehicle();
      if (_currentVehicle == null && _vehicles.isNotEmpty) {
        _currentVehicle = _vehicles.first;
      }
      AppConfig.log(
        '已成功加载 ${_vehicles.length} 辆车辆数据，当前选中: ${_currentVehicle?.name}',
      );
    } catch (e) {
      AppConfig.log('加载车辆数据失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 切换当前选中的激活车辆
  Future<bool> selectVehicle(VehicleModel vehicle) {
    final result = _selectionTail.then((_) => _selectVehicle(vehicle));
    _selectionTail = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  Future<bool> _selectVehicle(VehicleModel vehicle) async {
    if (_currentVehicle?.id == vehicle.id) return true;

    try {
      final changed = await _db.setDefaultVehicle(vehicle.id);
      if (!changed) return false;
      _currentVehicle = vehicle.copyWith(isDefault: true);
      // 更新列表中对应车辆的 isDefault 状态
      _vehicles = _vehicles
          .map((v) => v.copyWith(isDefault: v.id == vehicle.id))
          .toList();
      notifyListeners();
      return true;
    } catch (e) {
      AppConfig.log('切换车辆失败: $e');
      return false;
    }
  }

  /// 新增车辆
  Future<bool> addVehicle(VehicleModel vehicle) async {
    try {
      await _db.insertVehicle(vehicle);
      await loadVehicles();
      return true;
    } catch (e) {
      AppConfig.log('新增车辆失败: $e');
      rethrow;
    }
  }

  /// 修改车辆信息
  Future<bool> updateVehicle(VehicleModel vehicle) async {
    try {
      final count = await _db.updateVehicle(vehicle);
      if (count == 0) return false;
      await loadVehicles();
      return true;
    } catch (e) {
      AppConfig.log('更新车辆失败: $e');
      rethrow;
    }
  }

  /// 删除车辆
  Future<bool> deleteVehicle(String vehicleId) async {
    try {
      final count = await _db.deleteVehicle(vehicleId);
      if (count == 0) return false;
      await loadVehicles();
      return true;
    } catch (e) {
      AppConfig.log('删除车辆失败: $e');
      return false;
    }
  }
}
