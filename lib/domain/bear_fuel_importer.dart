import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../data/models/refuel_record_model.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/date_formatter.dart';

/// 导入解析结果模型
class ImportResult {
  final bool success;
  final int totalCount;
  final int validCount;
  final int skippedCount;
  final String? errorMessage;
  final List<RefuelRecordModel> parsedRecords;

  ImportResult({
    required this.success,
    this.totalCount = 0,
    this.validCount = 0,
    this.skippedCount = 0,
    this.errorMessage,
    this.parsedRecords = const [],
  });
}

/// 小熊油耗全格式数据导入与导出引擎（全面支持 .csv, .xls, .xlsx, .tsv, .txt）
class BearFuelImporter {
  /// 模版示例数据（用于用户直接测试体验）
  static const String sampleCsvData = '''时间,当前里程,加油量,单价,金额,是否加满,是否漏记,油品,加油站,备注
2026-01-05 08:30,10000,48.5,8.12,393.82,是,否,92# 汽油,中石化朝阳路加油站,首充加满基准
2026-01-18 17:45,10620,44.2,8.15,360.23,是,否,92# 汽油,中石油北苑站,上下班通勤
2026-02-02 12:10,10950,20.0,8.20,164.00,否,否,92# 汽油,壳牌立汤路站,临时补油
2026-02-15 09:20,11380,32.8,8.25,270.60,是,否,92# 汽油,中石化望京站,春节高速自驾
2026-03-01 19:00,11900,41.0,8.30,340.30,是,否,92# 汽油,中石化朝阳路加油站,常态用车''';

  /// 解析从手机本地文件读取的原始字节流（智能识别 XLS 格式与 UTF-8 / GBK 编码文本）
  static ImportResult parseBytes(List<int> bytes, String vehicleId) {
    if (bytes.isEmpty) {
      return ImportResult(success: false, errorMessage: '选取的导入文件为空');
    }

    // 1. 检查是否为 Microsoft Excel 二进制文件 (.xls / CFB BIFF8 格式)
    if (_isCfbExcel(bytes)) {
      try {
        final rows = _parseCfbXls(bytes);
        if (rows != null && rows.isNotEmpty) {
          return _parseRows(rows, vehicleId);
        }
      } catch (e) {
        // 若 XLS 结构解析异常，继续向下尝试文本解码降级
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
      // 3. 若非标准 UTF-8（如 Windows Excel 默认导出的 GBK/GB2312 编码），使用容错 latin1/转码
      try {
        content = const Utf8Decoder(allowMalformed: true).convert(bytes);
      } catch (e) {
        return ImportResult(success: false, errorMessage: '文件编码解析失败: $e');
      }
    }

    return parseCsv(content, vehicleId);
  }

  /// 解析小熊油耗 CSV/TSV 文本格式字符串
  static ImportResult parseCsv(String csvContent, String vehicleId) {
    if (csvContent.trim().isEmpty) {
      return ImportResult(success: false, errorMessage: 'CSV 内容为空');
    }

    try {
      final lines = csvContent
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

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

    // 2. 若首行表头匹配不完整（如 Excel/CSV 无表头或表头乱码），尝试位置推导与特征匹配
    if (!colMap.containsKey('mileage') || !colMap.containsKey('fuelAmount')) {
      // 检查首行是否其实就是数据行（例如首列就是日期时间）
      final isFirstRowData = DateFormatter.tryParse(headers.first) != null;
      if (isFirstRowData) {
        startIndex = 0;
        colMap = _heuristicDetectColumns(rows.first);
      } else if (rows.length > 1) {
        // 首行是乱码表头，根据第二行数据特征自动推导列索引
        colMap = _heuristicDetectColumns(rows[1]);
      }
    }

    // 3. 若仍无法推导核心列，执行默认标准小熊油耗 13 列位置兜底
    if (!colMap.containsKey('mileage') || !colMap.containsKey('fuelAmount')) {
      if (rows.first.length >= 7) {
        colMap['date'] = 0;
        colMap['mileage'] = 1;
        colMap['unitPrice'] = 2;
        colMap['fuelAmount'] = 3;
        colMap['totalPrice'] = 5; // 实付总金额
        colMap['fuelType'] = 6;
        colMap['isFullTank'] = 7;
        colMap['isForgotPrevious'] = 9;
        if (rows.first.length >= 12) colMap['gasStation'] = 11;
        if (rows.first.length >= 13) colMap['note'] = 12;
      }
    }

    if (!colMap.containsKey('mileage') || !colMap.containsKey('fuelAmount')) {
      return ImportResult(
        success: false,
        errorMessage: '表格缺少核心列（必须包含“当前里程”和“加油量/升数”）',
      );
    }

    final List<RefuelRecordModel> parsedList = [];
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
        final refuelDate = parsedDate ?? DateTime.now();

        // 单价与总价
        final priceStr = _getColValue(row, colMap['unitPrice']);
        final totalStr = _getColValue(row, colMap['totalPrice']);
        double unitPrice = _parseNumber(priceStr) ?? 0.0;
        double totalPrice = _parseNumber(totalStr) ?? 0.0;

        if (totalPrice <= 0 && unitPrice > 0) {
          totalPrice =
              double.parse((fuelAmount * unitPrice).toStringAsFixed(2));
        } else if (unitPrice <= 0 && totalPrice > 0) {
          unitPrice =
              double.parse((totalPrice / fuelAmount).toStringAsFixed(2));
        } else if (unitPrice <= 0 && totalPrice <= 0) {
          // 缺少价格时不能使用固定示例值，否则会把导入数据伪装成真实账目。
          skipped++;
          continue;
        }

        // 是否加满
        final fullStr = _getColValue(row, colMap['isFullTank'])?.toLowerCase();
        final isFullTank = (fullStr == null || fullStr.isEmpty)
            ? true
            : (fullStr.contains('是') ||
                fullStr == '1' ||
                fullStr.contains('满') ||
                fullStr == 'true' ||
                fullStr == 'yes');

        // 是否漏记
        final forgotStr =
            _getColValue(row, colMap['isForgotPrevious'])?.toLowerCase();
        final isForgotPrevious = (forgotStr == null || forgotStr.isEmpty)
            ? false
            : (forgotStr.contains('是') ||
                forgotStr == '1' ||
                forgotStr.contains('漏') ||
                forgotStr == 'true' ||
                forgotStr == 'yes');

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
            gasStation: (gasStation != null &&
                    gasStation.isNotEmpty &&
                    gasStation != 'nan')
                ? gasStation
                : null,
            isFullTank: isFullTank,
            isForgotPrevious: isForgotPrevious,
            note: (note != null && note.isNotEmpty && note != 'nan')
                ? note
                : null,
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
      errorMessage: parsedList.isEmpty ? '未能成功提取到有效加油记录' : null,
    );
  }

  /// 导出为小熊油耗兼容的标准 CSV 文本
  static String exportToCsv(List<RefuelRecordModel> records) {
    final buffer = StringBuffer();
    // 写入标准小熊油耗兼容表头
    buffer.writeln('时间,当前里程,加油量,单价,金额,是否加满,是否漏记,油品,加油站,百公里油耗,每公里花费,备注');

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
      final note = _escapeCsv(r.note ?? '');

      buffer.writeln(
          '$date,$mileage,$amount,$price,$total,$isFull,$isForgot,$fuel,$station,$consumption,$costKm,$note');
    }

    return buffer.toString();
  }

