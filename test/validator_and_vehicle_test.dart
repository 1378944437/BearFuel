import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/core/utils/validators.dart';
import 'package:bearfuel/data/models/vehicle_model.dart';

void main() {
  group('校验器与车辆档案模型测试 (Validators & VehicleModel Tests)', () {
    test('1. 非负数校验器测试 (支持初始里程为 0.0 或 0)', () {
      expect(Validators.nonNegativeNumber('0', fieldName: '初始里程'), isNull);
      expect(Validators.nonNegativeNumber('0.0', fieldName: '初始里程'), isNull);
      expect(Validators.nonNegativeNumber('1250.5', fieldName: '初始里程'), isNull);
      expect(Validators.nonNegativeNumber('-1', fieldName: '初始里程'), isNotNull);
      expect(Validators.nonNegativeNumber('', fieldName: '初始里程'), isNotNull);
      expect(Validators.nonNegativeNumber('abc', fieldName: '初始里程'), isNotNull);
    });

    test('2. 正数校验器测试 (油箱容积必须 > 0)', () {
      expect(Validators.positiveNumber('50', fieldName: '油箱容积'), isNull);
      expect(Validators.positiveNumber('50.5', fieldName: '油箱容积'), isNull);
      expect(Validators.positiveNumber('0', fieldName: '油箱容积'), isNotNull);
      expect(Validators.positiveNumber('-10', fieldName: '油箱容积'), isNotNull);
    });

    test('3. 车辆实体模型映射与序列化测试', () {
      final v = VehicleModel(
        id: 'car-123',
        name: '我的领克03',
        plateNumber: '鄂S·88888',
        brand: '领克',
        model: '03 2.0T Pro',
        tankCapacity: 50.0,
        initialMileage: 0.0,
        defaultFuelType: '95# 汽油',
        isDefault: true,
      );

      final map = v.toMap();
      expect(map['id'], equals('car-123'));
      expect(map['name'], equals('我的领克03'));
      expect(map['initial_mileage'], equals(0.0));
      expect(map['is_default'], equals(1));

      final restored = VehicleModel.fromMap(map);
      expect(restored.id, equals(v.id));
      expect(restored.name, equals(v.name));
      expect(restored.initialMileage, equals(0.0));
      expect(restored.isDefault, isTrue);
    });
  });
}
