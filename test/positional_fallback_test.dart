import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/domain/bear_fuel_importer.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';

/// P2-03：无表头/乱码表头文件的标准 13 列位置兜底与校验。
///
/// 标准 13 列（与小熊油耗真实导出一致）：
/// 日期时间, 总里程, 机显单价, 加油量, 机显金额, 实付金额,
/// 油号, 加满, 亮灯, 漏记, 油耗, 加油站名称, 备注
void main() {
  // 首行里程 8 与真实样例一致：低里程使特征推导失效，必须走位置兜底
  const row1 =
      '2026-01-05 08:30,8,8.12,48.50,393.82,386.44,92#,是,是,否,8.10,中石化朝阳路站,首充';
  const row2 =
      '2026-01-18 17:45,505,8.15,44.20,360.23,352.98,92#,是,否,否,7.13,中石油北苑站,';
  const row3 =
      '2026-02-02 12:10,1002,8.20,20.00,164.00,164.00,95#,否,否,否,-1.00,壳牌立汤路站,临时补油';

  group('P2-03 标准 13 列位置兜底', () {
    test('无表头标准 13 列文件按位置成功导入', () {
      final result = BearFuelImporter.parseCsv(
        '$row1\n$row2\n$row3',
        'veh_test',
      );

      expect(result.success, isTrue);
      expect(result.validCount, equals(3));
      expect(result.skippedCount, equals(0));

      final first = result.parsedRecords[0];
      expect(first.refuelDate, equals(DateTime(2026, 1, 5, 8, 30)));
      expect(first.mileage, equals(8));
      expect(first.unitPrice, equals(8.12));
      expect(first.fuelAmount, equals(48.5));
      // 实付金额进账本，机显金额与实付金额之差进优惠金额
      expect(first.totalPrice, equals(386.44));
      expect(first.discountAmount, equals(7.38));
      // 亮灯 / 漏记 / 站名 / 备注
      expect(first.fuelWarningLightOn, isTrue);
      expect(result.parsedRecords[1].fuelWarningLightOn, isFalse);
      expect(first.isForgotPrevious, isFalse);
      expect(first.gasStation, equals('中石化朝阳路站'));
      expect(first.note, equals('首充'));
      expect(result.parsedRecords[1].note, isNull);

      // 源油耗列：正常值保留，-1.00 标记为不可用
      expect(first.sourceFuelConsumption, equals(8.1));
      expect(first.sourceDataQuality, equals(SourceDataQuality.reported));
      expect(result.parsedRecords[2].sourceFuelConsumption, isNull);
      expect(
        result.parsedRecords[2].sourceDataQuality,
        equals(SourceDataQuality.unavailable),
      );
    });

    test('乱码表头 + 标准 13 列数据：乱码行跳过，数据完整且金额口径正确', () {
      // 乱码表头 13 个单元格（GBK 误码风格），不含可识别的表头关键词
      const garbageHeader =
          'ÃÕÏÈ,Àï³Ì,µ¥¼Û,ÓÍÁ¿,»úÏÔ½ð¶î,Êµ¸¶½ð¶î,ÓÍºÅ,¼ÓÂú,ÁÁµÆ,Â©¼Ç,ÓÍºÄ,Õ¾Ãû,±¸×¢';
      final result = BearFuelImporter.parseCsv(
        '$garbageHeader\n$row1\n$row2',
        'veh_test',
      );

      expect(result.success, isTrue);
      expect(result.validCount, equals(2));
      // 关键回归：totalPrice 必须是实付金额（386.44），
      // 而不是特征推导会误占的机显金额（393.82）
      expect(result.parsedRecords[0].totalPrice, equals(386.44));
      expect(result.parsedRecords[0].discountAmount, equals(7.38));
      expect(result.parsedRecords[0].fuelWarningLightOn, isTrue);
    });

    test('无表头且首列为 Excel 日期序列数：序列数转换且首行数据不丢失', () {
      // 46023.5 = 2026-01-01 12:00（Excel 序列数）
      const csv =
          '46023.5,8,8.12,48.50,393.82,386.44,92#,是,是,否,8.10,中石化朝阳路站,首充\n'
          '46031.5,505,8.15,44.20,360.23,352.98,92#,是,否,否,7.13,中石油北苑站,';
      final result = BearFuelImporter.parseCsv(csv, 'veh_test');

      expect(result.success, isTrue);
      expect(result.validCount, equals(2));
      expect(
        result.parsedRecords[0].refuelDate,
        equals(DateTime(2026, 1, 1, 12, 0)),
      );
      expect(
        result.parsedRecords[1].refuelDate,
        equals(DateTime(2026, 1, 9, 12, 0)),
      );
      expect(result.parsedRecords[0].mileage, equals(8));
    });
  });

  group('P2-03 位置兜底校验失败必须返回“需要确认列映射”', () {
    test('列数不足 13 且特征推导失败', () {
      // 10 列；所有数值 ≤100 使特征推导找不到里程列（无 >100 的大数）
      const csv = '2026-01-05 08:30,8,8.12,48.50,93.82,86.44,92#,是,否,否';
      final result = BearFuelImporter.parseCsv(csv, 'veh_test');

      expect(result.success, isFalse);
      expect(result.validCount, equals(0));
      expect(result.errorMessage, contains('需要确认列映射'));
    });

    test('13 列但油号列类型不符', () {
      // 第 7 列（油号位置）是“是”而非油号；数值均 ≤100 使特征推导失效
      const csv =
          '2026-01-05 08:30,8,8.12,48.50,93.82,86.44,是,92#,否,否,8.10,站名,备注';
      final result = BearFuelImporter.parseCsv(csv, 'veh_test');

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('需要确认列映射'));
    });

    test('13 列但首列既非文本日期也非 Excel 序列数', () {
      const csv = '不是日期,8,8.12,48.50,393.82,386.44,92#,是,否,否,8.10,站名,备注';
      final result = BearFuelImporter.parseCsv(csv, 'veh_test');

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('需要确认列映射'));
    });

    test('第 13 列之后仍有非空内容时不按标准布局解析', () {
      const csv =
          '2026-01-05 08:30,8,8.12,48.50,93.82,86.44,92#,是,否,否,8.10,站名,备注,多余列';
      final result = BearFuelImporter.parseCsv(csv, 'veh_test');

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('需要确认列映射'));
    });
  });

  group('P2-03 有表头文件不受兜底影响（回归保护）', () {
    test('完整表头的标准 CSV 仍按表头映射解析', () {
      const csv =
          '日期时间,总里程,机显单价,加油量,机显金额,实付金额,油号,加满,亮灯,漏记,油耗,加油站名称,备注\n'
          '$row1';
      final result = BearFuelImporter.parseCsv(csv, 'veh_test');

      expect(result.success, isTrue);
      expect(result.validCount, equals(1));
      expect(result.parsedRecords[0].totalPrice, equals(386.44));
      expect(result.parsedRecords[0].discountAmount, equals(7.38));
    });
  });
}
