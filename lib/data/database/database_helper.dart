import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/app_config.dart';
import '../models/vehicle_model.dart';
import '../models/refuel_record_model.dart';
import '../models/expense_record_model.dart';
import '../models/weather_snapshot_model.dart';

/// SQLite 本地数据库核心辅助类与仓储管理
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  /// 获取数据库实例单例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库连接并建表
  Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, AppConfig.databaseName);
      AppConfig.log('正在初始化本地 SQLite 数据库: $path');

      final db = await openDatabase(
        path,
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );

      // 安全自检并补齐表结构
      try {
        await _ensureTableSchema(db);
      } catch (e) {
        AppConfig.log('数据库表结构自愈检查警告: $e');
      }

      return db;
    } catch (e, stack) {
      AppConfig.log('数据库初始化异常: $e\n$stack');
      rethrow;
    }
  }

  /// 动态自愈：安全检查并补齐缺失列
  Future<void> _ensureTableSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='vehicles'",
    );
    if (tables.isEmpty) {
      await _onCreate(db, 1);
      return;
    }

    final columns = await db.rawQuery('PRAGMA table_info(vehicles)');
    final colNames = columns.map((c) => c['name'] as String).toSet();

    if (!colNames.contains('initial_mileage')) {
      await db.execute(
        'ALTER TABLE vehicles ADD COLUMN initial_mileage REAL NOT NULL DEFAULT 0.0',
      );
    }
    if (!colNames.contains('tank_capacity')) {
      await db.execute(
        'ALTER TABLE vehicles ADD COLUMN tank_capacity REAL NOT NULL DEFAULT 50.0',
      );
    }
    if (!colNames.contains('default_fuel_type')) {
      await db.execute(
        "ALTER TABLE vehicles ADD COLUMN default_fuel_type TEXT NOT NULL DEFAULT '92# 汽油'",
      );
    }
    if (!colNames.contains('is_default')) {
      await db.execute(
        'ALTER TABLE vehicles ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!colNames.contains('plate_number')) {
      await db.execute('ALTER TABLE vehicles ADD COLUMN plate_number TEXT');
    }
    if (!colNames.contains('brand')) {
      await db.execute('ALTER TABLE vehicles ADD COLUMN brand TEXT');
    }
    if (!colNames.contains('model')) {
      await db.execute('ALTER TABLE vehicles ADD COLUMN model TEXT');
    }

    final weatherTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='weather_snapshots'",
    );
    if (weatherTables.isEmpty) {
      await _createWeatherSnapshotTable(db);
    }
  }

  /// 创建数据表结构
  Future<void> _onCreate(Database db, int version) async {
    AppConfig.log('开始创建数据库表结构...');

    // 1. 车辆表
    await db.execute('''
      CREATE TABLE vehicles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        plate_number TEXT,
        brand TEXT,
        model TEXT,
        tank_capacity REAL NOT NULL DEFAULT 50.0,
        default_fuel_type TEXT NOT NULL DEFAULT '92# 汽油',
        initial_mileage REAL NOT NULL DEFAULT 0.0,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 2. 加油记录表
    await db.execute('''
      CREATE TABLE refuel_records (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT NOT NULL,
        refuel_date TEXT NOT NULL,
        mileage REAL NOT NULL,
        fuel_amount REAL NOT NULL,
        unit_price REAL NOT NULL,
        total_price REAL NOT NULL,
        fuel_type TEXT NOT NULL,
        gas_station TEXT,
        is_full_tank INTEGER NOT NULL DEFAULT 1,
        is_forgot_previous INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        fuel_consumption REAL,
        cost_per_km REAL,
        distance REAL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
      )
    ''');

    // 3. 其它费用记录表 (保养、保险、年检等)
    await db.execute('''
      CREATE TABLE expense_records (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT NOT NULL,
        category TEXT NOT NULL,
        expense_date TEXT NOT NULL,
        amount REAL NOT NULL,
        current_mileage REAL,
        next_reminder_mileage REAL,
        next_reminder_date TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
      )
    ''');

    await _createWeatherSnapshotTable(db);

    // 创建必要索引以加速按车辆和时间排序查询
    await db.execute(
      'CREATE INDEX idx_refuel_vehicle_date ON refuel_records (vehicle_id, refuel_date ASC, mileage ASC)',
    );
    await db.execute(
      'CREATE INDEX idx_expense_vehicle_date ON expense_records (vehicle_id, expense_date DESC)',
    );

    // 写入默认示例车辆
    final defaultVehicleId = const Uuid().v4();
    await db.insert('vehicles', {
      'id': defaultVehicleId,
      'name': '默认爱车',
      'plate_number': '京A·88888',
      'brand': '家用燃油车',
      'model': '标准版',
      'tank_capacity': 50.0,
      'default_fuel_type': '92# 汽油',
      'initial_mileage': 0.0,
      'is_default': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    AppConfig.log('数据库表及默认车辆创建完成！');
  }

  /// 数据库版本升级迁移策略
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    AppConfig.log('数据库版本升级: $oldVersion -> $newVersion');
    if (oldVersion < 3) {
      await _createWeatherSnapshotTable(db);
    }
  }

  Future<void> _createWeatherSnapshotTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS weather_snapshots (
        id TEXT PRIMARY KEY,
        city_key TEXT NOT NULL,
        city_name TEXT NOT NULL,
        province TEXT,
        snapshot_date TEXT NOT NULL,
        temperature REAL,
        temp_high REAL,
        temp_low REAL,
        condition TEXT,
        aqi INTEGER,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        UNIQUE(city_key, snapshot_date)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_weather_city_date ON weather_snapshots (city_key, snapshot_date ASC)',
    );
  }

  // ==================== 车辆模块 CRUD ====================

  /// 查询所有车辆列表
  Future<List<VehicleModel>> getVehicles() async {
    try {
      final db = await database;
      final maps = await db.query(
        'vehicles',
        orderBy: 'is_default DESC, created_at ASC',
      );
      return maps.map((e) => VehicleModel.fromMap(e)).toList();
    } catch (e) {
      AppConfig.log('获取车辆列表失败: $e');
      return [];
    }
  }

  /// 获取当前默认选中的车辆
  Future<VehicleModel?> getDefaultVehicle() async {
    try {
      final db = await database;
      final maps = await db.query(
        'vehicles',
        where: 'is_default = 1',
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return VehicleModel.fromMap(maps.first);
      }
      // 若无默认选中，取第一辆
      final all = await getVehicles();
      if (all.isEmpty) return null;
      await db.update(
        'vehicles',
        {'is_default': 1},
        where: 'id = ?',
        whereArgs: [all.first.id],
      );
      return all.first.copyWith(isDefault: true);
    } catch (e) {
      AppConfig.log('获取默认车辆失败: $e');
      return null;
    }
  }

  /// 新增车辆
  Future<int> insertVehicle(VehicleModel vehicle) async {
    try {
      final db = await database;
      final rowId = await db.transaction((txn) async {
        if (vehicle.isDefault) {
          await txn.rawUpdate('UPDATE vehicles SET is_default = 0');
        }
        return txn.insert(
          'vehicles',
          vehicle.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      AppConfig.log(
        '成功写入车辆数据 [${vehicle.name}], id: ${vehicle.id}, rowId: $rowId',
      );
      return rowId;
    } catch (e) {
      AppConfig.log('新增车辆初次写入异常，执行紧急自检修复: $e');
      try {
        final db = await database;
        await _ensureTableSchema(db);
        return db.transaction((txn) async {
          if (vehicle.isDefault) {
            await txn.rawUpdate('UPDATE vehicles SET is_default = 0');
          }
          return txn.insert(
            'vehicles',
            vehicle.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });
      } catch (retryError) {
        AppConfig.log('新增车辆重试失败: $retryError');
        rethrow;
      }
    }
  }

  /// 更新车辆信息
  Future<int> updateVehicle(VehicleModel vehicle) async {
    try {
      final db = await database;
      final count = await db.transaction((txn) async {
        if (vehicle.isDefault) {
          await txn.rawUpdate('UPDATE vehicles SET is_default = 0');
        }
        return txn.update(
          'vehicles',
          vehicle.toMap(),
          where: 'id = ?',
          whereArgs: [vehicle.id],
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      AppConfig.log('成功更新车辆数据 [${vehicle.name}], count: $count');
      return count;
    } catch (e) {
      AppConfig.log('更新车辆初次失败，执行紧急修复: $e');
      try {
        final db = await database;
        await _ensureTableSchema(db);
        return db.transaction((txn) async {
          if (vehicle.isDefault) {
            await txn.rawUpdate('UPDATE vehicles SET is_default = 0');
          }
          return txn.update(
            'vehicles',
            vehicle.toMap(),
            where: 'id = ?',
            whereArgs: [vehicle.id],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });
      } catch (retryError) {
        AppConfig.log('更新车辆重试失败: $retryError');
        rethrow;
      }
    }
  }

  /// 设置激活/默认车辆
  Future<bool> setDefaultVehicle(String vehicleId) async {
    try {
      final db = await database;
      return db.transaction((txn) async {
        final target = await txn.query(
          'vehicles',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [vehicleId],
          limit: 1,
        );
        if (target.isEmpty) return false;
        await txn.rawUpdate('UPDATE vehicles SET is_default = 0');
        final count = await txn.rawUpdate(
          'UPDATE vehicles SET is_default = 1 WHERE id = ?',
          [vehicleId],
        );
        return count == 1;
      });
    } catch (e) {
      AppConfig.log('设置默认车辆失败: $e');
      rethrow;
    }
  }

  /// 删除车辆（同时级联删除该车的所有记录）
  Future<int> deleteVehicle(String vehicleId) async {
    try {
      final db = await database;
      return await db.transaction((txn) async {
        await txn.delete(
          'refuel_records',
          where: 'vehicle_id = ?',
          whereArgs: [vehicleId],
        );
        await txn.delete(
          'expense_records',
          where: 'vehicle_id = ?',
          whereArgs: [vehicleId],
        );
        final deleted = await txn.delete(
          'vehicles',
          where: 'id = ?',
          whereArgs: [vehicleId],
        );
        if (deleted > 0) {
          final defaults = await txn.query(
            'vehicles',
            columns: ['id'],
            where: 'is_default = 1',
            limit: 1,
          );
          if (defaults.isEmpty) {
            final next = await txn.query(
              'vehicles',
              columns: ['id'],
              orderBy: 'created_at ASC',
              limit: 1,
            );
            if (next.isNotEmpty) {
              await txn.update(
                'vehicles',
                {'is_default': 1},
                where: 'id = ?',
                whereArgs: [next.first['id']],
              );
            }
          }
        }
        return deleted;
      });
    } catch (e) {
      AppConfig.log('删除车辆失败: $e');
      rethrow;
    }
  }

  // ==================== 加油记录模块 CRUD ====================

  /// 获取指定车辆的所有加油记录（按里程升序排列）
  Future<List<RefuelRecordModel>> getRefuelRecords(String vehicleId) async {
    try {
      final db = await database;
      final maps = await db.query(
        'refuel_records',
        where: 'vehicle_id = ?',
        whereArgs: [vehicleId],
        orderBy: 'refuel_date ASC, mileage ASC',
      );
      return maps.map((e) => RefuelRecordModel.fromMap(e)).toList();
    } catch (e) {
      AppConfig.log('获取加油记录失败: $e');
      rethrow;
    }
  }

  /// 批量插入加油记录（用于小熊油耗数据导入）
  Future<void> batchInsertRefuelRecords(List<RefuelRecordModel> records) async {
    try {
      final db = await database;
      final batch = db.batch();
      for (final r in records) {
        batch.insert('refuel_records', r.toMap());
      }
      await batch.commit(noResult: true);
      AppConfig.log('已批量插入 ${records.length} 条加油记录');
    } catch (e) {
      AppConfig.log('批量插入加油记录失败: $e');
      rethrow;
    }
  }

  /// 在一个事务中覆盖指定车辆的加油记录，失败时保留原数据。
  Future<void> replaceVehicleRefuelRecords(
    String vehicleId,
    List<RefuelRecordModel> records,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'refuel_records',
        where: 'vehicle_id = ?',
        whereArgs: [vehicleId],
      );
      for (final record in records) {
        await txn.insert('refuel_records', record.toMap());
      }
    });
  }

  /// 清空指定车辆的加油记录
  Future<int> clearVehicleRefuelRecords(String vehicleId) async {
    try {
      final db = await database;
      return await db.delete(
        'refuel_records',
        where: 'vehicle_id = ?',
        whereArgs: [vehicleId],
      );
    } catch (e) {
      AppConfig.log('清空车辆加油记录失败: $e');
      rethrow;
    }
  }

  /// 新增加油记录
  Future<int> insertRefuelRecord(RefuelRecordModel record) async {
    try {
      final db = await database;
      return await db.insert('refuel_records', record.toMap());
    } catch (e) {
      AppConfig.log('新增加油记录失败: $e');
      rethrow;
    }
  }

  /// 更新单条加油记录
  Future<int> updateRefuelRecord(RefuelRecordModel record) async {
    try {
      final db = await database;
      return await db.update(
        'refuel_records',
        record.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );
    } catch (e) {
      AppConfig.log('更新加油记录失败: $e');
      rethrow;
    }
  }

  /// 批量更新加油记录计算结果（用于重新计算后回写油耗）
  Future<void> batchUpdateRefuelCalculations(
    List<RefuelRecordModel> records,
  ) async {
    try {
      final db = await database;
      final batch = db.batch();
      for (final r in records) {
        batch.update(
          'refuel_records',
          {
            'fuel_consumption': r.fuelConsumption,
            'cost_per_km': r.costPerKm,
            'distance': r.distance,
          },
          where: 'id = ?',
          whereArgs: [r.id],
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      AppConfig.log('批量更新加油计算失败: $e');
      rethrow;
    }
  }

  /// 删除加油记录
  Future<int> deleteRefuelRecord(String recordId) async {
    try {
      final db = await database;
      return await db.delete(
        'refuel_records',
        where: 'id = ?',
        whereArgs: [recordId],
      );
    } catch (e) {
      AppConfig.log('删除加油记录失败: $e');
      rethrow;
    }
  }

  // ==================== 其它费用模块 CRUD ====================

  /// 获取指定车辆的费用记录列表（按日期倒序）
  Future<List<ExpenseRecordModel>> getExpenseRecords(String vehicleId) async {
    try {
      final db = await database;
      final maps = await db.query(
        'expense_records',
        where: 'vehicle_id = ?',
        whereArgs: [vehicleId],
        orderBy: 'expense_date DESC',
      );
      return maps.map((e) => ExpenseRecordModel.fromMap(e)).toList();
    } catch (e) {
      AppConfig.log('获取费用记录失败: $e');
      rethrow;
    }
  }

  /// 新增费用记录
  Future<int> insertExpenseRecord(ExpenseRecordModel record) async {
    try {
      final db = await database;
      return await db.insert('expense_records', record.toMap());
    } catch (e) {
      AppConfig.log('新增费用记录失败: $e');
      rethrow;
    }
  }

  /// 按城市和日期保存天气快照，同一天重复采集时覆盖旧值。
  Future<void> upsertWeatherSnapshots(
    List<WeatherSnapshotModel> snapshots,
  ) async {
    if (snapshots.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final snapshot in snapshots) {
      batch.insert(
        'weather_snapshots',
        snapshot.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<WeatherSnapshotModel>> getWeatherSnapshots({
    required String cityKey,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final db = await database;
      final where = <String>['city_key = ?'];
      final args = <Object?>[cityKey];
      if (from != null) {
        where.add('snapshot_date >= ?');
        args.add(from.toIso8601String().substring(0, 10));
      }
      if (to != null) {
        where.add('snapshot_date <= ?');
        args.add(to.toIso8601String().substring(0, 10));
      }
      final rows = await db.query(
        'weather_snapshots',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'snapshot_date ASC',
      );
      return rows.map(WeatherSnapshotModel.fromMap).toList();
    } catch (e) {
      AppConfig.log('获取天气快照失败: $e');
      return [];
    }
  }

  /// 删除费用记录
  Future<int> deleteExpenseRecord(String recordId) async {
    try {
      final db = await database;
      return await db.delete(
        'expense_records',
        where: 'id = ?',
        whereArgs: [recordId],
      );
    } catch (e) {
      AppConfig.log('删除费用记录失败: $e');
      rethrow;
    }
  }

  // ==================== 全量数据备份与安全恢复 ====================

  /// 获取 SQLite 数据库在手机上的物理绝对路径
  Future<String> getDatabaseFilePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, AppConfig.databaseName);
  }

  /// 导出全库数据为标准化 JSON 备份字典
  Future<Map<String, dynamic>> exportFullBackupData() async {
    final db = await database;
    final vehicles = await db.query('vehicles');
    final refuels = await db.query('refuel_records');
    final expenses = await db.query('expense_records');
    final weatherSnapshots = await db.query('weather_snapshots');

    return {
      'app': 'BearFuel',
      'version': AppConfig.versionName,
      'export_time': DateTime.now().toIso8601String(),
      'vehicles': vehicles,
      'refuel_records': refuels,
      'expense_records': expenses,
      'weather_snapshots': weatherSnapshots,
    };
  }

  /// 从 JSON 备份全量恢复数据（采用单事务安全替换）
  Future<bool> restoreFullBackupData(Map<String, dynamic> backupData) async {
    bool text(dynamic value) => value is String && value.trim().isNotEmpty;
    bool date(dynamic value) =>
        value is String && DateTime.tryParse(value) != null;
    bool number(dynamic value, {required bool positive}) {
      return value is num &&
          value.isFinite &&
          (positive ? value > 0 : value >= 0);
    }

    bool flag(dynamic value) => value is int && (value == 0 || value == 1);

    bool validRows(
      dynamic value,
      bool Function(Map<String, dynamic>) validator, {
      bool allowEmpty = true,
    }) {
      if (value is! List || (!allowEmpty && value.isEmpty)) return false;
      for (final row in value) {
        if (row is! Map) return false;
        try {
          if (!validator(Map<String, dynamic>.from(row))) return false;
        } catch (_) {
          return false;
        }
      }
      return true;
    }

    final vehicleIds = <String>{};
    final refuelIds = <String>{};
    final expenseIds = <String>{};
    final weatherIds = <String>{};
    bool validVehicle(Map<String, dynamic> row) {
      final id = row['id'];
      if (!text(id) || !text(row['name']) || !date(row['created_at'])) {
        return false;
      }
      if (!vehicleIds.add(id as String)) return false;
      return (row['tank_capacity'] == null ||
              number(row['tank_capacity'], positive: true)) &&
          (row['initial_mileage'] == null ||
              number(row['initial_mileage'], positive: false)) &&
          (row['default_fuel_type'] == null ||
              text(row['default_fuel_type'])) &&
          (row['is_default'] == null || flag(row['is_default'])) &&
          (row['plate_number'] == null || text(row['plate_number'])) &&
          (row['brand'] == null || text(row['brand'])) &&
          (row['model'] == null || text(row['model']));
    }

    bool validRefuel(Map<String, dynamic> row) {
      if (!text(row['id']) || !refuelIds.add(row['id'] as String)) return false;
      return text(row['vehicle_id']) &&
          vehicleIds.contains(row['vehicle_id']) &&
          date(row['refuel_date']) &&
          number(row['mileage'], positive: false) &&
          number(row['fuel_amount'], positive: true) &&
          number(row['unit_price'], positive: true) &&
          number(row['total_price'], positive: true) &&
          text(row['fuel_type']) &&
          flag(row['is_full_tank']) &&
          flag(row['is_forgot_previous']) &&
          date(row['created_at']) &&
          (row['fuel_consumption'] == null ||
              number(row['fuel_consumption'], positive: true)) &&
          (row['cost_per_km'] == null ||
              number(row['cost_per_km'], positive: true)) &&
          (row['distance'] == null || number(row['distance'], positive: true));
    }

    bool validExpense(Map<String, dynamic> row) {
      if (!text(row['id']) || !expenseIds.add(row['id'] as String)) {
        return false;
      }
      return text(row['vehicle_id']) &&
          vehicleIds.contains(row['vehicle_id']) &&
          text(row['category']) &&
          date(row['expense_date']) &&
          number(row['amount'], positive: true) &&
          date(row['created_at']) &&
          (row['current_mileage'] == null ||
              number(row['current_mileage'], positive: false)) &&
          (row['next_reminder_mileage'] == null ||
              number(row['next_reminder_mileage'], positive: true)) &&
          (row['next_reminder_date'] == null ||
              date(row['next_reminder_date'])) &&
          (row['note'] == null || text(row['note']));
    }

    bool validWeather(Map<String, dynamic> row) {
      if (!text(row['id']) || !weatherIds.add(row['id'] as String)) {
        return false;
      }
      return text(row['city_key']) &&
          text(row['city_name']) &&
          date(row['snapshot_date']) &&
          text(row['source']) &&
          date(row['fetched_at']) &&
          (row['temperature'] == null ||
              number(row['temperature'], positive: false)) &&
          (row['temp_high'] == null ||
              number(row['temp_high'], positive: false)) &&
          (row['temp_low'] == null ||
              number(row['temp_low'], positive: false)) &&
          (row['aqi'] == null || row['aqi'] is int);
    }

    // Validate before opening the replacement transaction. An empty or
    // malformed backup must never be allowed to clear the local database.
    final isValid = backupData['app'] == 'BearFuel' &&
        validRows(backupData['vehicles'], validVehicle, allowEmpty: false) &&
        validRows(backupData['refuel_records'], validRefuel) &&
        (!backupData.containsKey('expense_records') ||
            validRows(backupData['expense_records'], validExpense)) &&
        (!backupData.containsKey('weather_snapshots') ||
            validRows(backupData['weather_snapshots'], validWeather));
    if (!isValid) {
      AppConfig.log('全量数据恢复已拒绝：备份格式无效或不包含车辆数据');
      return false;
    }

    try {
      final db = await database;
      await db.transaction((txn) async {
        final vehicles = (backupData['vehicles'] as List<dynamic>?) ?? [];
        final refuels = (backupData['refuel_records'] as List<dynamic>?) ?? [];
        final expenses =
            (backupData['expense_records'] as List<dynamic>?) ?? [];
        final includesWeatherSnapshots = backupData.containsKey(
          'weather_snapshots',
        );
        final weatherSnapshots =
            (backupData['weather_snapshots'] as List<dynamic>?) ?? [];

        // Delete child rows first so this remains valid when foreign keys are
        // enabled, then rebuild every table even when a backup section is empty.
        await txn.delete('expense_records');
        await txn.delete('refuel_records');
        await txn.delete('vehicles');
        // A full restore replaces the complete local dataset. Older backups
        // without snapshots must also clear current snapshots to avoid mixing
        // weather history from two different datasets.
        await txn.delete('weather_snapshots');

        for (final v in vehicles) {
          await txn.insert(
            'vehicles',
            Map<String, dynamic>.from(v),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        final defaults = await txn.query(
          'vehicles',
          columns: ['id'],
          where: 'is_default = 1',
          orderBy: 'created_at ASC',
        );
        if (defaults.length != 1) {
          await txn.rawUpdate('UPDATE vehicles SET is_default = 0');
          await txn.update(
            'vehicles',
            {'is_default': 1},
            where: 'id = ?',
            whereArgs: [
              defaults.isNotEmpty ? defaults.first['id'] : vehicles.first['id']
            ],
          );
        }

        for (final r in refuels) {
          await txn.insert(
            'refuel_records',
            Map<String, dynamic>.from(r),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        for (final e in expenses) {
          await txn.insert(
            'expense_records',
            Map<String, dynamic>.from(e),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        if (includesWeatherSnapshots) {
          for (final snapshot in weatherSnapshots) {
            await txn.insert(
              'weather_snapshots',
              Map<String, dynamic>.from(snapshot),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      });
      AppConfig.log('全量数据恢复成功！');
      return true;
    } catch (e) {
      AppConfig.log('全量数据恢复失败: $e');
      return false;
    }
  }
}
