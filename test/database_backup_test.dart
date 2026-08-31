import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/database/database_helper.dart';

void main() {
  group('全量恢复前置校验', () {
    test('空车辆全量备份在访问数据库前被拒绝', () async {
      final result = await DatabaseHelper().restoreFullBackupData({
        'app': 'BearFuel',
        'vehicles': <Map<String, dynamic>>[],
        'refuel_records': <Map<String, dynamic>>[],
        'expense_records': <Map<String, dynamic>>[],
        'weather_snapshots': <Map<String, dynamic>>[],
      });

      expect(result.success, isFalse);
    });

    test('备份字段类型错误时被拒绝', () async {
      final result = await DatabaseHelper().restoreFullBackupData({
        'app': 'BearFuel',
        'vehicles': [
          {'id': 'car-1', 'name': 123, 'created_at': '2026-08-28T00:00:00.000'},
        ],
        'refuel_records': [],
      });

      expect(result.success, isFalse);
    });
  });

  group('备份金额一致性检查 (P1-09)', () {
    Map<String, dynamic> row({
      required String id,
      double fuelAmount = 25.0,
      double unitPrice = 8.0,
      double totalPrice = 200.0,
      double? discount,
    }) => {
      'id': id,
      'fuel_amount': fuelAmount,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'discount_amount': discount,
    };

    test('量价与优惠自洽时无问题', () {
      // 25 L × 8 元 = 200 元机显，实付 192.44，优惠 7.56
      final report = DatabaseHelper.inspectRefuelAmountConsistency([
        row(id: 'ok-1', totalPrice: 192.44, discount: 7.56),
      ]);
      expect(report.isClean, isTrue);
      expect(report.unverifiableCount, equals(0));
    });

    test('机显金额与量价不符时记录问题', () {
      final report = DatabaseHelper.inspectRefuelAmountConsistency([
        row(
          id: 'bad-1',
          fuelAmount: 25.0,
          unitPrice: 8.0,
          totalPrice: 100.0,
          discount: 0.0,
        ),
      ]);
      expect(report.issues.length, equals(1));
      expect(report.issues.single.recordId, equals('bad-1'));
      expect(
        report.issues.single.kind,
        equals(BackupAmountIssueKind.quantityPriceMismatch),
      );
    });

    test('两位小数舍入在容差内不报错', () {
      final report = DatabaseHelper.inspectRefuelAmountConsistency([
        row(
          id: 'round-1',
          fuelAmount: 24.63,
          unitPrice: 7.85,
          totalPrice: 193.34,
          discount: 0.0,
        ),
      ]);
      expect(report.isClean, isTrue);
    });

    test('缺少优惠金额时记为无法核验而非不一致', () {
      final report = DatabaseHelper.inspectRefuelAmountConsistency([
        row(id: 'nodisc-1', totalPrice: 192.44),
      ]);
      expect(report.isClean, isTrue);
      expect(report.unverifiableCount, equals(1));
    });

    test('负优惠被识别，且不再据此推断量价', () {
      final report = DatabaseHelper.inspectRefuelAmountConsistency([
        row(id: 'neg', discount: -5.0),
      ]);
      expect(report.issues.length, equals(1));
      expect(
        report.issues.single.kind,
        equals(BackupAmountIssueKind.negativeDiscount),
      );
    });
  });
}
