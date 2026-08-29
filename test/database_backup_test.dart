import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/database/database_helper.dart';

void main() {
  test('空车辆全量备份在访问数据库前被拒绝', () async {
    final result = await DatabaseHelper().restoreFullBackupData({
      'app': 'BearFuel',
      'vehicles': <Map<String, dynamic>>[],
      'refuel_records': <Map<String, dynamic>>[],
      'expense_records': <Map<String, dynamic>>[],
      'weather_snapshots': <Map<String, dynamic>>[],
    });

    expect(result, isFalse);
  });

  test('备份字段类型错误时被拒绝', () async {
    final result = await DatabaseHelper().restoreFullBackupData({
      'app': 'BearFuel',
      'vehicles': [
        {'id': 'car-1', 'name': 123, 'created_at': '2026-08-28T00:00:00.000'},
      ],
      'refuel_records': [],
    });

    expect(result, isFalse);
  });
}
