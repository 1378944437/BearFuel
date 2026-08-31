import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/domain/bear_fuel_importer.dart';
import 'package:bearfuel/domain/fuel_calculator.dart';

/// 阶段一：数值、布尔与日期不再被静默转换的回归测试。
///
/// 覆盖 P2-05（未知布尔）、P2-06（混合脏值）、P2-12（非法日期）。
void main() {
  const header = '日期时间,总里程,机显单价,加油量,机显金额,实付金额,油号,加满,亮灯,漏记';

  ImportResult parse(String body) {
    return BearFuelImporter.parseCsv('$header\n$body', 'veh_test');
  }

  RefuelRecordModel base({
    required DateTime date,
    double mileage = 10000,
    double fuelAmount = 40,
    double unitPrice = 8,
    double totalPrice = 320,
    double? sourceFuelConsumption,
    String? sourceDataQuality,
  }) {
    return RefuelRecordModel(
      id: 'fixed-id',
      vehicleId: 'veh_test',
      refuelDate: date,
      mileage: mileage,
      fuelAmount: fuelAmount,
      unitPrice: unitPrice,
      totalPrice: totalPrice,
      fuelType: '92#',
      sourceFuelConsumption: sourceFuelConsumption,
      sourceDataQuality: sourceDataQuality,
    );
  }

  group('P2-06 数字解析拒绝混合脏值', () {
    test('中间夹字母的混合值不再被拼成有效数字', () {
      // 里程写成 12abc34：旧实现会剥离字母得到 1234 并成功导入
      final result = parse(
        '2026-01-01 08:00,12abc34,8.00,40.00,320.00,320.00,92#,是,否,否',
      );
      expect(result.validCount, equals(0));
      expect(result.skippedCount, equals(1));
    });

    test('多个小数点视为脏值', () {
      final result = parse(
        '2026-01-01 08:00,10000,8.00,4.0.0,320.00,320.00,92#,是,否,否',
      );
      expect(result.validCount, equals(0));
    });

    test('引号包裹的千分位里程可以解析', () {
      final result = parse(
        '2026-01-01 08:00,"12,500.5",8.00,40.00,320.00,320.00,92#,是,否,否',
      );
      expect(result.validCount, equals(1));
      expect(result.parsedRecords.single.mileage, equals(12500.5));
    });

    test('货币符号前缀与单位后缀可以解析', () {
      final result = parse(
        '2026-01-01 08:00,10000,"¥8.00","40.00L","¥320.00","320.00元",92#,是,否,否',
      );
      expect(result.validCount, equals(1));
      expect(result.parsedRecords.single.unitPrice, equals(8.0));
      expect(result.parsedRecords.single.fuelAmount, equals(40.0));
      expect(result.parsedRecords.single.totalPrice, equals(320.0));
    });

    test('标准格式记录正常解析', () {
      final result = parse(
        '2026-01-01 08:00,10000,8.00,40.00,320.00,320.00,92#,是,否,否',
      );
      expect(result.validCount, equals(1));
      expect(result.parsedRecords.single.mileage, equals(10000));
      expect(result.parsedRecords.single.unitPrice, equals(8.0));
    });
  });

  group('P2-05 未知布尔值不再静默变成确定值', () {
    test('无法识别的"是否加满"会产生告警', () {
      final result = parse(
        '2026-01-01 08:00,10000,8.00,40.00,320.00,320.00,92#,maybe,否,否',
      );
      expect(result.validCount, equals(1));
      expect(
        result.warnings.any(
          (w) =>
              w.kind == ImportWarningKind.unknownBoolean &&
              w.field == '是否加满' &&
              w.rawValue == 'maybe',
        ),
        isTrue,
      );
    });

    test('明确的"否"不产生告警', () {
      final result = parse(
        '2026-01-01 08:00,10000,8.00,40.00,320.00,320.00,92#,否,否,否',
      );
      expect(result.warnings, isEmpty);
    });

    test('无法识别的"是否漏记"会产生告警', () {
      final result = parse(
        '2026-01-01 08:00,10000,8.00,40.00,320.00,320.00,92#,是,否,???',
      );
      expect(
        result.warnings.any(
          (w) =>
              w.kind == ImportWarningKind.unknownBoolean && w.field == '是否漏记',
        ),
        isTrue,
      );
    });
  });

  group('P2-02 缺失单价的推算必须留痕', () {
    test('由总价反推单价时产生 derivedValue 告警', () {
      final result = parse(
        '2026-01-01 08:00,10000,,40.00,320.00,320.00,92#,是,否,否',
      );
      expect(result.validCount, equals(1));
      expect(result.parsedRecords.single.unitPrice, equals(8.0));
      expect(
        result.warnings.any(
          (w) => w.kind == ImportWarningKind.derivedValue && w.field == '单价',
        ),
        isTrue,
      );
    });

    test('由单价推算总价时同样留痕', () {
      final result = parse('2026-01-01 08:00,10000,8.00,40.00,,,,是,否,否');
      expect(
        result.warnings.any(
          (w) => w.kind == ImportWarningKind.derivedValue && w.field == '实付金额',
        ),
        isTrue,
      );
    });
  });

  group('P2-01 源油耗与本地重算值分离', () {
    const withConsumptionHeader = '日期时间,总里程,机显单价,加油量,机显金额,实付金额,油号,加满,亮灯,漏记,油耗';

    ImportResult parseWithConsumption(String body) {
      return BearFuelImporter.parseCsv(
        '$withConsumptionHeader\n$body',
        'veh_test',
      );
    }

    test('源文件给出的油耗值被保留且标记为 reported', () {
      final result = parseWithConsumption(
        '2026-01-01 08:00,10000,8.00,40.00,320.00,320.00,92#,是,否,否,7.50',
      );
      final r = result.parsedRecords.single;
      expect(r.sourceFuelConsumption, equals(7.5));
      expect(r.sourceDataQuality, equals(SourceDataQuality.reported));
    });

    test('-1.00 记为不可用而不是真实油耗', () {
      final result = parseWithConsumption(
        '2026-01-01 08:00,10000,8.00,40.00,320.00,320.00,92#,是,否,否,-1.00',
      );
      final r = result.parsedRecords.single;
      expect(r.sourceFuelConsumption, isNull);
      expect(r.sourceDataQuality, equals(SourceDataQuality.unavailable));
      expect(SourceDataQuality.isUnusable(r.sourceDataQuality), isTrue);
    });

    test('"数据丢失，预估"记为 estimated', () {
      final result = parseWithConsumption(
        '2026-01-01 08:00,10000,8.00,40.00,320.00,320.00,92#,是,否,否,数据丢失，预估',
      );
      final r = result.parsedRecords.single;
      expect(r.sourceDataQuality, equals(SourceDataQuality.estimated));
      expect(SourceDataQuality.isUnusable(r.sourceDataQuality), isTrue);
    });

    test('源油耗不会被本地重算值覆盖', () async {
      final result = parseWithConsumption(
        '2026-01-01 08:00,10000,8.00,40.00,320.00,320.00,92#,是,否,否,7.50'
        '\n2026-01-20 08:00,10500,8.00,45.00,360.00,360.00,92#,是,否,否,9.99',
      );
      final computed = FuelCalculator.computeRecords(result.parsedRecords);
      final second = computed.last;
      // 本地按周期重算：本周期只计第二次加满的 45 L / 500 km = 9.00 L/100km
      // （首箱的 40 L 属上一周期消耗，不重复计入）
      expect(second.fuelConsumption, equals(9.0));
      // 源值保持独立，未被本地重算的 9.00 覆盖
      expect(second.sourceFuelConsumption, equals(9.99));
    });

    test('导出再导入可保留源油耗与质量标记', () {
      final record = base(
        date: DateTime(2026, 1, 1),
        sourceFuelConsumption: 7.5,
        sourceDataQuality: SourceDataQuality.reported,
      );
      final csv = BearFuelImporter.exportToCsv([record]);
      final result = BearFuelImporter.parseCsv(csv, 'veh_test');

      expect(result.validCount, equals(1));
      expect(result.parsedRecords.single.sourceFuelConsumption, equals(7.5));
      expect(
        result.parsedRecords.single.sourceDataQuality,
        equals(SourceDataQuality.reported),
      );
    });
  });

  group('日期格式与模型可空字段', () {
    test('支持斜杠日期和中文日期', () {
      final slash = parse('2026/08/31 08:00,10000,8,40,320,320,92#,是,否,否');
      final chinese = parse('2026年08月31日 08:00,10000,8,40,320,320,92#,是,否,否');
      expect(slash.validCount, 1);
      expect(chinese.validCount, 1);
      expect(slash.parsedRecords.single.refuelDate.month, 8);
      expect(chinese.parsedRecords.single.refuelDate.day, 31);
    });

    test('否定词不会被正向关键词误判', () {
      final result = parse('2026-01-01 08:00,10000,8,40,320,320,92#,不满,不亮,未漏');
      final record = result.parsedRecords.single;
      expect(record.isFullTank, isFalse);
      expect(record.isForgotPrevious, isFalse);
      expect(record.fuelWarningLightOn, isFalse);
    });

    test('copyWith 可以显式清空可空字段', () {
      final original =
          base(
            date: DateTime(2026, 1, 1),
            sourceFuelConsumption: 7.5,
            sourceDataQuality: SourceDataQuality.reported,
          ).copyWith(
            gasStation: '站点',
            note: '备注',
            discountAmount: 3,
            fuelConsumption: 8,
            costPerKm: 0.5,
            distance: 100,
          );
      final cleared = original.copyWith(
        gasStation: null,
        note: null,
        discountAmount: null,
        fuelConsumption: null,
        costPerKm: null,
        distance: null,
        sourceFuelConsumption: null,
        sourceDataQuality: null,
      );
      expect(cleared.gasStation, isNull);
      expect(cleared.note, isNull);
      expect(cleared.discountAmount, isNull);
      expect(cleared.fuelConsumption, isNull);
      expect(cleared.costPerKm, isNull);
      expect(cleared.distance, isNull);
      expect(cleared.sourceFuelConsumption, isNull);
      expect(cleared.sourceDataQuality, isNull);
    });
  });
  group('P2-12 非法日期不再伪装成当前时间', () {
    test('越界 ISO 日期被拒绝而不是自动进位', () {
      final result = parse('2026-02-30 08:00,10000,8,40,320,320,92#,是,否,否');
      expect(result.validCount, 0);
      expect(result.skippedCount, 1);
    });

    test('Excel 序列下限外的普通数字不会被当作日期', () {
      final result = parse('1234,10000,8,40,320,320,92#,是,否,否');
      expect(result.validCount, 0);
    });
    test('fromMap 解析失败时打上 hasInvalidDate 标记', () {
      final record = RefuelRecordModel.fromMap({
        ...base(date: DateTime(2026, 1, 1)).toMap(),
        'refuel_date': 'not-a-date',
      });
      expect(record.hasInvalidDate, isTrue);
    });

    test('合法日期不带标记', () {
      final record = RefuelRecordModel.fromMap(
        base(date: DateTime(2026, 1, 1)).toMap(),
      );
      expect(record.hasInvalidDate, isFalse);
    });

    test('标记不写入数据库字段', () {
      final map = base(date: DateTime(2026, 1, 1)).toMap();
      expect(map.containsKey('has_invalid_date'), isFalse);
    });
  });
}
