import 'dart:convert';
import 'dart:typed_data';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:uuid/uuid.dart';
import '../data/models/refuel_record_model.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/date_formatter.dart';

/// 导入告警：数据已成功入库，但某些字段的值并非原始事实。
///
/// 与"跳过整行"不同，告警行会被导入，只是把推算、缺失或无法识别的
/// 字段明确告知用户，避免派生值被当成原始值。
class ImportWarning {
  /// 1 起的行号（含表头，与用户在表格软件中看到的行号一致）
  final int line;

  /// 取值见 [ImportWarningKind]
  final String kind;

  /// 相关字段名
  final String field;

  /// 原始文本，便于用户回到原文件核对
  final String rawValue;

  /// 无法识别时实际采用的默认值（P2-05：文案必须与真实处理一致）
  final String? defaultValue;

  const ImportWarning({
    required this.line,
    required this.kind,
    required this.field,
    this.rawValue = '',
    this.defaultValue,
  });

  String get description {
    final shown = rawValue.isEmpty ? '(空)' : rawValue;
    switch (kind) {
      case ImportWarningKind.derivedValue:
        return '第 $line 行「$field」缺失，已由其他字段推算（$shown）';
      case ImportWarningKind.unknownBoolean:
        final applied = defaultValue ?? '否';
        return '第 $line 行「$field」无法识别为是/否，已按"$applied"处理（$shown）';
      case ImportWarningKind.unparseableNumber:
        return '第 $line 行「$field」不是有效数字，已跳过该字段（$shown）';
      default:
        return '第 $line 行「$field」：$kind（$shown）';
    }
  }
}

/// 告警类型常量
class ImportWarningKind {
  /// 字段缺失后由其他字段推算
  static const derivedValue = 'derived_value';

  /// 是否类字段无法识别
  static const unknownBoolean = 'unknown_boolean';

  /// 数字字段无法解析
  static const unparseableNumber = 'unparseable_number';

  /// 非枚举值或其他无法安全归一化的字段
  static const unknownValue = 'unknown_value';
}

/// 导入解析结果模型
class ImportResult {
  final bool success;
  final int totalCount;
  final int validCount;
  final int skippedCount;
  final String? errorMessage;
  final List<RefuelRecordModel> parsedRecords;

  /// 需要用户知晓的可疑数据，不影响入库但必须在导入报告展示
  final List<ImportWarning> warnings;

  ImportResult({
    required this.success,
    this.totalCount = 0,
    this.validCount = 0,
    this.skippedCount = 0,
    this.errorMessage,
    this.parsedRecords = const [],
    this.warnings = const [],
  });
}

/// 小熊油耗数据导入与导出引擎（支持 .csv, .xls, .tsv, .txt）
class BearFuelImporter {
  static const int _maxXlsBytes = 20 * 1024 * 1024;
  static const int _maxXlsRows = 10000;
  static const int _maxXlsColumns = 128;

  /// 解析从手机本地文件读取的原始字节流（智能识别 XLS 格式与 UTF-8 / GBK 编码文本）
  static ImportResult parseBytes(List<int> bytes, String vehicleId) {
    if (bytes.isEmpty) {
      return ImportResult(success: false, errorMessage: '选取的导入文件为空');
    }
    if (bytes.length > _maxXlsBytes) {
      return ImportResult(
        success: false,
        errorMessage: '文件超过 20 MB 安全上限，请拆分后再导入',
      );
    }

    // XLSX is a ZIP container and is not parsed by this Dart-only importer.
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return ImportResult(
        success: false,
        errorMessage: '暂不支持 XLSX 文件，请另存为 CSV 或 XLS 后再导入',
      );
    }

    // 1. 检查是否为 Microsoft Excel 二进制文件 (.xls / CFB BIFF8 格式)
    if (_isCfbExcel(bytes)) {
      try {
        final rows = _parseCfbXls(bytes);
        if (rows != null && rows.isNotEmpty) {
          _convertXlsDateColumn(rows);
          return _parseRows(rows, vehicleId);
        }
        return ImportResult(
          success: false,
          errorMessage: 'XLS 文件无法解析：仅支持有效的 BIFF8 工作簿，请另存为标准 CSV 后重试',
        );
      } catch (e) {
        return ImportResult(
          success: false,
          errorMessage: 'XLS 文件结构损坏或暂不兼容：$e，请另存为标准 CSV 后重试',
        );
      }
    }

    // 2. 尝试使用 UTF-8 解码（跳过 UTF-8 BOM）
    String content = '';
    try {
      if (bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF) {
        content = utf8.decode(bytes.sublist(3));
      } else {
        content = utf8.decode(bytes);
      }
    } catch (_) {
      // UTF-8 解码失败时按 GBK 重试（中文 Windows Excel 另存的默认 ANSI 编码）
      try {
        content = gbk_bytes.decode(bytes);
      } catch (_) {
        return ImportResult(
          success: false,
          errorMessage: '文件编码无法识别，请另存为 UTF-8 CSV 后再导入',
        );
      }
    }

