import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bearfuel/domain/pdf_report_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('第三阶段报表导出与分享测试 (Phase 3 Report & Share Tests)', () {
    test('1. PDF 文档装配与生成测试 (PdfReportGenerator)', () async {
      // 1x1 标准有效 PNG 图像字节流
      final samplePngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1F,
        0x15,
        0xC4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0A,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9C,
        0x63,
        0x00,
        0x01,
        0x00,
        0x00,
        0x05,
        0x00,
        0x01,
        0x0D,
        0x0A,
        0x2D,
        0xB4,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);

      final tempDir = Directory.systemTemp.createTempSync('bearfuel_test');
      final file = await PdfReportGenerator.generatePdfFromImage(
        imageBytes: samplePngBytes,
        fileName: 'test_audit_report.pdf',
        outputDirectory: tempDir,
      );

      expect(file.existsSync(), true);
      expect(file.path.endsWith('.pdf'), true);
      expect(file.lengthSync(), greaterThan(0));

      // 清理测试临时文件
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
