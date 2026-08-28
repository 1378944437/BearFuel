import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/core/utils/input_formatters.dart';

void main() {
  group('输入框格式限制器测试 (AppInputFormatters Tests)', () {
    test('1. decimal2 限制器：应严格限制仅允许数值且最多两位小数', () {
      final formatter = AppInputFormatters.decimal2;

      // 允许两位小数
      final val1 = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '123.45'),
      );
      expect(val1.text, '123.45');

      // 拒绝第三位小数
      final val2 = formatter.formatEditUpdate(
        const TextEditingValue(text: '123.45'),
        const TextEditingValue(text: '123.456'),
      );
      expect(val2.text, '123.45'); // 保持原值不变

      // 拒绝非数字字母
      final val3 = formatter.formatEditUpdate(
        const TextEditingValue(text: '12'),
        const TextEditingValue(text: '12a'),
      );
      expect(val3.text, '12');
    });

    test('2. stationName 与 note 限制器：应严格限制最大字符数', () {
      final stationFormatter = AppInputFormatters.stationName;
      final noteFormatter = AppInputFormatters.note;

      final longStation = 'a' * 50;
      final resStation = stationFormatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        TextEditingValue(text: longStation),
      );
      expect(resStation.text.length, 40);

      final longNote = 'b' * 150;
      final resNote = noteFormatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        TextEditingValue(text: longNote),
      );
      expect(resNote.text.length, 100);
    });

    test('3. plateNumber 限制器：应自动转大写并过滤特殊字符', () {
      final formatters = AppInputFormatters.plateNumber;
      var curVal = const TextEditingValue(text: '');

      // 输入小写字母与数字混合
      for (final f in formatters) {
        curVal = f.formatEditUpdate(
          const TextEditingValue(text: ''),
          const TextEditingValue(text: 'ad12345'),
        );
      }
      expect(curVal.text, 'AD12345');
    });
  });
}
