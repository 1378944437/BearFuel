import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/domain/bear_fuel_importer.dart';
import 'package:bearfuel/domain/fuel_calculator.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';

void main() {
  group('小熊油耗数据导入与导出引擎测试 (BearFuelImporter Tests)', () {
    test('1. 标准小熊油耗 CSV 解析测试', () {
      const sampleCsv = '''时间,当前里程,加油量,单价,金额,是否加满,是否漏记,油品,加油站,备注
2026-01-05 08:30,10000,48.5,8.12,393.82,是,否,92# 汽油,中石化朝阳路加油站,首充加满基准
2026-01-18 17:45,10620,44.2,8.15,360.23,是,否,92# 汽油,中石油北苑站,上下班通勤
2026-02-02 12:10,10950,20.0,8.20,164.00,否,否,92# 汽油,壳牌立汤路站,临时补油
2026-02-15 09:20,11380,32.8,8.25,270.60,是,否,92# 汽油,中石化望京站,春节高速自驾''';

      final result = BearFuelImporter.parseCsv(sampleCsv, 'test_car_id');

      expect(result.success, isTrue);
      expect(result.validCount, equals(4));
      expect(result.skippedCount, equals(0));

      final records = result.parsedRecords;
      expect(records[0].mileage, equals(10000.0));
      expect(records[0].fuelAmount, equals(48.5));
      expect(records[0].isFullTank, isTrue);
      expect(records[0].gasStation, equals('中石化朝阳路加油站'));

      expect(records[2].isFullTank, isFalse);
      expect(records[2].fuelAmount, equals(20.0));

      final computed = FuelCalculator.computeRecords(records);
      expect(computed[1].fuelConsumption, equals(7.13));
      expect(computed[3].fuelConsumption, equals(6.95));
    });

    test('2. 直接从原始文件字节流 (parseBytes) 解码导入测试 (含 UTF-8 BOM 嗅探)', () {
      const csvStr = '''时间,当前里程,加油量,单价,金额,是否加满,是否漏记,油品,加油站,备注
2026-01-05 08:30,10000,50.0,8.0,400.0,是,否,92# 汽油,荆门象山站,首充
2026-01-15 08:30,10500,40.0,8.0,320.0,是,否,92# 汽油,荆门虎牙关站,二充''';

      // 模拟带 UTF-8 BOM 头的字节流 (0xEF, 0xBB, 0xBF)
      final rawBytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csvStr)];

      final result = BearFuelImporter.parseBytes(rawBytes, 'test_car_id');
      expect(result.success, isTrue);
      expect(result.validCount, equals(2));
      expect(result.parsedRecords[0].gasStation, equals('荆门象山站'));
    });

    test('3. 异构表头容错与缺失金额自动推算测试', () {
      const variedCsv = '''日期,表显里程,升数,油价,总花费,加满,漏记,标号,站名,备注
2026-03-01,15000,50.0,8.0,,1,0,95#,中石化,推算金额
2026-03-10,15500,40.0,,320.0,1,0,95#,中石油,推算单价''';

      final result = BearFuelImporter.parseCsv(variedCsv, 'test_car_id');

      expect(result.success, isTrue);
      expect(result.validCount, equals(2));
      expect(result.parsedRecords[0].totalPrice, equals(400.0));
      expect(result.parsedRecords[1].unitPrice, equals(8.0));
    });

    test('4. 导出为小熊油耗兼容 CSV 测试', () {
      const sampleCsv = '''时间,当前里程,加油量,单价,金额,是否加满,是否漏记,油品,加油站,备注
2026-01-05 08:30,10000,50.0,8.0,400.0,是,否,92# 汽油,中石化,首充
2026-01-15 08:30,10500,40.0,8.0,320.0,是,否,92# 汽油,中石化,二充''';

      final parseResult = BearFuelImporter.parseCsv(sampleCsv, 'car_1');
      final computed = FuelCalculator.computeRecords(parseResult.parsedRecords);

      final exportedCsv = BearFuelImporter.exportToCsv(computed);
      expect(
        exportedCsv,
        contains(
          '时间,当前里程,加油量,单价,金额,是否加满,是否漏记,油品,加油站,百公里油耗,每公里花费,优惠金额,油量警告灯,备注',
        ),
      );
      expect(exportedCsv, contains('8.00,0.64'));
    });

    test('5. 保留负号并拒绝无效日期，避免导入脏数据', () {
      const csv = '''时间,当前里程,加油量,单价,金额,是否加满,是否漏记,油品,加油站,备注
2026-04-01,12000,-10,8,80,是,否,92#,北京站,有效
不是日期,12100,40,8,320,是,否,92#,北京站,无效''';

      final result = BearFuelImporter.parseCsv(csv, 'car_1');

      expect(result.validCount, equals(0));
      expect(result.skippedCount, equals(2));
    });

    test('6. 导出时正确转义包含逗号和引号的字段', () {
      final record = RefuelRecordModel(
        id: 'record_1',
        vehicleId: 'car_1',
        refuelDate: DateTime(2026, 4, 1, 8, 30),
        mileage: 12000,
        fuelAmount: 40,
        unitPrice: 8,
        totalPrice: 320,
        fuelType: '92# 汽油',
        gasStation: '北京,朝阳"站',
        note: '高速,满载',
      );

      final exportedCsv = BearFuelImporter.exportToCsv([record]);

      expect(exportedCsv, contains('"北京,朝阳""站"'));
      expect(exportedCsv, contains('"高速,满载"'));
    });

    test('7. 缺少单价和金额时不补造油价', () {
      const csv = '''时间,当前里程,加油量,单价,金额,是否加满
2026-05-01,13000,40,,,是''';

      final result = BearFuelImporter.parseCsv(csv, 'car_1');

      expect(result.success, isFalse);
      expect(result.validCount, equals(0));
      expect(result.skippedCount, equals(1));
    });

    test('8. RFC 4180 字段中的逗号、引号和换行可完整往返', () {
      final record = RefuelRecordModel(
        id: 'record_2',
        vehicleId: 'car_1',
        refuelDate: DateTime(2026, 4, 2, 8, 30),
        mileage: 12100,
        fuelAmount: 41,
        unitPrice: 8.1,
        totalPrice: 332.1,
        fuelType: '92# 汽油',
        gasStation: '北京,朝阳"站',
        note: '高速,满载\n夜间到站',
      );

      final exported = BearFuelImporter.exportToCsv([record]);
      final result = BearFuelImporter.parseCsv(exported, 'car_1');

      expect(result.success, isTrue);
      expect(result.validCount, equals(1));
      expect(result.parsedRecords.single.gasStation, equals('北京,朝阳"站'));
      expect(result.parsedRecords.single.note, equals('高速,满载\n夜间到站'));
    });

    test('9. XLSX ZIP 文件明确返回不支持', () {
      final result = BearFuelImporter.parseBytes([
        0x50,
        0x4B,
        0x03,
        0x04,
      ], 'car_1');

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('不支持 XLSX'));
    });
  });
}