    return parseCsv(content, vehicleId);
  }

  /// Excel 日期序列数上下界（约 1954-09-18 至 2099-12-31）
  static const double _excelSerialMin = 20000;
  static const double _excelSerialMax = 73050;

  /// .xls 中日期单元格以 Excel 序列数存储（如 45210.5），
  /// 仅当表头明确为日期列时把该列的序列数转换为日期文本，
  /// 避免里程等普通数值列被误判转换。
  static void _convertXlsDateColumn(List<List<String>> rows) {
    if (rows.isEmpty) return;
    final header = rows.first;
    for (int c = 0; c < header.length; c++) {
      final h = header[c].trim().toLowerCase();
      final isDateCol =
          h.contains('时间') || h.contains('日期') || h == 'date' || h == 'time';
      if (!isDateCol) continue;
      for (int r = 1; r < rows.length; r++) {
        if (c >= rows[r].length) continue;
        final cell = rows[r][c].trim();
        if (cell.isEmpty) continue;
        if (DateFormatter.tryParse(cell) != null) continue;
        final serial = double.tryParse(cell);
        if (serial == null ||
            serial < _excelSerialMin ||
            serial > _excelSerialMax) {
          continue;
        }
        rows[r][c] = _formatExcelSerial(serial);
      }
    }
  }

  /// 把 Excel 日期序列数格式化为 "yyyy-MM-dd HH:mm" 文本
  static String _formatExcelSerial(double serial) {
    final days = serial.floor();
    final frac = serial - days;
    final dt = DateTime(
      1899,
      12,
      30,
    ).add(Duration(days: days, minutes: (frac * 24 * 60).round()));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  /// 解析小熊油耗 CSV/TSV 文本格式字符串
  static ImportResult parseCsv(String csvContent, String vehicleId) {
    if (csvContent.trim().isEmpty) {
      return ImportResult(success: false, errorMessage: 'CSV 内容为空');
    }

    try {
      final content = csvContent
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      final lines = _splitCsvRecords(
        content,
      ).where((e) => e.trim().isNotEmpty).toList();

      if (lines.isEmpty) {
        return ImportResult(success: false, errorMessage: '未读取到有效行数据');
      }

      // 自动嗅探分隔符（逗号、制表符、分号）
      final delimiter = _detectDelimiter(lines.first);
      final List<List<String>> rows = lines
          .map((line) => _splitCsvLine(line, delimiter: delimiter))
          .toList();

      return _parseRows(rows, vehicleId);
    } catch (e) {
      return ImportResult(success: false, errorMessage: '解析 CSV 异常: $e');
    }
  }

  /// 统一解析二维表格数据行列表
  static ImportResult _parseRows(List<List<String>> rows, String vehicleId) {
    if (rows.isEmpty) {
      return ImportResult(success: false, errorMessage: '数据表格为空');
    }

    // 1. 尝试从首行解析表头映射
    final headers = rows.first;
    var colMap = _detectColumns(headers);

    int startIndex = 1;
    var usedHeuristic = false;

    // 2. 若首行表头匹配不完整（如 Excel/CSV 无表头或表头乱码），尝试位置推导与特征匹配
    if (!colMap.containsKey('mileage') || !colMap.containsKey('fuelAmount')) {
      // 检查首行是否其实就是数据行（例如首列就是日期时间）
      final isFirstRowData = DateFormatter.tryParse(headers.first) != null;
      if (isFirstRowData) {
        startIndex = 0;
        colMap = _heuristicDetectColumns(rows.first);
        usedHeuristic = true;
      } else if (rows.length > 1) {
        // 首行是乱码表头，根据第二行数据特征自动推导列索引
        colMap = _heuristicDetectColumns(rows[1]);
        usedHeuristic = true;
      }
    }

    // 3. 位置兜底：表头不可信（核心列仍缺失，或列位置来自样本推导）时，
    //    校验文件是否严格符合标准小熊油耗 13 列布局。校验必须全部通过
    //    （列数、样本值、字段类型），才允许按标准列位置映射；核心列
    //    缺失且校验不通过时返回“需要确认列映射”，不允许静默跳行。
    final coreColumnsComplete =
        colMap.containsKey('date') &&
        colMap.containsKey('mileage') &&
        colMap.containsKey('fuelAmount');
    if (!coreColumnsComplete || usedHeuristic) {
      final fallback = _standardColumnFallback(rows, startIndex);
      if (fallback != null) {
        colMap = fallback.columnMap;
        startIndex = fallback.startIndex;
      } else if (!coreColumnsComplete) {
        return ImportResult(
          success: false,
          errorMessage:
              '无法识别表格的列结构，需要确认列映射：'
              '无表头文件必须严格符合小熊油耗标准 13 列格式，'
              '或请为文件补充表头行后再导入',
        );
      }
      // 核心列完整但不符合标准 13 列布局：保留样本推导结果，
      // 非标准布局仍可自洽解析（行为与旧版本一致）。
    }

    if (!colMap.containsKey('mileage') || !colMap.containsKey('fuelAmount')) {
      return ImportResult(
        success: false,
        errorMessage: '表格缺少核心列（必须包含“当前里程”和“加油量/升数”）',
      );
    }

    final List<RefuelRecordModel> parsedList = [];
    final List<ImportWarning> warnings = [];
    int skipped = 0;

    // 3. 逐行提取解析数据
    for (int i = startIndex; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((c) => c.trim().isEmpty)) continue;

      try {
        // 里程
        final mileageStr = _getColValue(row, colMap['mileage']);
        final mileage = _parseNumber(mileageStr);
        if (mileage == null || mileage < 0) {
          skipped++;
          continue;
        }

        // 加油量
        final amountStr = _getColValue(row, colMap['fuelAmount']);
        final fuelAmount = _parseNumber(amountStr);
        if (fuelAmount == null || fuelAmount <= 0) {
          skipped++;
          continue;
        }

        // 时间
        final dateStr = _getColValue(row, colMap['date']);
        final parsedDate = DateFormatter.tryParse(dateStr);
        // 有日期列但内容无效时跳过该行，避免把历史记录伪装成当前记录。
        if (colMap.containsKey('date') && parsedDate == null) {
          skipped++;
          continue;
        }
        final refuelDate = parsedDate;
        if (refuelDate == null) {
          // 没有日期或日期无法解析时拒绝该行，禁止伪造为当前时间。
          skipped++;
          continue;
        }

        // 单价与总价。小熊油耗导出同时有“机显金额”和“实付金额”，
        // 总价必须优先使用实付金额；机显金额仅用于推导优惠金额。
        final priceStr = _getColValue(row, colMap['unitPrice']);
        final totalStr = _getColValue(row, colMap['totalPrice']);
        final displayTotalStr = _getColValue(row, colMap['displayTotalPrice']);
        double unitPrice = _parseNumber(priceStr) ?? 0.0;
        double totalPrice = _parseNumber(totalStr) ?? 0.0;
        final displayTotalPrice = _parseNumber(displayTotalStr);

        // 推算出的价格必须留痕：这是派生值，不是原始事实。
        if (totalPrice <= 0 && unitPrice > 0) {
          totalPrice = double.parse(
            (fuelAmount * unitPrice).toStringAsFixed(2),
          );
          warnings.add(
            ImportWarning(
              line: i + 1,
              kind: ImportWarningKind.derivedValue,
              field: '实付金额',
              rawValue:
                  '${fuelAmount.toStringAsFixed(2)} L × '
                  '${unitPrice.toStringAsFixed(2)} 元/L = '
                  '${totalPrice.toStringAsFixed(2)} 元',
            ),
          );
        } else if (unitPrice <= 0 && totalPrice > 0) {
          unitPrice = double.parse(
            (totalPrice / fuelAmount).toStringAsFixed(2),
          );
          warnings.add(
            ImportWarning(
              line: i + 1,
              kind: ImportWarningKind.derivedValue,
              field: '单价',
              rawValue:
                  '${totalPrice.toStringAsFixed(2)} 元 ÷ '
                  '${fuelAmount.toStringAsFixed(2)} L = '
                  '${unitPrice.toStringAsFixed(2)} 元/L',
            ),
          );
        } else if (unitPrice <= 0 && totalPrice <= 0) {
          // 缺少价格时不能使用固定示例值，否则会把导入数据伪装成真实账目。
          skipped++;
          continue;
        }

        // 是否加满。空值沿用"是"，但必须告警，因为加满是油耗周期的基准点。
        final fullStr = _getColValue(row, colMap['isFullTank'])?.toLowerCase();
        late final bool isFullTank;
        if (fullStr == null || fullStr.isEmpty) {
          isFullTank = true;
        } else if (fullStr.contains('否') ||
            fullStr.contains('不') ||
            fullStr == '0' ||
            fullStr.contains('未') ||
            fullStr.contains('没') ||
            fullStr == 'false' ||
            fullStr == 'no') {
          isFullTank = false;
        } else if (fullStr.contains('是') ||
            fullStr == '1' ||
            fullStr.contains('满') ||
            fullStr == 'true' ||
            fullStr == 'yes') {
          isFullTank = true;
        } else {
          // 无法识别：默认按加满处理并告警，不静默当作确定值。
          isFullTank = true;
          warnings.add(
            ImportWarning(
              line: i + 1,
              kind: ImportWarningKind.unknownBoolean,
              field: '是否加满',
              rawValue: fullStr,
              defaultValue: '是',
            ),
          );
        }

        // 是否漏记。空值视作"否"，无法识别时同样告警。
        final forgotStr = _getColValue(
          row,
          colMap['isForgotPrevious'],
        )?.toLowerCase();
        late final bool isForgotPrevious;
        if (forgotStr == null || forgotStr.isEmpty) {
          isForgotPrevious = false;
        } else if (forgotStr.contains('否') ||
            forgotStr.contains('不') ||
            forgotStr == '0' ||
            forgotStr.contains('未') ||
            forgotStr.contains('没') ||
            forgotStr == 'false' ||
            forgotStr == 'no') {
          isForgotPrevious = false;
        } else if (forgotStr.contains('是') ||
            forgotStr == '1' ||
            forgotStr.contains('漏') ||
            forgotStr == 'true' ||
            forgotStr == 'yes') {
          isForgotPrevious = true;
        } else {
          isForgotPrevious = false;
          warnings.add(
            ImportWarning(
              line: i + 1,
              kind: ImportWarningKind.unknownBoolean,
              field: '是否漏记',
              rawValue: forgotStr,
              defaultValue: '否',
            ),
          );
        }

        // 油品
        var rawFuel = _getColValue(row, colMap['fuelType']) ?? FuelType.gas92;
        if (rawFuel.contains('92') || rawFuel.contains('E92')) {
          rawFuel = FuelType.gas92;
        } else if (rawFuel.contains('95') || rawFuel.contains('E95')) {
          rawFuel = FuelType.gas95;
        } else if (rawFuel.contains('98')) {
          rawFuel = FuelType.gas98;
        } else if (rawFuel.contains('柴') || rawFuel.contains('0#')) {
          rawFuel = FuelType.diesel;
        } else {
          rawFuel = FuelType.gas92;
        }

        // 优惠金额与油量警告灯（可选列）。小熊油耗原表没有独立优惠列时，
        // 用机显金额 - 实付金额推导，保留实际支付金额口径。
        final discountRaw = _getColValue(row, colMap['discountAmount']);
        if (discountRaw != null &&
            discountRaw.trim().isNotEmpty &&
            _parseNumber(discountRaw) == null) {
          warnings.add(
            ImportWarning(
              line: i + 1,
              kind: ImportWarningKind.unparseableNumber,
              field: '优惠金额',
              rawValue: discountRaw,
            ),
          );
        }
        final explicitDiscount = _parseNumber(discountRaw);
        final discountAmount =
            explicitDiscount ??
            (displayTotalPrice != null && displayTotalPrice > totalPrice + 0.005
                ? double.parse(
                    (displayTotalPrice - totalPrice).toStringAsFixed(2),
                  )
                : null);
        final warningLightRaw = _getColValue(
          row,
          colMap['fuelWarningLight'],
        )?.toLowerCase();
        bool? fuelWarningLightOn;
        if (warningLightRaw != null && warningLightRaw.isNotEmpty) {
          if (warningLightRaw.contains('否') ||
              warningLightRaw.contains('不') ||
              warningLightRaw == '0' ||
              warningLightRaw.contains('未') ||
              warningLightRaw.contains('没') ||
              warningLightRaw == 'false' ||
              warningLightRaw == 'no') {
            fuelWarningLightOn = false;
          } else if (warningLightRaw.contains('是') ||
              warningLightRaw == '1' ||
              warningLightRaw.contains('亮') ||
              warningLightRaw == 'true' ||
              warningLightRaw == 'yes') {
            fuelWarningLightOn = true;
          } else {
            fuelWarningLightOn = null;
            warnings.add(
              ImportWarning(
                line: i + 1,
                kind: ImportWarningKind.unknownBoolean,
                field: '油量警告灯',
                rawValue: warningLightRaw,
                defaultValue: '未记录',
              ),
            );
          }
        }

        // 源油耗：只作为参考保存，不参与本地周期计算。
        // 小熊油耗的 -1.00 与"数据丢失，预估"必须分级，不能当成真实值。
        final sourceConsumptionRaw =
            _getColValue(row, colMap['sourceFuelConsumption']) ??
            _getColValue(row, colMap['fuelConsumption']);
        final parsedSourceConsumption = _parseNumber(sourceConsumptionRaw);
        double? sourceFuelConsumption;
        String? sourceDataQuality;
        if (sourceConsumptionRaw != null &&
            sourceConsumptionRaw.trim().isNotEmpty) {
          if (sourceConsumptionRaw.contains('预估') ||
              sourceConsumptionRaw.contains('估算') ||
              sourceConsumptionRaw.contains('丢失')) {
            sourceDataQuality = SourceDataQuality.estimated;
          }
          if (parsedSourceConsumption != null && parsedSourceConsumption > 0) {
            sourceFuelConsumption = parsedSourceConsumption;
          } else {
            // -1.00、0 或无法解析：源文件明确表示不可用
            sourceDataQuality ??= SourceDataQuality.unavailable;
          }
          final explicitQuality = _getColValue(
            row,
            colMap['sourceDataQuality'],
          );
          if (explicitQuality != null && explicitQuality.trim().isNotEmpty) {
            const accepted = {
              SourceDataQuality.reported,
              SourceDataQuality.estimated,
              SourceDataQuality.unavailable,
            };
            final normalizedQuality = explicitQuality.trim().toLowerCase();
            if (accepted.contains(normalizedQuality)) {
              sourceDataQuality = normalizedQuality;
            } else {
              sourceDataQuality = SourceDataQuality.unavailable;
              warnings.add(
                ImportWarning(
                  line: i + 1,
                  kind: ImportWarningKind.unknownValue,
                  field: '源数据质量',
                  rawValue: explicitQuality,
                  defaultValue: SourceDataQuality.unavailable,
                ),
              );
            }
          } else {
            sourceDataQuality ??= sourceFuelConsumption != null
                ? SourceDataQuality.reported
                : SourceDataQuality.unavailable;
          }
        }

        final gasStation = _getColValue(row, colMap['gasStation']);
        final note = _getColValue(row, colMap['note']);

        parsedList.add(
          RefuelRecordModel(
            id: const Uuid().v4(),
            vehicleId: vehicleId,
            refuelDate: refuelDate,
            mileage: mileage,
            fuelAmount: fuelAmount,
            unitPrice: unitPrice,
            totalPrice: totalPrice,
            fuelType: rawFuel,
            gasStation:
                (gasStation != null &&
                    gasStation.isNotEmpty &&
                    gasStation != 'nan')
                ? gasStation
                : null,
            isFullTank: isFullTank,
            isForgotPrevious: isForgotPrevious,
            discountAmount: discountAmount,
            fuelWarningLightOn: fuelWarningLightOn,
            note: (note != null && note.isNotEmpty && note != 'nan')
                ? note
                : null,
            sourceFuelConsumption: sourceFuelConsumption,
            sourceDataQuality: sourceDataQuality,
          ),
        );
      } catch (e) {
        skipped++;
      }
    }

    return ImportResult(
      success: parsedList.isNotEmpty,
      totalCount: rows.length - startIndex,
      validCount: parsedList.length,
      skippedCount: skipped,
      parsedRecords: parsedList,
      warnings: warnings,
      errorMessage: parsedList.isEmpty ? '未能成功提取到有效加油记录' : null,
    );
  }

  /// 导出为小熊油耗兼容的标准 CSV 文本
  static String exportToCsv(List<RefuelRecordModel> records) {
    final buffer = StringBuffer();
    // 写入标准小熊油耗兼容表头
    buffer.writeln(
      '时间,当前里程,加油量,单价,金额,是否加满,是否漏记,油品,加油站,百公里油耗,每公里花费,优惠金额,油量警告灯,备注,源油耗,源数据质量',
    );

    for (final r in records) {
      final date = DateFormatter.formatYmdHm(r.refuelDate);
      final mileage = r.mileage.toStringAsFixed(1);
      final amount = r.fuelAmount.toStringAsFixed(2);
      final price = r.unitPrice.toStringAsFixed(2);
      final total = r.totalPrice.toStringAsFixed(2);
      final isFull = r.isFullTank ? '是' : '否';
      final isForgot = r.isForgotPrevious ? '是' : '否';
      final fuel = _escapeCsv(r.fuelType);
      final station = _escapeCsv(r.gasStation ?? '');
      final consumption = r.fuelConsumption?.toStringAsFixed(2) ?? '';
      final costKm = r.costPerKm?.toStringAsFixed(2) ?? '';
      final discount = r.discountAmount?.toStringAsFixed(2) ?? '';
      final warningLight = r.fuelWarningLightOn == null
          ? ''
          : (r.fuelWarningLightOn! ? '是' : '否');
      final note = _escapeCsv(r.note ?? '');
      final sourceConsumption =
          r.sourceFuelConsumption?.toStringAsFixed(2) ?? '';
      final sourceQuality = r.sourceDataQuality ?? '';

      buffer.writeln(
        '$date,$mileage,$amount,$price,$total,$isFull,$isForgot,$fuel,$station,$consumption,$costKm,$discount,$warningLight,$note,$sourceConsumption,$sourceQuality',
      );
    }

    return buffer.toString();
  }

  /// 智能表头字段匹配
  static Map<String, int> _detectColumns(List<String> headers) {
    final Map<String, int> map = {};

    // 首个匹配生效，避免同义词列相互覆盖
    void assign(String key, int index) {
      if (!map.containsKey(key)) {
        map[key] = index;
      }
    }

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].trim().toLowerCase();
      if (h.contains('时间') ||
          h.contains('日期') ||
          h == 'date' ||
          h == 'time' ||
          h.contains('加油时间')) {
        assign('date', i);
      } else if (h.contains('警告灯') || h.contains('油灯') || h.contains('亮灯')) {
        // 必须先于加油量分支："油量警告灯" 含 "油量"
        assign('fuelWarningLight', i);
      } else if (h.contains('优惠')) {
        // 必须先于总价分支："优惠金额" 含 "金额"
        assign('discountAmount', i);
      } else if (h.contains('当前里程') ||
          h.contains('总里程') ||
          h.contains('里程') ||
          h.contains('表显') ||
          h == 'mileage' ||
          h == 'odometer') {
        assign('mileage', i);
      } else if (h.contains('加油量') ||
          h.contains('升数') ||
          h.contains('油量') ||
          h.contains('容量') ||
          h == 'amount' ||
          h == 'volume' ||
          h == 'liters') {
        assign('fuelAmount', i);
      } else if (h.contains('单价') ||
          h.contains('油价') ||
          h == 'price' ||
          h == 'unit_price') {
        assign('unitPrice', i);
      } else if (h.contains('源油耗') || h.contains('原始油耗')) {
        // 必须先于下方泛化的"油耗"分支，否则会被"百公里油耗"占位
        assign('sourceFuelConsumption', i);
      } else if (h.contains('数据质量')) {
        assign('sourceDataQuality', i);
      } else if (h.contains('百公里油耗') || h.contains('油耗') || h == 'l/100km') {
        // 计算值列（本应用导出表头）：导入后由计算器重算，单独登记避免误占
        assign('fuelConsumption', i);
      } else if (h.contains('每公里花费') ||
          h.contains('每公里成本') ||
          h.contains('公里花费')) {
        // 计算值列：必须先于下方 "花费" 关键词判断，否则会抢占总价列
        assign('costPerKm', i);
      } else if (h.contains('机显金额') || h.contains('显示金额')) {
        // 机显金额不是实际支出；独立保存用于推导优惠金额。
        assign('displayTotalPrice', i);
      } else if (h.contains('实付') ||
          h.contains('金额') ||
          h.contains('总额') ||
          h.contains('花费') ||
          h == 'total' ||
          h == 'cost') {
        // 必须在“机显金额”之后，且实付金额优先于泛化的金额匹配。
        assign('totalPrice', i);
      } else if (h.contains('满') ||
          h == 'is_full' ||
          h == 'isfull' ||
          h.contains('加满')) {
        assign('isFullTank', i);
      } else if (h.contains('漏') ||
          h == 'forgot' ||
          h == 'is_forgot' ||
          h.contains('漏记')) {
        assign('isForgotPrevious', i);
      } else if (h.contains('油品') ||
          h.contains('标号') ||
          h.contains('油号') ||
          h == 'type' ||
          h == 'fuel_type') {
        assign('fuelType', i);
      } else if (h.contains('站') ||
          h == 'station' ||
          h == 'gas_station' ||
          h.contains('油站')) {
        assign('gasStation', i);
      } else if (h.contains('备注') ||
          h == 'note' ||
          h == 'remark' ||
          h.contains('说明')) {
        assign('note', i);
      }
    }

    return map;
  }

  /// 基于单行样本数据特征自动推导各列
  static Map<String, int> _heuristicDetectColumns(List<String> sampleRow) {
    final Map<String, int> map = {};

    for (int i = 0; i < sampleRow.length; i++) {
      final val = sampleRow[i].trim();
      if (val.isEmpty) continue;

      // 1. 日期判断
      if (!map.containsKey('date') && DateFormatter.tryParse(val) != null) {
        map['date'] = i;
        continue;
      }

      // 2. 油品判断
      if (!map.containsKey('fuelType') &&
          (val.contains('92') ||
              val.contains('95') ||
              val.contains('98') ||
              val.contains('柴油') ||
              val.contains('电'))) {
        map['fuelType'] = i;
        continue;
      }

      // 3. 数字类型判断
      final numVal = _parseNumber(val);
      if (numVal != null) {
        // 里程列：优先大数值；索引 1 处排除常见单价/油量量级，防止把油价当里程
        if (!map.containsKey('mileage') &&
            numVal >= 0 &&
            (numVal > 100 || (i == 1 && numVal > 15))) {
          map['mileage'] = i;
        } else if (!map.containsKey('unitPrice') &&
            numVal >= 4.0 &&
            numVal <= 15.0) {
          map['unitPrice'] = i;
        } else if (!map.containsKey('fuelAmount') &&
            numVal >= 2.0 &&
            numVal <= 150.0) {
          map['fuelAmount'] = i;
        } else if (!map.containsKey('totalPrice') && numVal > 30.0) {
          map['totalPrice'] = i;
        }
      }
    }

    return map;
  }

  /// 标准小熊油耗导出的 13 列布局（无表头时的位置兜底映射）。
  ///
  /// 列顺序与真实导出文件一致：
  /// 日期时间, 总里程, 机显单价, 加油量, 机显金额, 实付金额,
  /// 油号, 加满, 亮灯, 漏记, 油耗, 加油站名称, 备注。
  ///
  /// 标准布局没有独立优惠列：优惠金额由“机显金额 - 实付金额”推导。
  static const Map<String, int> _standardColumnLayout = {
    'date': 0,
    'mileage': 1,
    'unitPrice': 2,
    'fuelAmount': 3,
    'displayTotalPrice': 4,
    'totalPrice': 5,
    'fuelType': 6,
    'isFullTank': 7,
    'fuelWarningLight': 8,
    'isForgotPrevious': 9,
    'sourceFuelConsumption': 10,
    'gasStation': 11,
    'note': 12,
  };

  /// 标准 13 列位置兜底的结果：列映射与确认后的数据起始行
  ///
  /// 尝试按标准小熊油耗 13 列布局解析。首行本身可能就是数据（无表头
  /// 文件，如日期为 Excel 序列数时无法通过文本日期识别），也可能是
  /// 乱码表头；优先按“首行即数据”校验，失败再退回既有起点。
  /// 两个候选都无法通过校验时返回 null。
  static ({Map<String, int> columnMap, int startIndex})?
  _standardColumnFallback(List<List<String>> rows, int currentStart) {
    final candidates = currentStart == 0
        ? const <int>[0]
        : <int>[0, currentStart];
    for (final start in candidates) {
      if (_validateStandardThirteenColumns(rows, start)) {
        _convertSerialDateColumn(rows, start);
        return (
          columnMap: Map<String, int>.from(_standardColumnLayout),
          startIndex: start,
        );
      }
    }
    return null;
  }

  /// 校验从 [start] 开始的数据行（最多抽样 5 行）是否全部符合
  /// 标准 13 列布局的列数与字段类型。
  static bool _validateStandardThirteenColumns(
    List<List<String>> rows,
    int start,
  ) {
    if (start < 0 || start >= rows.length) return false;
    final sampleEnd = start + 5 > rows.length ? rows.length : start + 5;
    var sampled = 0;
    for (int i = start; i < sampleEnd; i++) {
      final row = rows[i];
      if (row.every((c) => c.trim().isEmpty)) continue;
      sampled++;
      if (!_rowMatchesStandardLayout(row)) return false;
    }
    return sampled > 0;
  }

  /// 校验单行是否符合标准 13 列布局的列数与字段类型。
  ///
  /// 核心列（日期、里程、加油量、价格、油号、布尔列）全部强校验；
  /// 站名与备注为自由文本不校验；源油耗允许“不可用”标记文本。
  static bool _rowMatchesStandardLayout(List<String> row) {
    // 列数校验：必须至少 13 列，且第 13 列之后不允许再出现非空内容
    if (row.length < 13) return false;
    for (int c = 13; c < row.length; c++) {
      if (row[c].trim().isNotEmpty) return false;
    }

    String cell(int i) => row[i].trim();

    // 0 日期时间：文本日期或 Excel 日期序列数
    final dateCell = cell(0);
    final isTextDate = DateFormatter.tryParse(dateCell) != null;
    final serial = double.tryParse(dateCell);
    final isSerialDate =
        !isTextDate &&
        serial != null &&
        serial >= _excelSerialMin &&
        serial <= _excelSerialMax;
    if (!isTextDate && !isSerialDate) return false;

    // 1 总里程：非负数字
    final mileage = _parseNumber(cell(1));
    if (mileage == null || mileage < 0) return false;

    // 2 机显单价 / 5 实付金额：非空时必须是正数，且至少一列有价格
    final unitPrice = _parseNumber(cell(2));
    if (cell(2).isNotEmpty && (unitPrice == null || unitPrice <= 0)) {
      return false;
    }
    final totalPrice = _parseNumber(cell(5));
    if (cell(5).isNotEmpty && (totalPrice == null || totalPrice <= 0)) {
      return false;
    }
    final hasUnitPrice = unitPrice != null && unitPrice > 0;
    final hasTotalPrice = totalPrice != null && totalPrice > 0;
    if (!hasUnitPrice && !hasTotalPrice) return false;

    // 3 加油量：正数
    final fuelAmount = _parseNumber(cell(3));
    if (fuelAmount == null || fuelAmount <= 0) return false;

    // 4 机显金额：可为空，非空时必须是数字
    if (cell(4).isNotEmpty && _parseNumber(cell(4)) == null) return false;

    // 6 油号：必须匹配已知油号样式
    if (!_looksLikeFuelType(cell(6))) return false;

    // 7/8/9 加满、亮灯、漏记：是/否样式，允许为空
    if (!_isBooleanLikeText(cell(7))) return false;
    if (!_isBooleanLikeText(cell(8))) return false;
    if (!_isBooleanLikeText(cell(9))) return false;

    // 10 源油耗：数字（含 -1 不可用标记）或“数据丢失，预估”说明，允许为空
    final sourceConsumption = cell(10);
    if (sourceConsumption.isNotEmpty &&
        _parseNumber(sourceConsumption) == null &&
        !sourceConsumption.contains('预估') &&
        !sourceConsumption.contains('估算') &&
        !sourceConsumption.contains('丢失')) {
      return false;
    }

    // 11 加油站名称 / 12 备注：自由文本，不做类型校验
    return true;
  }

  /// 把 [start] 起数据行首列的 Excel 日期序列数就地转换为文本日期。
  ///
  /// `_convertXlsDateColumn` 只在表头可识别时转换；无表头文件的
  /// 序列数必须在此转换，否则行解析会把它当非法日期整行跳过。
  static void _convertSerialDateColumn(List<List<String>> rows, int start) {
    for (int i = start; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final cell = row[0].trim();
      if (cell.isEmpty || DateFormatter.tryParse(cell) != null) continue;
      final serial = double.tryParse(cell);
      if (serial == null ||
          serial < _excelSerialMin ||
          serial > _excelSerialMax) {
        continue;
      }
      row[0] = _formatExcelSerial(serial);
    }
  }

  /// 油号样式：92/95/98（含 E92 等乙醇汽油）、柴油或 0# 柴油
  static bool _looksLikeFuelType(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    return v.contains('92') ||
        v.contains('95') ||
        v.contains('98') ||
        v.contains('柴') ||
        v.contains('0#');
  }

  /// 是否类布尔文本：与行解析认可的“是/否”词汇表一致，允许为空
  static bool _isBooleanLikeText(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return true;
    return v.contains('是') ||
        v.contains('否') ||
        v == '1' ||
        v == '0' ||
        v.contains('满') ||
        v.contains('未') ||
        v.contains('没') ||
        v.contains('漏') ||
        v == 'true' ||
        v == 'false' ||
        v == 'yes' ||
        v == 'no';
  }

  /// 嗅探分隔符
  static String _detectDelimiter(String line) {
    final commas = ','.allMatches(line).length;
    final tabs = '\t'.allMatches(line).length;
    final semicolons = ';'.allMatches(line).length;

    if (tabs > commas && tabs > semicolons) return '\t';
    if (semicolons > commas && semicolons > tabs) return ';';
    return ',';
  }

  /// 按 RFC 4180 规则切分记录，允许引号字段跨越多行。
  static List<String> _splitCsvRecords(String content) {
    final records = <String>[];
    final sb = StringBuffer();
    var insideQuote = false;

    for (var i = 0; i < content.length; i++) {
      final char = content[i];
      if (char == '"') {
        if (insideQuote && i + 1 < content.length && content[i + 1] == '"') {
          sb.write('""');
          i++;
        } else {
          insideQuote = !insideQuote;
          sb.write(char);
        }
      } else if (char == '\n' && !insideQuote) {
        records.add(sb.toString());
        sb.clear();
      } else {
        sb.write(char);
      }
    }
    if (sb.length > 0) records.add(sb.toString());
    return records;
  }

  /// 切分 CSV 行并还原引号字段中的转义双引号。
  static List<String> _splitCsvLine(String line, {String delimiter = ','}) {
    final result = <String>[];
    final sb = StringBuffer();
    var insideQuote = false;
    var fieldStarted = false;
    var fieldWasQuoted = false;

    void addField() {
      result.add(fieldWasQuoted ? sb.toString() : sb.toString().trim());
      sb.clear();
      fieldStarted = false;
      fieldWasQuoted = false;
    }

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (insideQuote) {
          if (i + 1 < line.length && line[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            insideQuote = false;
          }
        } else if (!fieldStarted && sb.length == 0) {
          insideQuote = true;
          fieldStarted = true;
          fieldWasQuoted = true;
        } else {
          sb.write(char);
          fieldStarted = true;
        }
      } else if (char == delimiter && !insideQuote) {
        addField();
      } else {
        sb.write(char);
        fieldStarted = true;
      }
    }
    addField();
    return result;
  }

  static String? _getColValue(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return null;
    return row[index].trim();
  }

  /// 解析带单位、货币符号或千位分隔符的数字，同时保留负号。
  /// 数字形状：允许可选负号、整数或小数、可选科学计数法。
  ///
  /// 必须完整匹配。此前实现把所有非数字字符删除，会把 `12abc34`
  /// 变成 `1234`，把错误数据静默伪装成有效数字。
  static final RegExp _numericShape = RegExp(
    r'^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$',
  );

  static double? _parseNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    var normalized = value.trim().replaceAll(',', '').replaceAll(' ', '');
    if (normalized.startsWith('(') && normalized.endsWith(')')) {
      normalized = '-${normalized.substring(1, normalized.length - 1)}';
    }
    // 仅剥离首尾的货币符号与常见单位，中间出现的任何非数字字符都视为脏值
    normalized = normalized.replaceFirst(RegExp(r'^[¥￥$€£]'), '');
    normalized = normalized.replaceFirst(
      RegExp(r'(?:l|升|km|公里|元)$', caseSensitive: false),
      '',
    );

    if (!_numericShape.hasMatch(normalized)) return null;
    final result = double.tryParse(normalized);
    return result != null && result.isFinite ? result : null;
  }

  /// 按 RFC 4180 规则转义 CSV 字段，避免站名/备注中的逗号破坏列结构。
  static String _escapeCsv(String value) {
    if (!value.contains(RegExp(r'[,"\r\n]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  /// 检查文件头部是否为 Microsoft CFB (Compound File Binary) 格式
  static bool _isCfbExcel(List<int> bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0 &&
        bytes[4] == 0xA1 &&
        bytes[5] == 0xB1 &&
        bytes[6] == 0x1A &&
        bytes[7] == 0xE1;
  }

  /// 原生纯 Dart 解析 Microsoft Excel BIFF8 (.xls) 文件流
  static List<List<String>>? _parseCfbXls(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final bd = ByteData.sublistView(data);

    if (data.length < 512) return null;

    final sectorShift = bd.getUint16(30, Endian.little);
    final sectorSize = 1 << sectorShift;
    if (sectorSize <= 0 || sectorSize > 4096) return null;

    // 读取 FAT Sector IDs
    final List<int> fatSecIds = [];
    for (int i = 0; i < 109; i++) {
      final secId = bd.getUint32(76 + i * 4, Endian.little);
      if (secId < 0xFFFFFFFC) {
        fatSecIds.add(secId);
      }
    }

    // 构建 FAT 映射表
    final List<int> fat = [];
    for (final secId in fatSecIds) {
      final offset = (secId + 1) * sectorSize;
      if (offset + sectorSize > data.length) break;
      for (int p = 0; p < sectorSize; p += 4) {
        fat.add(bd.getUint32(offset + p, Endian.little));
      }
    }

    // 读取 Directory 目录流
    final dirSecId = bd.getUint32(48, Endian.little);
    int curr = dirSecId;

    int? workbookSec;
    int workbookSize = 0;

    final visitedDirectory = <int>{};
    var directorySector = dirSecId;
    final directoryBytes = BytesBuilder();
    while (directorySector < fat.length &&
        directorySector < 0xFFFFFFFC &&
        visitedDirectory.add(directorySector)) {
      final offset = (directorySector + 1) * sectorSize;
      if (offset + sectorSize > data.length) break;
      directoryBytes.add(data.sublist(offset, offset + sectorSize));
      directorySector = fat[directorySector];
    }
    final dirBytes = directoryBytes.toBytes();
    if (dirBytes.length < 128) return null;
    final dirBd = ByteData.sublistView(dirBytes);

    for (int i = 0; i + 128 <= dirBytes.length; i += 128) {
      final nameLen = dirBd.getUint16(i + 64, Endian.little);
      if (nameLen < 2 || nameLen > 64 || nameLen.isOdd) continue;
      final rawNameBytes = dirBytes.sublist(i, i + nameLen);
      final name = String.fromCharCodes(
        Uint16List.fromList([
          for (int p = 0; p + 1 < rawNameBytes.length; p += 2)
            rawNameBytes[p] | (rawNameBytes[p + 1] << 8),
        ]),
      ).replaceAll('\x00', '');

      if (name == 'Workbook' || name == 'Book') {
        workbookSec = dirBd.getUint32(i + 116, Endian.little);
        workbookSize = dirBd.getUint32(i + 120, Endian.little);
        break;
      }
    }

    if (workbookSec == null || workbookSize <= 0) return null;

    // 读取 Workbook 数据流，链路遇到循环或越界时安全终止。
    final BytesBuilder wbBuilder = BytesBuilder();
    final visitedWorkbook = <int>{};
    curr = workbookSec;
    while (curr < fat.length &&
        curr < 0xFFFFFFFC &&
        wbBuilder.length < workbookSize &&
        visitedWorkbook.add(curr)) {
      final offset = (curr + 1) * sectorSize;
      if (offset + sectorSize > data.length) break;
      final remaining = workbookSize - wbBuilder.length;
      wbBuilder.add(
        data.sublist(
          offset,
          offset + (remaining < sectorSize ? remaining : sectorSize),
        ),
      );
      curr = fat[curr];
    }

    final wbBytes = wbBuilder.toBytes();
    if (wbBytes.isEmpty || wbBytes.length < workbookSize) return null;

    return _parseBiffWorkbook(wbBytes);
  }

  /// 解析 BIFF8 Workbook 数据记录
  static List<List<String>> _parseBiffWorkbook(Uint8List wbBytes) {
    final bd = ByteData.sublistView(wbBytes);
    int pos = 0;

    final List<String> sst = [];
    final Map<int, Map<int, String>> cellMap = {}; // row -> col -> string_value

    while (pos + 4 <= wbBytes.length) {
      final rtype = bd.getUint16(pos, Endian.little);
      final rlen = bd.getUint16(pos + 2, Endian.little);
      pos += 4;

      if (pos + rlen > wbBytes.length) break;
      final recOffset = pos;
      pos += rlen;

      if (rtype == 0x00FC) {
        // SST (Shared String Table)
        if (rlen >= 8) {
          final uniqueStrings = bd.getUint32(recOffset + 4, Endian.little);
          int p = recOffset + 8;
          for (int s = 0; s < uniqueStrings && p + 3 <= recOffset + rlen; s++) {
            final cch = bd.getUint16(p, Endian.little);
            final flags = wbBytes[p + 2];
            p += 3;
            final is16Bit = (flags & 0x01) != 0;
            if (is16Bit) {
              final byteLen = cch * 2;
              if (p + byteLen > recOffset + rlen) break;
              final rawStr = wbBytes.sublist(p, p + byteLen);
              final str = String.fromCharCodes(
                Uint16List.view(
                  rawStr.buffer,
                  rawStr.offsetInBytes,
                  rawStr.lengthInBytes ~/ 2,
                ),
              );
              sst.add(str);
              p += byteLen;
            } else {
              final byteLen = cch;
              if (p + byteLen > recOffset + rlen) break;
              final str = latin1.decode(wbBytes.sublist(p, p + byteLen));
              sst.add(str);
              p += byteLen;
            }
          }
        }
      } else if (rtype == 0x00FD) {
        // LABELSST
        if (rlen >= 10) {
          final row = bd.getUint16(recOffset, Endian.little);
          final col = bd.getUint16(recOffset + 2, Endian.little);
          final sstIdx = bd.getUint32(recOffset + 6, Endian.little);
          if (sstIdx < sst.length) {
            cellMap.putIfAbsent(row, () => {})[col] = sst[sstIdx];
          }
        }
      } else if (rtype == 0x0203) {
        // NUMBER (IEEE 754 float64)
        if (rlen >= 14) {
          final row = bd.getUint16(recOffset, Endian.little);
          final col = bd.getUint16(recOffset + 2, Endian.little);
          final val = bd.getFloat64(recOffset + 6, Endian.little);
          cellMap.putIfAbsent(row, () => {})[col] = val.toString();
        }
      } else if (rtype == 0x027E) {
        // RK
        if (rlen >= 10) {
          final row = bd.getUint16(recOffset, Endian.little);
          final col = bd.getUint16(recOffset + 2, Endian.little);
          final rkVal = bd.getInt32(recOffset + 6, Endian.little);
          cellMap.putIfAbsent(row, () => {})[col] = _decodeRk(rkVal).toString();
        }
      } else if (rtype == 0x00BD) {
        // MULRK
        if (rlen >= 6) {
          final row = bd.getUint16(recOffset, Endian.little);
          final firstCol = bd.getUint16(recOffset + 2, Endian.little);
          final lastCol = bd.getUint16(recOffset + rlen - 2, Endian.little);
          int p = recOffset + 4;
          int col = firstCol;
          while (col <= lastCol && p + 6 <= recOffset + rlen) {
            final rkVal = bd.getInt32(p + 2, Endian.little);
            cellMap.putIfAbsent(row, () => {})[col] = _decodeRk(
              rkVal,
            ).toString();
            p += 6;
            col++;
          }
        }
      }
    }

    if (cellMap.isEmpty) return [];

    final maxRow = cellMap.keys.reduce((a, b) => a > b ? a : b);
    if (maxRow >= _maxXlsRows) return [];
    int maxCol = 0;
    for (final rowCols in cellMap.values) {
      for (final c in rowCols.keys) {
        if (c > maxCol) maxCol = c;
      }
    }
    if (maxCol >= _maxXlsColumns) return [];

    final List<List<String>> result = [];
    for (int r = 0; r <= maxRow; r++) {
      final List<String> rowList = [];
      final cols = cellMap[r] ?? {};
      for (int c = 0; c <= maxCol; c++) {
        rowList.add(cols[c] ?? '');
      }
      result.add(rowList);
    }

    return result;
  }

  /// 解码 BIFF8 RK 压缩数值
  static double _decodeRk(int rkVal) {
    if ((rkVal & 0x02) != 0) {
      final val = (rkVal >> 2).toDouble();
      return (rkVal & 0x01) != 0 ? val / 100.0 : val;
    } else {
      final bd = ByteData(8);
      bd.setUint32(4, rkVal & 0xFFFFFFFC, Endian.little);
      final val = bd.getFloat64(0, Endian.little);
      return (rkVal & 0x01) != 0 ? val / 100.0 : val;
    }
  }
}
