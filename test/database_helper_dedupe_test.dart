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
      // 主键必须含车辆，否则跨车同时刻同里程的用例会因主键冲突而非去重失败
      id: 'r_${vid}_${date.toIso8601String()}_$mileage',
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

  test('跨车辆同时刻同里程的记录不互相判重 (P1-07)', () async {
    const otherVehicleId = 'veh_dedupe_cross';
    await db.insertVehicle(
      VehicleModel(id: otherVehicleId, name: '跨车查重测试车', isDefault: false),
    );

    final sameMoment = DateTime(2026, 6, 20, 10, 0);
    // 两辆车在同一分钟、相同表显里程各加一次油，是现实存在的场景
    final stats = await db.batchInsertRefuelRecords([
      record(sameMoment, 20000, 400.0),
      record(sameMoment, 20000, 380.0, vid: otherVehicleId),
    ]);

    expect(stats.inserted, equals(2), reason: '去重指纹必须包含车辆，否则第二辆车的记录会被静默丢弃');
    expect(stats.skippedDuplicates, equals(0));
    expect(stats.byVehicle[vehicleId]?.inserted, equals(1));
    expect(stats.byVehicle[otherVehicleId]?.inserted, equals(1));

    final rowsA = await db.getRefuelRecords(vehicleId);
    final rowsB = await db.getRefuelRecords(otherVehicleId);
    expect(rowsA.any((r) => r.mileage == 20000), isTrue);
    expect(rowsB.any((r) => r.mileage == 20000), isTrue);
  });

  test('重复跳过会按原因归类并计入导入报告', () async {
    final existing = record(DateTime(2026, 7, 1, 9, 0), 30000, 500.0);
    await db.batchInsertRefuelRecords([existing]);

    final fresh = record(DateTime(2026, 7, 5, 9, 0), 30500, 300.0);
    final stats = await db.batchInsertRefuelRecords([
      existing, // 与库内已有记录重复
      fresh, // 正常新增
      fresh, // 与本批次前序记录重复
    ]);

    expect(stats.inserted, equals(1));
    expect(stats.skippedDuplicates, equals(2));
    expect(stats.skipReasons[ImportSkipReason.duplicateInDb], equals(1));
    expect(stats.skipReasons[ImportSkipReason.duplicateInBatch], equals(1));
  });

  test('覆盖导入拒绝 vehicleId 不匹配的记录且保留原数据 (P1-08)', () async {
    const targetId = 'veh_overwrite_guard';
    await db.insertVehicle(
      VehicleModel(id: targetId, name: '覆盖导入守卫车', isDefault: false),
    );
    await db.insertRefuelRecord(
      record(DateTime(2026, 8, 1, 8, 0), 40000, 320.0, vid: targetId),
    );

    await expectLater(
      db.replaceVehicleRefuelRecords(targetId, [
        record(DateTime(2026, 8, 10, 8, 0), 40500, 300.0, vid: targetId),
        // 携带了错误归属的记录
        record(DateTime(2026, 8, 11, 8, 0), 40600, 280.0, vid: 'veh_other'),
      ]),
      throwsA(isA<ArgumentError>()),
    );

    final rows = await db.getRefuelRecords(targetId);
    expect(
      rows.single.mileage,
      equals(40000),
      reason: '校验失败必须整事务拒绝，不能先删后插导致原数据丢失',
    );
  });

  test('覆盖导入归属一致时正常替换', () async {
    const targetId = 'veh_overwrite_ok';
    await db.insertVehicle(
      VehicleModel(id: targetId, name: '覆盖导入正常车', isDefault: false),
    );
    await db.insertRefuelRecord(
      record(DateTime(2026, 8, 1, 8, 0), 50000, 320.0, vid: targetId),
    );

    await db.replaceVehicleRefuelRecords(targetId, [
      record(DateTime(2026, 8, 10, 8, 0), 50500, 300.0, vid: targetId),
      record(DateTime(2026, 8, 20, 8, 0), 51000, 310.0, vid: targetId),
    ]);

    final rows = await db.getRefuelRecords(targetId);
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
