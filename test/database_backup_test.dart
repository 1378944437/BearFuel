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
}