  /// 智能表头字段匹配
  static Map<String, int> _detectColumns(List<String> headers) {
    final Map<String, int> map = {};

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].trim().toLowerCase();
      if (h.contains('时间') ||
          h.contains('日期') ||
          h == 'date' ||
          h == 'time' ||
          h.contains('加油时间')) {
        map['date'] = i;
      } else if (h.contains('当前里程') ||
          h.contains('总里程') ||
          h.contains('里程') ||
          h.contains('表显') ||
          h == 'mileage' ||
          h == 'odometer') {
        map['mileage'] = i;
      } else if (h.contains('加油量') ||
          h.contains('升数') ||
          h.contains('油量') ||
          h.contains('容量') ||
          h == 'amount' ||
          h == 'volume' ||
          h == 'liters') {
        map['fuelAmount'] = i;
      } else if (h.contains('单价') ||
          h.contains('油价') ||
          h == 'price' ||
          h == 'unit_price') {
        map['unitPrice'] = i;
      } else if (h.contains('实付') ||
          h.contains('金额') ||
          h.contains('总额') ||
          h.contains('花费') ||
          h == 'total' ||
          h == 'cost') {
        map['totalPrice'] = i;
      } else if (h.contains('满') ||
          h == 'is_full' ||
          h == 'isfull' ||
          h.contains('加满')) {
        map['isFullTank'] = i;
      } else if (h.contains('漏') ||
          h == 'forgot' ||
          h == 'is_forgot' ||
          h.contains('漏记')) {
        map['isForgotPrevious'] = i;
      } else if (h.contains('油品') ||
          h.contains('标号') ||
          h.contains('油号') ||
          h == 'type' ||
          h == 'fuel_type') {
        map['fuelType'] = i;
      } else if (h.contains('站') ||
          h == 'station' ||
          h == 'gas_station' ||
          h.contains('油站')) {
        map['gasStation'] = i;
      } else if (h.contains('备注') ||
          h == 'note' ||
          h == 'remark' ||
          h.contains('说明')) {
        map['note'] = i;
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
        if (!map.containsKey('mileage') &&
            numVal >= 0 &&
            (i == 1 || numVal > 100)) {
          map['mileage'] = i;
        } else if (!map.containsKey('unitPrice') &&
            numVal >= 4.0 &&
            numVal <= 15.0 &&
            (i == 2 || i == 3)) {
          map['unitPrice'] = i;
        } else if (!map.containsKey('fuelAmount') &&
            numVal >= 2.0 &&
            numVal <= 150.0 &&
            (i == 3 || i == 2)) {
          map['fuelAmount'] = i;
        } else if (!map.containsKey('totalPrice') &&
            numVal > 30.0 &&
            (i == 4 || i == 5)) {
          map['totalPrice'] = i;
        }
      }
    }

    return map;
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

  /// 切分 CSV 行
  static List<String> _splitCsvLine(String line, {String delimiter = ','}) {
    final List<String> result = [];
    final sb = StringBuffer();
    bool insideQuote = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        insideQuote = !insideQuote;
      } else if (char == delimiter && !insideQuote) {
        result.add(sb.toString().trim());
        sb.clear();
      } else {
        sb.write(char);
      }
    }
    result.add(sb.toString().trim());
    return result;
  }

  static String? _getColValue(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return null;
    return row[index].trim();
  }

  /// 解析带单位、货币符号或千位分隔符的数字，同时保留负号。
  static double? _parseNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    var normalized = value.trim().replaceAll(',', '').replaceAll(' ', '');
    if (normalized.startsWith('(') && normalized.endsWith(')')) {
      normalized = '-${normalized.substring(1, normalized.length - 1)}';
    }
    normalized = normalized.replaceAll(RegExp(r'[^0-9eE+\-.]'), '');
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
    final BytesBuilder dirBuilder = BytesBuilder();
    int curr = dirSecId;
    while (curr < fat.length && curr < 0xFFFFFFFC) {
      final offset = (curr + 1) * sectorSize;
      if (offset + sectorSize > data.length) break;
      dirBuilder.add(data.sublist(offset, offset + sectorSize));
      curr = fat[curr];
    }

    final dirBytes = dirBuilder.toBytes();
    final dirBd = ByteData.sublistView(dirBytes);

    int? workbookSec;
    int workbookSize = 0;

    for (int i = 0; i + 128 <= dirBytes.length; i += 128) {
      final nameLen = dirBd.getUint16(i + 64, Endian.little);
      if (nameLen == 0) continue;
      final rawNameBytes = dirBytes.sublist(i, i + nameLen);
      final name = String.fromCharCodes(
        Uint16List.view(rawNameBytes.buffer, rawNameBytes.offsetInBytes,
            rawNameBytes.lengthInBytes ~/ 2),
      ).replaceAll('\x00', '');

      if (name == 'Workbook' || name == 'Book') {
        workbookSec = dirBd.getUint32(i + 116, Endian.little);
        workbookSize = dirBd.getUint32(i + 120, Endian.little);
        break;
      }
    }

    if (workbookSec == null) return null;

    // 读取 Workbook 数据流
    final BytesBuilder wbBuilder = BytesBuilder();
    curr = workbookSec;
    while (curr < fat.length &&
        curr < 0xFFFFFFFC &&
        wbBuilder.length < workbookSize) {
      final offset = (curr + 1) * sectorSize;
      if (offset + sectorSize > data.length) break;
      wbBuilder.add(data.sublist(offset, offset + sectorSize));
      curr = fat[curr];
    }

    final wbBytes = wbBuilder.toBytes();
    if (wbBytes.isEmpty) return null;

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
                Uint16List.view(rawStr.buffer, rawStr.offsetInBytes,
                    rawStr.lengthInBytes ~/ 2),
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
            cellMap.putIfAbsent(row, () => {})[col] =
                _decodeRk(rkVal).toString();
            p += 6;
            col++;
          }
        }
      }
    }

    if (cellMap.isEmpty) return [];

    final maxRow = cellMap.keys.reduce((a, b) => a > b ? a : b);
    int maxCol = 0;
    for (final rowCols in cellMap.values) {
      for (final c in rowCols.keys) {
        if (c > maxCol) maxCol = c;
      }
    }

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
