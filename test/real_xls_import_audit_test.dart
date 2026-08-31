import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/domain/bear_fuel_importer.dart';

void main() {
  test('真实小熊油耗 XLS 样例端到端解析审计', () {
    final file = File('小熊油耗csv实例/小熊油耗-10790947-2026-08-25.xls');
    expect(file.existsSync(), isTrue);
    final result = BearFuelImporter.parseBytes(
      file.readAsBytesSync(),
      'audit-vehicle',
    );
    // Keep the output visible in CI to audit the actual export shape/count.
    // ignore: avoid_print
    print(
      'XLS audit: success=${result.success}, total=${result.totalCount}, '
      'valid=${result.validCount}, skipped=${result.skippedCount}, '
      'error=${result.errorMessage}',
    );
    for (final record in result.parsedRecords.take(3)) {
      // ignore: avoid_print
      print(
        'record: ${record.refuelDate.toIso8601String()} '
        'mileage=${record.mileage} amount=${record.fuelAmount} '
        'unitPrice=${record.unitPrice} total=${record.totalPrice} '
        'fuel=${record.fuelType} full=${record.isFullTank} '
        'forgot=${record.isForgotPrevious} station=${record.gasStation}',
      );
    }
    expect(result.success, isTrue);
    expect(result.validCount, 30);
    // 真实导出列含“机显金额”和“实付金额”：账本必须保存实付金额，
    // 机显金额与实付金额之差保存为优惠金额。
    expect(result.parsedRecords[3].totalPrice, 192.44);
    expect(result.parsedRecords[3].discountAmount, 7.57);
    // “亮灯”是小熊油耗原表的列名，应映射到警告灯字段。
    expect(result.parsedRecords.first.fuelWarningLightOn, isTrue);
    expect(result.parsedRecords[1].fuelWarningLightOn, isTrue);
  });
}
