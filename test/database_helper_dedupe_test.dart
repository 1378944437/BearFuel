import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bearfuel/core/config/app_config.dart';
import 'package:bearfuel/data/database/database_helper.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/data/models/vehicle_model.dart';

/// 供 ffi 工厂运行的内存外隔离数据库测试：
/// 覆盖批量导入查重与车辆主键冲突不再级联清空两条回归。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = DatabaseHelper();
  const vehicleId = 'veh_dedupe_test';

  RefuelRecordModel record(
    DateTime date,
    double mileage,
    double total, {
    String vid = vehicleId,
  }) {
    return RefuelRecordModel(
      id: 'r_${date.toIso8601String()}_$mileage',
      vehicleId: vid,
      refuelDate: date,
      mileage: mileage,
      fuelAmount: 40,
      unitPrice: 8,
      totalPrice: total,
      fuelType: '92#',
      isFullTank: true,
    );
  }

  setUpAll(() async {
    // 与 DatabaseHelper 相同的路径约定，先删除残留库文件保证隔离
    final path = p.join(
      await databaseFactory.getDatabasesPath(),
      AppConfig.databaseName,
    );
    await databaseFactory.deleteDatabase(path);
  });

  setUp(() async {
    await db.clearVehicleRefuelRecords(vehicleId);
  });

  test('批量导入按"同车+同分钟+同里程"跳过重复记录', () async {
    await db.insertVehicle(
      VehicleModel(id: vehicleId, name: '查重测试车', isDefault: false),
    );

    final existing = record(DateTime(2026, 6, 1, 8, 30), 10000, 400.0);

    // 首次导入：正常入库
    final first = await db.batchInsertRefuelRecords([existing]);
    expect(first.inserted, equals(1));
    expect(first.skippedDuplicates, equals(0));

    // 第二次导入同一文件：库内已有记录 + 批内重复都应被跳过
    final batchDuplicate = record(DateTime(2026, 6, 1, 8, 30), 10000, 400.0);
    final fresh = record(DateTime(2026, 6, 15, 9, 0), 10500, 320.0);
    final second = await db.batchInsertRefuelRecords([
      batchDuplicate,
      fresh,
      fresh,
    ]);
    expect(second.inserted, equals(1));
    expect(second.skippedDuplicates, equals(2));

    // 第三次全量重复导入：全部跳过，历史不再翻倍
    final third = await db.batchInsertRefuelRecords([
      existing,
      record(DateTime(2026, 6, 15, 9, 0), 10500, 320.0),
    ]);
    expect(third.inserted, equals(0));
    expect(third.skippedDuplicates, equals(2));

    final rows = await db.getRefuelRecords(vehicleId);
    expect(rows.length, equals(2));
  });

  test('insertVehicle 主键冲突时报错而不是级联清空既有数据', () async {
    const conflictId = 'veh_conflict_test';
    await db.insertVehicle(
      VehicleModel(id: conflictId, name: '冲突测试车', isDefault: false),
    );
    await db.insertRefuelRecord(
      record(DateTime(2026, 6, 1, 8, 30), 10000, 400.0, vid: conflictId),
    );

    // 相同主键再次插入：abort 策略应抛错（此前 replace 会先删旧车并级联清空加油记录）
    await expectLater(
      db.insertVehicle(
        VehicleModel(id: conflictId, name: '冲突测试车副本', isDefault: false),
      ),
      throwsA(anything),
    );

    final rows = await db.getRefuelRecords(conflictId);
    expect(rows, isNotEmpty, reason: '主键冲突后原有加油记录必须完好无损');
  });
}
