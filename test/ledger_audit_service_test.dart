import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/data/services/apizero_fuel_price_service.dart';
import 'package:bearfuel/domain/fuel_price_service.dart';
import 'package:bearfuel/domain/ledger_audit_service.dart';

RefuelRecordModel record({
  String id = 'r1',
  required DateTime date,
  required double mileage,
  required double amount,
  required double price,
  required double total,
  bool full = true,
  bool forgot = false,
}) {
  return RefuelRecordModel(
    id: id,
    vehicleId: 'car_1',
    refuelDate: date,
    mileage: mileage,
    fuelAmount: amount,
    unitPrice: price,
    totalPrice: total,
    fuelType: '92# 汽油',
    isFullTank: full,
    isForgotPrevious: forgot,
  );
}

List<RuleFinding> run(
  List<RefuelRecordModel> records, {
  double? tankCapacity,
  ApiZeroFuelPriceSnapshot? priceSnapshot,
}) {
  return LedgerAuditService.runLocalRules(
    records: records,
    dataHashOf: LedgerAuditService.hashRecord,
    tankCapacity: tankCapacity,
    priceSnapshot: priceSnapshot,
    now: DateTime(2026, 8, 29, 12),
  );
}

void main() {
  group('账本本地规则审查 (LedgerAuditService)', () {
    test('金额与量价不匹配时给出建议值', () {
      final findings = run([
        record(
          id: 'bad',
          date: DateTime(2026, 8, 1),
          mileage: 10000,
          amount: 40,
          price: 8,
          total: 300, // 应为 320
        ),
      ]);
      final finding = findings.firstWhere(
        (f) => f.findingType == LedgerFindingType.amountMismatch,
      );
      expect(finding.severity, 'warning');
      expect(finding.suggestedChanges.first['suggested'], closeTo(320.0, 0.01));
    });

    test('金额误差在 0.02 元内不报警', () {
      final findings = run([
        record(
          id: 'ok',
          date: DateTime(2026, 8, 1),
          mileage: 10000,
          amount: 40,
          price: 8.0,
          total: 320.01,
        ),
      ]);
      expect(
        findings.where(
          (f) => f.findingType == LedgerFindingType.amountMismatch,
        ),
        isEmpty,
      );
    });

    test('里程回退与重复里程分别提示', () {
      final findings = run([
        record(
          id: 'a',
          date: DateTime(2026, 8, 1),
          mileage: 10500,
          amount: 40,
          price: 8,
          total: 320,
        ),
        record(
          id: 'b',
          date: DateTime(2026, 8, 8),
          mileage: 10400, // 回退
          amount: 40,
          price: 8,
          total: 320,
        ),
        record(
          id: 'c',
          date: DateTime(2026, 8, 15),
          mileage: 10400, // 与上一条相同
          amount: 40,
          price: 8,
          total: 320,
        ),
      ]);
      expect(
        findings.any((f) => f.findingType == LedgerFindingType.mileageDecrease),
        isTrue,
      );
      expect(
        findings.any(
          (f) => f.findingType == LedgerFindingType.mileageDuplicate,
        ),
        isTrue,
      );
    });

    test('完全相同的相邻记录提示疑似重复', () {
      final findings = run([
        record(
          id: 'a',
          date: DateTime(2026, 8, 1, 10),
          mileage: 10000,
          amount: 40,
          price: 8,
          total: 320,
        ),
        record(
          id: 'b',
          date: DateTime(2026, 8, 1, 10, 0, 30),
          mileage: 10000,
          amount: 40,
          price: 8,
          total: 320,
        ),
      ]);
      expect(
        findings.where(
          (f) => f.findingType == LedgerFindingType.duplicateRecord,
        ),
        hasLength(1),
      );
    });

    test('加油量超过油箱容量 1.1 倍时提示', () {
      final findings = run([
        record(
          id: 'big',
          date: DateTime(2026, 8, 1),
          mileage: 10000,
          amount: 60,
          price: 8,
          total: 480,
        ),
      ], tankCapacity: 50);
      expect(
        findings.any((f) => f.findingType == LedgerFindingType.tankOverflow),
        isTrue,
      );
    });

    test('单价与接口价格差异超阈值且日期相邻时提示', () {
      final snapshot = ApiZeroFuelPriceSnapshot(
        province: '湖北',
        price: ProvinceFuelPrice(
          province: '湖北',
          gas92: 7.79,
          gas95: 8.35,
          gas98: 9.0,
          diesel0: 7.4,
          lastChangeAmount: 0,
          lastChangeDate: DateTime(2026, 8, 20),
        ),
        fetchedAt: DateTime(2026, 8, 28),
        sourceUrl: 'https://example.com',
      );
      final findings = run([
        record(
          id: 'cheap',
          date: DateTime(2026, 8, 25),
          mileage: 10000,
          amount: 40,
          price: 7.20, // 与 7.79 相差 0.59
          total: 288,
        ),
      ], priceSnapshot: snapshot);
      final finding = findings.firstWhere(
        (f) => f.findingType == LedgerFindingType.unitPriceDifference,
      );
      expect(finding.severity, 'info');
      expect(finding.evidence?['reference_value'], 7.79);
    });

    test('生效期之前的账单不做价格对比（调价周期误报回归）', () {
      // 账单日期（08-15）早于接口价格生效日期（08-20）：
      // 该账单执行的是上一轮价格，不应与新一轮价格比较
      final snapshot = ApiZeroFuelPriceSnapshot(
        province: '湖北',
        price: ProvinceFuelPrice(
          province: '湖北',
          gas92: 8.10,
          gas95: 8.6,
          gas98: 9.2,
          diesel0: 7.8,
          lastChangeAmount: 0.31,
          lastChangeDate: DateTime(2026, 8, 20),
        ),
        fetchedAt: DateTime(2026, 8, 29),
        sourceUrl: 'https://example.com',
      );
      final findings = run([
        record(
          id: 'old_price',
          date: DateTime(2026, 8, 15),
          mileage: 10000,
          amount: 40,
          price: 7.79, // 上一轮价格：与本轮 8.10 差 0.31，属正常
          total: 311.6,
        ),
      ], priceSnapshot: snapshot);
      expect(
        findings.where(
          (f) => f.findingType == LedgerFindingType.unitPriceDifference,
        ),
        isEmpty,
      );
    });

    test('油耗偏离个人中位数时提示（≥2 个有效样本）', () {
      final findings = run([
        record(
          id: 'a',
          date: DateTime(2026, 7, 1),
          mileage: 10000,
          amount: 40,
          price: 8,
          total: 320,
        ),
        record(
          id: 'b',
          date: DateTime(2026, 7, 15),
          mileage: 10500,
          amount: 40,
          price: 8,
          total: 320,
        ),
        record(
          id: 'c',
          date: DateTime(2026, 8, 1),
          mileage: 11000,
          amount: 40,
          price: 8,
          total: 320,
        ),
      ]);
      // 上面三条是理论满箱序列（无消费计算结果），手动构造消费值
      for (final f in findings) {
        expect(f.findingType, isNot(LedgerFindingType.consumptionAnomaly));
      }

      final withConsumption = [
        record(
          id: 'a',
          date: DateTime(2026, 7, 1),
          mileage: 10000,
          amount: 40,
          price: 8,
          total: 320,
        ),
        record(
          id: 'b',
          date: DateTime(2026, 7, 15),
          mileage: 10500,
          amount: 40,
          price: 8,
          total: 320,
        ),
        record(
          id: 'c',
          date: DateTime(2026, 8, 1),
          mileage: 11000,
          amount: 40,
          price: 8,
          total: 320,
        ),
      ];
      withConsumption[0].fuelConsumption = 7.0;
      withConsumption[1].fuelConsumption = 7.0;
      withConsumption[2].fuelConsumption = 13.0; // 中位数 7.0 的 1.35 倍为 9.45
      final anomalyFindings = run(withConsumption);
      expect(
        anomalyFindings.any(
          (f) => f.findingType == LedgerFindingType.consumptionAnomaly,
        ),
        isTrue,
      );
    });

    test('未来日期提示', () {
      final findings = run([
        record(
          id: 'future',
          date: DateTime(2026, 9, 15),
          mileage: 10000,
          amount: 40,
          price: 8,
          total: 320,
        ),
      ]);
      expect(
        findings.any((f) => f.findingType == LedgerFindingType.futureDate),
        isTrue,
      );
    });

    test('数据指纹稳定且随内容变化', () {
      final a = record(
        id: 'x',
        date: DateTime(2026, 8, 1),
        mileage: 10000,
        amount: 40,
        price: 8,
        total: 320,
      );
      final b = record(
        id: 'x',
        date: DateTime(2026, 8, 1),
        mileage: 10000,
        amount: 40,
        price: 8,
        total: 320,
      );
      final c = record(
        id: 'x',
        date: DateTime(2026, 8, 1),
        mileage: 10001,
        amount: 40,
        price: 8,
        total: 320,
      );
      expect(
        LedgerAuditService.hashRecord(a),
        equals(LedgerAuditService.hashRecord(b)),
      );
      expect(
        LedgerAuditService.hashRecord(a),
        isNot(equals(LedgerAuditService.hashRecord(c))),
      );
    });

    test('正常账本不产生发现', () {
      final findings = run([
        record(
          id: 'a',
          date: DateTime(2026, 8, 1, 10),
          mileage: 10000,
          amount: 40,
          price: 7.79,
          total: 311.6,
        ),
        record(
          id: 'b',
          date: DateTime(2026, 8, 15, 9),
          mileage: 10500,
          amount: 40,
          price: 7.79,
          total: 311.6,
        ),
      ]);
      expect(findings, isEmpty);
    });
  });
}
